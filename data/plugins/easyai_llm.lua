-- mod-version:4
--- LLM provider presets, one-time config dialog, and chat helpers.
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local style = require "core.style"
local View = require "core.view"
local http = require "plugins.easyai_http"

local llm = {}

llm.providers = {
  {
    id = "openai",
    name = "OpenAI",
    base_url = "https://api.openai.com/v1",
    model = "gpt-4o-mini",
    key_required = true,
  },
  {
    id = "deepseek",
    name = "DeepSeek",
    base_url = "https://api.deepseek.com/v1",
    model = "deepseek-chat",
    key_required = true,
  },
  {
    id = "kimi",
    name = "Kimi (Moonshot)",
    base_url = "https://api.moonshot.cn/v1",
    model = "moonshot-v1-8k",
    key_required = true,
  },
  {
    id = "tongyi",
    name = "通义千问",
    base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    model = "qwen-plus",
    key_required = true,
  },
  {
    id = "ollama",
    name = "本地 Ollama",
    base_url = "http://127.0.0.1:11434/v1",
    model = "qwen2.5:7b",
    key_required = false,
  },
  {
    id = "lmstudio",
    name = "本地 LM Studio",
    base_url = "http://127.0.0.1:1234/v1",
    model = "local-model",
    key_required = false,
  },
  {
    id = "custom",
    name = "自定义 (OpenAI 兼容)",
    base_url = "",
    model = "",
    key_required = true,
  },
}

local function config_path()
  return USERDIR .. PATHSEP .. "easyai_llm.lua"
end

-- Process redirect constants used by any legacy calls
local R_PIPE = process and process.REDIRECT_PIPE or 1
local R_DISCARD = process and process.REDIRECT_DISCARD or 3

function llm.load()
  local ok, t = pcall(dofile, config_path())
  if ok and type(t) == "table" then
    return t
  end
  return {}
end

function llm.save(cfg)
  local fp = io.open(config_path(), "w")
  if not fp then return false end
  fp:write("return {\n")
  fp:write(string.format("  provider=%q,\n", cfg.provider or ""))
  fp:write(string.format("  base_url=%q,\n", cfg.base_url or ""))
  fp:write(string.format("  model=%q,\n", cfg.model or ""))
  fp:write(string.format("  api_key=%q,\n", cfg.api_key or ""))
  fp:write("}\n")
  fp:close()
  return true
end

function llm.is_configured()
  local cfg = llm.load()
  return cfg.provider and cfg.base_url and cfg.model and (cfg.model ~= "")
end

function llm.get_provider(id)
  for _, p in ipairs(llm.providers) do
    if p.id == id then return p end
  end
  return nil
end

function llm.estimate_tokens(text)
  if not text then return 0, 0 end
  local n = #text
  -- rough: CJK ~1.5 char/token, Latin ~4 char/token
  local cjk = 0
  for _ in text:gmatch("[\128-\255]") do cjk = cjk + 1 end
  local latin = n - cjk
  local tokens = math.floor(cjk / 1.5 + latin / 4 + 1)
  return n, tokens
end

function llm.build_messages(action, context, user_question)
  local system_prompts = {
    summarize = "你是文本总结助手。用简洁中文总结用户提供的文本，抓住主旨与关键信息。只输出总结内容，不要多余寒暄。",
    analyze = "你是文本分析助手。从结构、论点、语气、受众与可改进点分析用户提供的文本。条理清晰，中文输出。",
    rewrite = "你是改写助手。在保持原意的前提下改进文本的清晰度、流畅度与表达。只输出改写后的全文，不要解释。",
    translate = "你是专业翻译助手。将用户提供的文本翻译成目标语言；若未指定目标语言，中文文本译为英文，非中文译为中文。只输出译文。",
    qa = "你是编辑器内的问答助手。根据提供的文档上下文回答问题。若上下文不足以回答，请明确说明。",
  }
  local sys = system_prompts[action] or system_prompts.qa
  local messages = {
    { role = "system", content = sys },
    { role = "user", content = context },
  }
  if action == "qa" and user_question and user_question ~= "" then
    messages = {
      { role = "system", content = sys },
      { role = "user", content = "文档/选中内容：\n" .. context .. "\n\n问题：" .. user_question },
    }
  end
  return messages
end

---Get context text from active doc: selection or full file.
function llm.get_context()
  local view = core.active_view
  if not view or not view.doc then
    return nil, "没有打开的文档"
  end
  local doc = view.doc
  local text = doc:get_selection_text(200000)
  local has_selection = text and text:match("%S")
  if not has_selection then
    text = table.concat(doc.lines)
  end
  if not text or not text:match("%S") then
    return nil, "文档为空"
  end
  local name = doc.filename or "未命名"
  local label = has_selection and "选中内容" or ("文件 " .. name)
  return string.format("[%s]\n%s", label, text), nil, has_selection
end

-- ---------------------------------------------------------------------------
-- Config modal
-- ---------------------------------------------------------------------------

local ConfigModal = View:extend()
ConfigModal.context = "application"

function ConfigModal:__tostring() return "EasyAIConfigModal" end

function ConfigModal:new()
  ConfigModal.super.new(self)
  self.scrollable = false
  local cfg = llm.load()
  local provider = cfg.provider or "deepseek"
  local preset = llm.get_provider(provider) or llm.providers[2]
  self.state = {
    provider_idx = 2,
    base_url = cfg.base_url or preset.base_url,
    model = cfg.model or preset.model,
    api_key = cfg.api_key or "",
    focus = "provider", -- provider | base_url | model | api_key
  }
  for i, p in ipairs(llm.providers) do
    if p.id == provider then self.state.provider_idx = i break end
  end
  self.visible = true
end

function ConfigModal:get_name() return "LLM 设置" end
function ConfigModal:get_filename() return "" end

local fields = {
  { key = "provider", label = "Provider" },
  { key = "base_url", label = "Base URL" },
  { key = "model", label = "模型名" },
  { key = "api_key", label = "API Key" },
}

function ConfigModal:get_name_box()
  local w = math.min(self.size.x - 40, 480 * SCALE)
  local h = 320 * SCALE
  local x = self.position.x + (self.size.x - w) / 2
  local y = self.position.y + (self.size.y - h) / 2
  return x, y, w, h
end

function ConfigModal:draw()
  -- dim overlay
  renderer.draw_rect(self.position.x, self.position.y, self.size.x, self.size.y, style.nagbar_dim or {0,0,0,140})
  local x, y, w, h = self:get_name_box()
  renderer.draw_rect(x, y, w, h, style.background2)
  renderer.draw_rect(x, y, w, h, { style.accent[1], style.accent[2], style.accent[3], 40 })
  -- border
  renderer.draw_rect(x, y, w, 1, style.divider)
  renderer.draw_rect(x, y + h - 1, w, 1, style.divider)
  renderer.draw_rect(x, y, 1, h, style.divider)
  renderer.draw_rect(x + w - 1, y, 1, h, style.divider)

  local pad = 16 * SCALE
  local ty = y + pad
  renderer.draw_text(style.big_font:copy(math.floor(22 * SCALE)), "配置 LLM Provider", x + pad, ty, style.accent)
  ty = ty + style.big_font:get_height() * 0.6 + 12 * SCALE
  renderer.draw_text(style.font, "只需配置一次。所有请求均由你手动触发。", x + pad, ty, style.dim)
  ty = ty + style.font:get_height() + 16 * SCALE

  local row_h = style.font:get_height() + 14 * SCALE
  local label_w = 90 * SCALE
  self.field_ys = {}
  for _, f in ipairs(fields) do
    self.field_ys[f.key] = ty
    local focused = self.state.focus == f.key
    local label_color = focused and style.accent or style.dim
    renderer.draw_text(style.font, f.label, x + pad, ty + 4 * SCALE, label_color)
    local fx = x + pad + label_w
    local fw = w - pad * 2 - label_w
    local fh = row_h - 6 * SCALE
    renderer.draw_rect(fx, ty, fw, fh, style.background3)
    if focused then
      renderer.draw_rect(fx, ty, 2 * SCALE, fh, style.accent)
    end
    local value = ""
    if f.key == "provider" then
      local p = llm.providers[self.state.provider_idx]
      value = p and p.name or ""
    else
      value = self.state[f.key] or ""
      if f.key == "api_key" and value ~= "" then
        value = value:sub(1, 4) .. string.rep("*", math.min(12, #value - 4))
      end
    end
    renderer.draw_text(style.font, value, fx + 8 * SCALE, ty + 4 * SCALE, style.text)
    ty = ty + row_h + 8 * SCALE
  end

  -- buttons
  local by = y + h - pad - style.font:get_height() - 8 * SCALE
  local btn_w = 100 * SCALE
  self.save_rect = { x = x + w - pad - btn_w, y = by, w = btn_w, h = style.font:get_height() + 10 * SCALE }
  self.cancel_rect = { x = self.save_rect.x - btn_w - 10 * SCALE, y = by, w = btn_w, h = self.save_rect.h }
  renderer.draw_rect(self.cancel_rect.x, self.cancel_rect.y, self.cancel_rect.w, self.cancel_rect.h, style.background3)
  renderer.draw_text(style.font, "取消", self.cancel_rect.x + 28 * SCALE, self.cancel_rect.y + 5 * SCALE, style.dim)
  renderer.draw_rect(self.save_rect.x, self.save_rect.y, self.save_rect.w, self.save_rect.h, style.accent)
  renderer.draw_text(style.font, "保存", self.save_rect.x + 30 * SCALE, self.save_rect.y + 5 * SCALE, {20,20,24})

  renderer.draw_text(style.font, "↑↓ 选择字段 · ←→ 切换 Provider · Tab 下一项 · Enter 保存", x + pad, y + h - pad - style.font:get_height() - 2 * SCALE, style.dim)
end

function ConfigModal:apply_preset()
  local p = llm.providers[self.state.provider_idx]
  if not p then return end
  self.state.base_url = p.base_url
  self.state.model = p.model
  if p.id ~= "custom" then
    self.state.focus = "api_key"
  end
end

function ConfigModal:save()
  local p = llm.providers[self.state.provider_idx]
  if not p then return end
  if not self.state.base_url or self.state.base_url == "" then
    core.error("请填写 Base URL")
    return
  end
  if not self.state.model or self.state.model == "" then
    core.error("请填写模型名")
    return
  end
  if p.key_required and (not self.state.api_key or self.state.api_key == "") then
    core.error("该 Provider 需要 API Key")
    return
  end
  local ok = llm.save({
    provider = p.id,
    base_url = self.state.base_url,
    model = self.state.model,
    api_key = self.state.api_key,
  })
  if ok then
    core.log("LLM 配置已保存")
    llm.close_config()
  else
    core.error("无法写入配置文件")
  end
end

function ConfigModal:on_text_input(text)
  local f = self.state.focus
  if f == "provider" then return end
  self.state[f] = (self.state[f] or "") .. text
  core.redraw = true
  return true
end

function ConfigModal:on_key_pressed(key)
  local order = { "provider", "base_url", "model", "api_key" }
  if key == "escape" then
    llm.close_config()
    return true
  elseif key == "tab" then
    local idx = 1
    for i, k in ipairs(order) do
      if k == self.state.focus then idx = i break end
    end
    self.state.focus = order[(idx % #order) + 1]
    core.redraw = true
    return true
  elseif key == "return" or key == "kpenter" then
    if self.state.focus == "provider" then
      self:apply_preset()
    else
      self:save()
    end
    return true
  elseif key == "backspace" then
    local f = self.state.focus
    if f ~= "provider" then
      self.state[f] = (self.state[f] or ""):sub(1, -2)
      core.redraw = true
      return true
    end
  elseif key == "up" or key == "down" then
    if self.state.focus == "provider" then
      local d = (key == "up") and -1 or 1
      local n = #llm.providers
      self.state.provider_idx = ((self.state.provider_idx - 1 + d) % n) + 1
      self:apply_preset()
      core.redraw = true
      return true
    end
  elseif key == "left" or key == "right" then
    if self.state.focus == "provider" then
      local d = (key == "left") and -1 or 1
      local n = #llm.providers
      self.state.provider_idx = ((self.state.provider_idx - 1 + d) % n) + 1
      self:apply_preset()
      core.redraw = true
      return true
    end
  end
  return false
end

function ConfigModal:on_mouse_pressed(button, x, y, clicks)
  if button ~= "left" then return false end
  if self.save_rect and x >= self.save_rect.x and x <= self.save_rect.x + self.save_rect.w
    and y >= self.save_rect.y and y <= self.save_rect.y + self.save_rect.h then
    self:save()
    return true
  end
  if self.cancel_rect and x >= self.cancel_rect.x and x <= self.cancel_rect.x + self.cancel_rect.w
    and y >= self.cancel_rect.y and y <= self.cancel_rect.y + self.cancel_rect.h then
    llm.close_config()
    return true
  end
  if self.field_ys then
    local bx, byy, bw, bh = self:get_name_box()
    for key, fy in pairs(self.field_ys) do
      if y >= fy and y <= fy + 28 * SCALE and x >= bx and x <= bx + bw then
        self.state.focus = key
        core.redraw = true
        return true
      end
    end
  end
  return true -- swallow clicks on overlay
end

local modal

function llm.open_config(on_done)
  if modal then return end
  modal = ConfigModal()
  llm._on_config_done = on_done
  core.redraw = true
end

-- Better modal overlay: intercept rootview draw
local RootView = require "core.rootview"
local _root_draw = RootView.draw
function RootView:draw()
  _root_draw(self)
  if modal then
    -- set modal geometry to full window
    modal.position.x, modal.position.y = 0, 0
    modal.size.x, modal.size.y = self.size.x, self.size.y
    modal:draw()
  end
end

local _root_key = RootView.on_key_pressed
function RootView:on_key_pressed(...)
  if modal then
    return modal:on_key_pressed(...)
  end
  return _root_key(self, ...)
end

local _root_text = RootView.on_text_input
function RootView:on_text_input(...)
  if modal then
    return modal:on_text_input(...)
  end
  return _root_text(self, ...)
end

local _root_mouse = RootView.on_mouse_pressed
function RootView:on_mouse_pressed(...)
  if modal then
    return modal:on_mouse_pressed(...)
  end
  return _root_mouse(self, ...)
end

function llm.close_config()
  modal = nil
  core.redraw = true
  if llm._on_config_done then
    local cb = llm._on_config_done
    llm._on_config_done = nil
    cb()
  end
end

function llm.ensure_config(callback)
  if llm.is_configured() then
    callback(true)
  else
    llm.open_config(function()
      callback(llm.is_configured())
    end)
  end
end

command.add(nil, {
  ["easyai:configure-llm"] = function()
    llm.open_config()
  end,
})

return llm
