-- mod-version:4
--- Encoding: UTF-8 only for V1 (per product decision).
local core = require "core"
local Doc = require "core.doc"

local encoding = {}
encoding.DEFAULT = "utf-8"

function encoding.detect(raw)
  return "utf-8"
end

encoding.get_doc_encoding = function(doc)
  return "utf-8"
end

-- Record encoding on open; reject undecodable binary-ish files gently.
local old_load = Doc.load
function Doc:load(filename)
  self.encoding = "utf-8"
  local fp = assert(io.open(filename, "rb"))
  local raw = fp:read("*a") or ""
  fp:close()

  local info = system.get_file_info(filename)
  if info and info.size and info.size > 0 then
    -- invalid UTF-8 heuristic: high bytes that never form valid sequences
    local invalid = false
    local i, n = 1, math.min(#raw, 64 * 1024)
    while i <= n do
      local c = raw:byte(i)
      if c < 0x80 then
        i = i + 1
      elseif c >= 0xC2 and c <= 0xDF and i + 1 <= n then
        local c2 = raw:byte(i + 1)
        if c2 and c2 >= 0x80 and c2 <= 0xBF then i = i + 2 else invalid = true break end
      elseif c >= 0xE0 and c <= 0xEF and i + 2 <= n then
        local c2, c3 = raw:byte(i + 1), raw:byte(i + 2)
        if c2 and c3 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then
          i = i + 3
        else
          invalid = true
          break
        end
      elseif c >= 0xF0 and c <= 0xF4 and i + 3 <= n then
        local c2, c3, c4 = raw:byte(i + 1), raw:byte(i + 2), raw:byte(i + 3)
        if c2 and c3 and c4 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF and c4 >= 0x80 and c4 <= 0xBF then
          i = i + 4
        else
          invalid = true
          break
        end
      elseif c >= 0x80 then
        invalid = true
        break
      else
        i = i + 1
      end
    end
    if invalid then
      core.warn("%s may not be valid UTF-8; opened as raw bytes", filename)
    end
  end

  self:reset()
  self.lines = {}
  local text = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
  if raw:find("\r\n", 1, true) then self.crlf = true end
  if text == "" then
    table.insert(self.lines, "\n")
  else
    if text:sub(-1) ~= "\n" then text = text .. "\n" end
    local i = 1
    for line in text:gmatch("(.-)\n") do
      table.insert(self.lines, line .. "\n")
      self.highlighter.lines[i] = false
      i = i + 1
    end
  end
  if #self.lines == 0 then
    table.insert(self.lines, "\n")
  end
  self:reset_syntax()
  -- Large files: skip syntax highlight for responsiveness
  local config = require "core.config"
  if config.large_file_size and #raw > config.large_file_size then
    pcall(function()
      self.syntax = "plain text"
      self.highlighter:soft_reset()
    end)
    core.warn("Large file: syntax highlight off (%s)", filename)
  end
end

return encoding
