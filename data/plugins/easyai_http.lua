-- mod-version:4
--- Minimal OpenAI-compatible HTTP client via curl. Streaming SSE + cancel.
local core = require "core"

local http = {}

local function find_curl()
  local candidates = {
    "curl",
    "/usr/bin/curl",
    "/opt/homebrew/bin/curl",
    "C:/Windows/System32/curl.exe",
  }
  for _, c in ipairs(candidates) do
    local ok, p = pcall(process.start, { c, "--version" }, {
      stdin = process.REDIRECT_DISCARD,
      stdout = process.REDIRECT_PIPE,
      stderr = process.REDIRECT_DISCARD,
    })
    if ok and p then
      local code = p:wait(2)
      if code == 0 then return c end
    end
  end
  return "curl"
end

http.curl = find_curl()

local function json_escape(s)
  return (s:gsub("[%z\1-\31\\\"]", function(c)
    local map = {
      ['"'] = '\\"',
      ['\\'] = '\\\\',
      ['\n'] = '\\n',
      ['\r'] = '\\r',
      ['\t'] = '\\t',
      ['\b'] = '\\b',
      ['\f'] = '\\f',
    }
    return map[c] or string.format("\\u%04x", c:byte())
  end))
end

function http.json_escape(s)
  return json_escape(s)
end

function http.encode_chat_body(opts)
  local messages = opts.messages or {}
  local parts = { '{"model":"', json_escape(opts.model or ""), '","stream":true,"messages":[' }
  for i, m in ipairs(messages) do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = string.format(
      '{"role":"%s","content":"%s"}',
      json_escape(m.role or "user"),
      json_escape(m.content or "")
    )
  end
  parts[#parts + 1] = "]"
  if opts.temperature then
    parts[#parts + 1] = string.format(',"temperature":%s', tostring(opts.temperature))
  end
  if opts.max_tokens then
    parts[#parts + 1] = string.format(',"max_tokens":%d', math.floor(opts.max_tokens))
  end
  parts[#parts + 1] = "}"
  return table.concat(parts)
end

local function extract_delta_content(payload)
  local content = payload:match('"content"%s*:%s*"(.-)"%s*[,}]')
  if content then
    content = content:gsub('\\n', '\n'):gsub('\\t', '\t'):gsub('\\"', '"'):gsub('\\\\', '\\')
    return content
  end
  return nil
end

local function extract_error_message(payload)
  local msg = payload:match('"message"%s*:%s*"(.-)"')
  if msg then
    return msg:gsub('\\n', ' '):gsub('\\"', '"')
  end
  return payload:sub(1, 200)
end

---Start a streaming chat completion request.
---@param opts { url:string, api_key:string, model:string, messages:table }
---@param on_delta fun(text:string)
---@param on_done fun(ok:boolean, err:string|nil, full:string)
function http.stream_chat(opts, on_delta, on_done)
  local body = http.encode_chat_body(opts)
  local url = opts.url
  if not url:match("/chat/completions") then
    if url:sub(-1) == "/" then
      url = url .. "chat/completions"
    else
      url = url .. "/chat/completions"
    end
  end

  local args = {
    http.curl, "-sS", "-N", "--http1.1",
    "-X", "POST", url,
    "-H", "Content-Type: application/json",
  }
  if opts.api_key and opts.api_key ~= "" then
    args[#args + 1] = "-H"
    args[#args + 1] = "Authorization: Bearer " .. opts.api_key
  end
  args[#args + 1] = "--data-binary"
  args[#args + 1] = "@-"

  local job = { cancelled = false, output = "", done = false, err = nil, proc = nil }

  core.add_thread(function()
    local ok, proc_or_err = pcall(process.start, args, {
      stdin = process.REDIRECT_PIPE,
      stdout = process.REDIRECT_PIPE,
      stderr = process.REDIRECT_PIPE,
    })
    if not ok or not proc_or_err then
      job.done = true
      job.err = "Failed to start curl: " .. tostring(proc_or_err)
      on_done(false, job.err, "")
      return
    end
    local proc = proc_or_err
    job.proc = proc
    proc.stdin:write(body)
    proc.stdin:close()

    local buf = ""
    while true do
      if job.cancelled then
        pcall(function() proc:terminate() end)
        job.done = true
        on_done(false, "Cancelled", job.output)
        return
      end
      local chunk = proc.stdout:read(4096, { scan = 0.02 })
      if chunk and #chunk > 0 then
        buf = buf .. chunk
        while true do
          local nl = buf:find("\n")
          if not nl then break end
          local line = buf:sub(1, nl - 1)
          buf = buf:sub(nl + 1)
          line = line:gsub("\r$", "")
          if line:find("^data:%s*") then
            local data = line:gsub("^data:%s*", "")
            if data ~= "" and data ~= "[DONE]" then
              if data:find('"error"') then
                job.err = extract_error_message(data)
              else
                local piece = extract_delta_content(data)
                if piece and piece ~= "" then
                  job.output = job.output .. piece
                  on_delta(piece)
                end
              end
            end
          end
        end
      end
      if not proc:running() then
        local rest = proc.stdout:read(1024 * 64)
        if rest then
          buf = buf .. rest
          for line in buf:gmatch("([^\n]+)") do
            line = line:gsub("\r$", "")
            if line:find("^data:%s*") then
              local data = line:gsub("^data:%s*", "")
              if data ~= "" and data ~= "[DONE]" and not data:find('"error"') then
                local piece = extract_delta_content(data)
                if piece and piece ~= "" then
                  job.output = job.output .. piece
                  on_delta(piece)
                end
              end
            end
          end
        end
        local code = proc:returncode()
        local err_out = ""
        if code ~= 0 then
          err_out = proc.stderr:read(2048) or ""
        end
        job.done = true
        if job.err then
          on_done(false, job.err, job.output)
        elseif code ~= 0 and job.output == "" then
          on_done(false, ("Request failed (exit %s): %s"):format(tostring(code), err_out:gsub("\n", " "):sub(1, 200)), job.output)
        else
          on_done(true, nil, job.output)
        end
        return
      end
      coroutine.yield(0.02)
    end
  end)

  function job.cancel()
    job.cancelled = true
    if job.proc then
      pcall(function() job.proc:terminate() end)
    end
  end

  return job
end

return http
