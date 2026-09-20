-- mod-version:4
--- EasyAI AI panel — professional composer UI (reference: modern agent input card).
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local llm = require "plugins.easyai_llm"
local http = require "plugins.easyai_http"
local textui = require "plugins.easyai_textinput"

-- Forward declaration so AIPanel methods / RootView hooks can use the singleton
local panel

config.plugins.easyai_panel = common.merge({
  size = 380 * SCALE,
  visible = false,
}, config.plugins.easyai_panel)

local PANEL_W = 380 * SCALE

local MODES = {
  { id = "qa",       label = "问答", hint = "描述任务或提问，Enter 发送" },
  { id = "summarize",label = "总结", hint = "总结当前文档或选中内容" },
  { id = "analyze",  label = "分析", hint = "分析结构、论点与语气" },
  { id = "rewrite",  label = "改写", hint = "改写后将替换原文（可撤销）" },
  { id = "translate",label = "翻译", hint = "翻译后将替换原文（可撤销）" },
}

local AIPanel = View:extend()

function AIPanel:__tostring() return "AIPanel" end

function AIPanel:new()
  AIPanel.super.new(self)
  self.visible = config.plugins.easyai_panel.visible
  self.target_size = config.plugins.easyai_panel.size
  self.scrollable = true
  self.output = ""
  self.status = ""
  self.running = false
  self.job = nil
  self.action = "qa"
  self.input_focus = false
  self.last_error = nil
  self.hover = nil
  self.ui = {}
  self.bubbles = {}
  self.caret_blink = 0
  -- Reusable multi-line composer with caret
  self.box = textui.TextBox.new({
    text = "",
    placeholder = "描述任务或提问，Cmd/Ctrl+Enter 发送",
    on_change = function() core.redraw = true end,
  })
end

function AIPanel:get_name() return "AI" end
function AIPanel:get_filename() return "" end

-- Critical: core.set_active_view() does system.text_input(window, view:supports_text_input())
-- Without this, SDL text input is stopped and typing never arrives.
function AIPanel:supports_text_input()
  return true
end

function AIPanel:on_text_input(text)
  if not self.visible then return false end
  if text and text ~= "" and self.box then
    return self.box:on_text(text)
  end
  return false
end

function AIPanel:on_key_pressed(key)
  if panel and panel.handle_key then
    local r = panel:handle_key(key)
    core.redraw = true
    return r
  end
  return false
end

function AIPanel:set_target_size(axis, value)
  if axis == "x" then
    self.target_size = value
    return true
  end
end

function AIPanel:wrap_text(text, font, width)
  local lines = {}
  if not text or text == "" then return lines end
  local pat = (utf8 and utf8.charpattern) or "[\0-\x7f\xc2-\xf4][\x80-\xbf]*"
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    if paragraph == "" then
      lines[#lines + 1] = ""
    else
      local buf = ""
      for ch in paragraph:gmatch(pat) do
        local trial = buf .. ch
        if font:get_width(trial) > width and buf ~= "" then
          lines[#lines + 1] = buf
          buf = ch
        else
          buf = trial
        end
      end
      lines[#lines + 1] = buf
    end
  end
  return lines
end

function AIPanel:update()
  if not self.target_size or self.target_size < 200 * SCALE then
    self.target_size = 360 * SCALE
  end
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = nil
  else
    self:move_towards(self.size, "x", dest)
  end
  self.caret_blink = system.get_time()
  AIPanel.super.update(self)
end

function AIPanel:toggle()
  self.visible = not self.visible
  if self.visible then
    self.target_size = 360 * SCALE
    self.size.x = self.target_size
    self.init_size = true
    self.input_focus = true
  end
  core.redraw = true
end

function AIPanel:get_scrollable_size()
  local out_h = #self:wrap_text(self.output, style.font, self:content_width()) * (style.font:get_height() + 2 * SCALE)
  return math.max(0, out_h + 40 * SCALE - (self.size.y - self:composer_height() - 40 * SCALE))
end

function AIPanel:content_width()
  return math.max(40, self.size.x - 28 * SCALE)
end

function AIPanel:mode()
  for _, m in ipairs(MODES) do
    if m.id == self.action then return m end
  end
  return MODES[1]
end

function AIPanel:model_label()
  local cfg = llm.load()
  local name = cfg and cfg.model
  if name and #name > 22 then
    name = name:sub(1, 20) .. "…"
  end
  return name or "未配置模型"
end

function AIPanel:scope_label()
  local view = core.active_view
  if not view or not view.doc then
    for _, doc in ipairs(core.docs or {}) do
      local vs = core.get_views_referencing_doc(doc)
      if vs and vs[1] then view = vs[1] break end
    end
  end
  if not view or not view.doc then return "无文档" end
  local sel = view.doc:get_selection_text(8)
  if sel and sel:match("%S") then return "选中内容" end
  return "当前文档"
end

function AIPanel:context_preview()
  local view = core.active_view
  if not view or not view.doc then
    for _, doc in ipairs(core.docs or {}) do
      local vs = core.get_views_referencing_doc(doc)
      if vs and vs[1] then view = vs[1] break end
    end
  end
  if not view or not view.doc then return "", 0, 0 end
  local doc = view.doc
  local text = doc:get_selection_text(200000)
  if not text or not text:match("%S") then
    text = table.concat(doc.lines)
  end
  local chars, tokens = llm.estimate_tokens(text)
  return text or "", chars or 0, tokens or 0
end

function AIPanel:composer_height()
  -- chips + gap + card + footer + paddings
  local chip_h = 24 * SCALE
  local pad = 12 * SCALE
  local line = style.font:get_height()
  local input_h = math.max(line * 2 + 16 * SCALE, 56 * SCALE)
  local toolbar_h = 30 * SCALE
  local card_h = pad + input_h + toolbar_h + pad
  local footer_h = line + 6 * SCALE
  return chip_h + 8 * SCALE + card_h + 6 * SCALE + footer_h + 4 * SCALE
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

local function round_rect(x, y, w, h, r, color)
  -- lite-xl has no rounded rect; approximate with rect + edge softening via layers
  renderer.draw_rect(x, y, w, h, color)
  -- corners: draw slightly inset background-colored squares is wrong; keep flat
  -- but draw a thinner inner border for "card" feel
end

function AIPanel:draw()
  local ok, err = pcall(function()
    self:draw_inner()
  end)
  if not ok then
    self.ui = {}
    self:draw_background(style.background2)
    renderer.draw_text(style.font, "AI 面板", 12, 12, style.accent)
    renderer.draw_text(style.font, "绘制错误: " .. tostring(err), 12, 40, style.error)
    renderer.draw_text(style.font, "宽=" .. tostring(self.size.x) .. " 可见=" .. tostring(self.visible), 12, 60, style.dim)
  end
end

function AIPanel:draw_inner()
  self.ui = {}
  local ox = self.position.x or 0
  local oy0 = self.position.y or 0
  local w = math.max(self.size.x or PANEL_W, 280 * SCALE)
  local h = math.max(self.size.y or 400, 200)

  -- clip to panel rect so we never paint over the editor
  renderer.set_clip_rect(ox, oy0, w, h)
  self:draw_background(style.background2)

  local pad = 14 * SCALE
  local y = oy0 + pad
  local content_w = w - pad * 2
  local x = ox + pad
  local line_h = style.font:get_height()

  -- ── Header ───────────────────────────────────────────────
  renderer.draw_text(style.font, "AI 助手", x, y, style.accent)
  local close_x = ox + w - pad - 12 * SCALE
  self.ui.close = { x = close_x - 6 * SCALE, y = y - 4 * SCALE, w = 20 * SCALE, h = 20 * SCALE }
  renderer.draw_text(style.font, "×", close_x, y, style.dim)
  y = y + line_h + 10 * SCALE
  renderer.draw_rect(x, y, content_w, 1, { 32, 32, 36, 255 })
  y = y + 12 * SCALE

  -- ── Output / empty state ─────────────────────────────────
  local composer_h = self:composer_height()
  local out_bottom = oy0 + h - composer_h - 16 * SCALE
  if out_bottom < y + 40 then out_bottom = y + 80 end
  local out_w = content_w
  local oy = y - (self.scroll.to.y or 0)

  if self.output == "" and not self.running then
    local m = self:mode()
    renderer.draw_text(style.font, "开始使用", x, oy, style.text)
    oy = oy + line_h + 8 * SCALE
    local hint_lines = {
      "在下方输入框描述任务。",
      "有选中则作用于选区，否则整份文档。",
      m.hint,
    }
    for _, hl in ipairs(hint_lines) do
      if oy > out_bottom - line_h then break end
      renderer.draw_text(style.font, hl, x, oy, style.dim)
      oy = oy + line_h + 4 * SCALE
    end
  else
    local lines = self:wrap_text(self.output, style.font, out_w)
    if self.running and self.output == "" then
      renderer.draw_text(style.font, "正在生成…", x, oy, style.dim)
      oy = oy + line_h + 6 * SCALE
    end
    for _, ln in ipairs(lines) do
      if oy > out_bottom then break end
      if oy > y - 40 then
        renderer.draw_text(style.font, ln, x, oy, style.text)
      end
      oy = oy + line_h + 2 * SCALE
    end
  end

  -- ── Bottom stack: chips → card → footer (no overlaps) ──
  local chip_h = 24 * SCALE
  local padc = 12 * SCALE
  local input_h = math.max(line_h * 2 + 16 * SCALE, 56 * SCALE)
  local toolbar_h = 30 * SCALE
  local card_h = padc + input_h + toolbar_h + padc
  local footer_h = line_h + 6 * SCALE
  local stack_h = chip_h + 8 * SCALE + card_h + 6 * SCALE + footer_h + 4 * SCALE
  local stack_top = oy0 + h - stack_h - 6 * SCALE
  if stack_top < y + 20 then stack_top = y + 20 end

  -- status (only above the chip row, with a real gap)
  local status_y = stack_top - line_h - 8 * SCALE
  if status_y > y + line_h then
    local st = self.status
    if st == "" and not self.running then
      local _, chars, tokens = self:context_preview()
      st = string.format("%s · %d 字 · ~%d tokens", self:scope_label(), chars or 0, tokens or 0)
    end
    if st ~= "" then
      renderer.draw_text(style.font, st, x, status_y, self.last_error and style.error or style.dim)
    end
  end

  -- mode chips
  local chip_y = stack_top
  local chip_x = ox + 10 * SCALE
  self.ui.modes = {}
  for _, m in ipairs(MODES) do
    local tw = style.font:get_width(m.label) + 18 * SCALE
    local active = (self.action == m.id)
    local hot = self.hover == ("mode:" .. m.id)
    local id = "mode:" .. m.id
    self.ui.modes[#self.ui.modes + 1] = { id = id, x = chip_x, y = chip_y, w = tw, h = chip_h, mode = m.id }
    if active then
      renderer.draw_rect(chip_x, chip_y, tw, chip_h, { style.accent[1], style.accent[2], style.accent[3], 45 })
      renderer.draw_text(style.font, m.label, chip_x + 9 * SCALE, chip_y + 4 * SCALE, style.accent)
    elseif hot then
      renderer.draw_rect(chip_x, chip_y, tw, chip_h, style.selection)
      renderer.draw_text(style.font, m.label, chip_x + 9 * SCALE, chip_y + 4 * SCALE, style.text)
    else
      renderer.draw_text(style.font, m.label, chip_x + 9 * SCALE, chip_y + 4 * SCALE, style.dim)
    end
    chip_x = chip_x + tw + 8 * SCALE
  end

  -- composer card
  local cy = chip_y + chip_h + 8 * SCALE
  local card_x = ox + 8 * SCALE
  local card_w = w - 16 * SCALE

  renderer.draw_rect(card_x, cy, card_w, card_h, style.background3)
  if self.input_focus then
    renderer.draw_rect(card_x, cy, card_w, 1, style.accent)
    renderer.draw_rect(card_x, cy + card_h - 1, card_w, 1, { style.accent[1], style.accent[2], style.accent[3], 80 })
    renderer.draw_rect(card_x, cy, 1, card_h, { style.accent[1], style.accent[2], style.accent[3], 80 })
    renderer.draw_rect(card_x + card_w - 1, cy, 1, card_h, { style.accent[1], style.accent[2], style.accent[3], 80 })
  else
    renderer.draw_rect(card_x, cy, card_w, 1, { 60, 60, 66, 255 })
    renderer.draw_rect(card_x, cy + card_h - 1, card_w, 1, { 40, 40, 44, 255 })
  end

  local ip = 12 * SCALE
  local ix = card_x + ip
  local iy = cy + padc
  local iw = card_w - ip * 2
  local mode = self:mode()
  self.ui.input = { x = card_x, y = cy, w = card_w, h = input_h + 8 * SCALE }

  -- Real text box with caret
  if self.box then
    self.box.placeholder = mode.hint
    self.box:focus(self.input_focus and true or false)
    self.box:draw(ix, iy, iw, input_h, {
      bg = { 30, 30, 34 },
      border = { 50, 50, 56, 255 },
      border_focus = style.accent,
    })
  end

  local bar_y = cy + card_h - padc - 22 * SCALE
  local bar_h = 22 * SCALE
  renderer.draw_rect(card_x + 10 * SCALE, bar_y - 6 * SCALE, card_w - 20 * SCALE, 1, { 50, 50, 56, 255 })

  local plus_x = card_x + 14 * SCALE
  self.ui.plus = { x = plus_x - 4 * SCALE, y = bar_y - 4 * SCALE, w = 24 * SCALE, h = bar_h + 6 * SCALE }
  renderer.draw_text(style.font, "+", plus_x, bar_y + 2 * SCALE, self.hover == "plus" and style.accent or style.dim)

  local scope_x = plus_x + 26 * SCALE
  local scope = self:scope_label()
  if scope == "选中内容" then
    renderer.draw_text(style.font, "选中内容", scope_x, bar_y + 2 * SCALE, style.warn)
  else
    renderer.draw_text(style.font, scope, scope_x, bar_y + 2 * SCALE, style.dim)
  end

  local send_r = 14 * SCALE
  local send_cx = card_x + card_w - 14 * SCALE - send_r
  local send_cy = bar_y + bar_h / 2
  local send_hot = self.hover == "send"
  self.ui.send = { x = send_cx - send_r - 2, y = send_cy - send_r - 2, w = send_r * 2 + 4, h = send_r * 2 + 4 }

  local model = self:model_label()
  local model_w = style.font:get_width(model) + 6 * SCALE
  local model_x = send_cx - send_r - 12 * SCALE - model_w
  if model_x < scope_x + 60 * SCALE then
    model_x = scope_x + 60 * SCALE
  end
  self.ui.model = { x = model_x - 4 * SCALE, y = bar_y - 4 * SCALE, w = model_w + 10 * SCALE, h = bar_h + 6 * SCALE }
  renderer.draw_text(style.font, model, model_x, bar_y + 2 * SCALE, self.hover == "model" and style.text or style.dim)

  if self.running then
    renderer.draw_rect(send_cx - send_r, send_cy - send_r, send_r * 2, send_r * 2, style.warn)
    renderer.draw_rect(send_cx - 4, send_cy - 4, 8, 8, { 20, 20, 24 })
  else
    local bg = send_hot and { 140, 170, 230 } or style.accent
    renderer.draw_rect(send_cx - send_r, send_cy - send_r, send_r * 2, send_r * 2, bg)
    renderer.draw_text(style.font, "↑", send_cx - 4 * SCALE, send_cy - line_h / 2 + 1, { 20, 20, 24 })
  end

  -- footer below card
  local foot = "AI 生成内容 — 请自行核对"
  local fw = style.font:get_width(foot)
  local foot_y = cy + card_h + 6 * SCALE
  if foot_y + line_h < oy0 + h then
    renderer.draw_text(style.font, foot, ox + math.max(8, (w - fw) / 2), foot_y, style.dim)
  end
end

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

function AIPanel:hit(x, y)
  for _, m in ipairs(self.ui.modes or {}) do
    if x >= m.x and x <= m.x + m.w and y >= m.y and y <= m.y + m.h then
      return { id = m.id, mode = m.mode }
    end
  end
  for _, key in ipairs({ "close", "send", "plus", "model", "input" }) do
    local r = self.ui[key]
    if r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      return { id = key }
    end
  end
  return nil
end

function AIPanel:on_mouse_moved(px, py)
  AIPanel.super.on_mouse_moved(self, px, py)
  local h = self:hit(px, py)
  self.hover = h and h.id or nil
  self.cursor = h and (h.id == "input" and "ibeam" or "hand") or "arrow"
  core.redraw = true
end

function AIPanel:on_mouse_pressed(button, x, y, clicks)
  if AIPanel.super.on_mouse_pressed(self, button, x, y, clicks) then
    return true
  end
  if button ~= "left" then return false end
  local h = self:hit(x, y)
  if not h then
    self.input_focus = false
    if self.box then self.box:focus(false) end
    return true
  end
  if h.id == "close" then
    self:toggle()
  elseif h.id == "input" then
    self:focus_input()
    if self.box then self.box:on_mouse_pressed(button, x, y) end
  elseif h.id == "plus" then
    self:focus_input()
  elseif h.id == "model" then
    command.perform("easyai:configure-llm")
  elseif h.id == "send" then
    if self.running then
      AIPanel.cancel()
    else
      self:submit()
    end
  elseif h.id and h.id:match("^mode:") then
    self.action = h.mode
    self:focus_input()
  end
  return true
end

function AIPanel:on_text_input(text)
  if not self.visible then return false end
  if self.box then
    return self.box:on_text(text)
  end
  return false
end

function AIPanel:on_key_pressed(key)
  if key == "escape" and self.running then
    AIPanel.cancel()
    return true
  end
  if not self.input_focus then return false end
  if key == "return" or key == "kpenter" then
    local mod = PLATFORM:find("Mac") and "cmd" or "ctrl"
    -- plain Enter submits when single-line-ish; Shift+Enter newline via box
    -- Cmd/Ctrl+Enter always submits; plain Enter submits in qa for chat feel
    self:submit()
    return true
  end
  if self.box then
    return self.box:on_key(key)
  end
  return false
end

function AIPanel:submit()
  local mode = self.action
  local text = self.box and self.box:get_text() or ""
  if mode == "qa" and (not text or text:match("^%s*$")) then
    self.status = "请先输入问题或任务描述"
    self.last_error = self.status
    core.redraw = true
    return
  end
  AIPanel.run(mode)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function AIPanel.replace_doc_text(result)
  local view = core.active_view
  if not view or not view.doc then
    core.error("没有可替换的文档")
    return
  end
  local doc = view.doc
  local line1, col1, line2, col2 = doc:get_selection(true)
  if line1 == line2 and col1 == col2 then
    line1, col1, line2, col2 = 1, 1, #doc.lines, #doc.lines[#doc.lines]
  end
  local clean = result:gsub("^%s+", ""):gsub("%s+$", "")
  clean = clean:gsub("^```%w*\n", ""):gsub("\n```%s*$", "")
  if clean == "" then
    core.error("AI 返回为空，未替换")
    return
  end
  doc:remove(line1, col1, line2, col2)
  doc:insert(line1, col1, clean)
  doc:set_selection(line1, col1, doc:position_offset(line1, col1, #clean))
  core.log("已替换原文，Cmd/Ctrl+Z 可撤销")
  core.redraw = true
end

function AIPanel.cancel()
  if panel.job then
    panel.job.cancel()
    panel.job = nil
  end
  panel.running = false
  panel.status = "已取消"
  panel.last_error = "已取消"
  core.redraw = true
end

function AIPanel.run(action)
  if not panel.visible then
    panel.visible = true
    panel.init_size = true
  end
  panel.action = action or panel.action
  local mode = panel:mode()

  llm.ensure_config(function(ok)
    if not ok then
      panel.status = "请先配置模型（点右下角模型名）"
      panel.last_error = panel.status
      core.redraw = true
      return
    end

    local context, err = llm.get_context()
    if not context then
      panel.status = err or "无内容"
      panel.last_error = panel.status
      core.redraw = true
      return
    end

    local question = self.box and self.box:get_text() or ""
    if panel.action == "qa" and (not question or question:match("^%s*$")) then
      panel.status = "请输入问题"
      core.redraw = true
      return
    end
    -- non-qa modes: optional extra instruction from input
    if panel.action ~= "qa" and question and question:match("%S") then
      context = context .. "\n\n补充要求：" .. question
    end

    local cfg = llm.load()
    local messages = llm.build_messages(panel.action, context, question)

    if panel.job then
      pcall(panel.job.cancel)
      panel.job = nil
    end

    panel.running = true
    panel.last_error = nil
    panel.output = ""
    panel.status = "生成中…"
    core.redraw = true

    local on_delta = function(piece)
      panel.output = panel.output .. piece
      core.redraw = true
    end
    local on_done = function(ok2, err2, full)
      panel.running = false
      panel.job = nil
      if not ok2 then
        panel.last_error = err2 or "请求失败"
        panel.status = panel.last_error
        core.redraw = true
        return
      end
      panel.output = full ~= "" and full or panel.output
      if panel.action == "rewrite" or panel.action == "translate" then
        AIPanel.replace_doc_text(panel.output)
        panel.status = "已替换原文（Cmd+Z 撤销）"
      else
        panel.status = "完成"
      end
      core.redraw = true
    end

    panel.job = http.stream_chat({
      url = cfg.base_url,
      api_key = cfg.api_key,
      model = cfg.model,
      messages = messages,
    }, on_delta, on_done)
  end)
end

-- ---------------------------------------------------------------------------
-- Single RootView router: editor → AI panel → confirm dialog → LLM modal
-- Input priority: LLM modal > confirm dialog > AI panel
-- ---------------------------------------------------------------------------

local RootView = require "core.rootview"
local dialog = require "plugins.easyai_dialog"
local llm = require "plugins.easyai_llm"

local panel_min_w = 280 * SCALE
local panel_max_w = 720 * SCALE
local drag_edge = 12 * SCALE

-- panel is forward-declared at top (strict.lua upvalue)
panel = AIPanel()
panel.init_size = true
panel.visible = false
panel.size.x = PANEL_W
panel.size.y = 400 * SCALE
panel.target_size = PANEL_W
panel.overlay = true
panel.dragging = false
panel.resize_hover = false

local function layout_overlay()
  local root = core.root_view
  local w, h = root.size.x, root.size.y
  local sh = 28 * SCALE
  if core.status_view and core.status_view.visible and core.status_view.size and core.status_view.size.y then
    sh = math.max(sh, core.status_view.size.y)
  end
  PANEL_W = math.max(panel_min_w, math.min(panel_max_w, PANEL_W))
  panel.position.x = math.max(0, w - PANEL_W)
  panel.position.y = 0
  panel.size.x = PANEL_W
  panel.size.y = math.max(120, h - sh)
  panel.target_size = PANEL_W
end

local function enable_text_input(on)
  pcall(function()
    if system.text_input then
      system.text_input(core.window, on and true or false)
    end
  end)
end

function panel:focus_input()
  self.input_focus = true
  if self.box then self.box:focus(true) end
  pcall(function() core.set_active_view(self) end)
  enable_text_input(true)
end

function panel:toggle()
  local ok, err = pcall(function()
    self.visible = not self.visible
    if self.visible then
      layout_overlay()
      self.input_focus = true
      if self.box then self.box:focus(true) end
      enable_text_input(true)
      pcall(function() core.set_active_view(self) end)
    else
      self.input_focus = false
      self.dragging = false
    end
    core.redraw = true
  end)
  if not ok then
    core.error("AI panel toggle: %s", tostring(err))
  end
  return self.visible
end

function panel:toggle()
  self.visible = not self.visible
  if self.visible then
    layout_overlay()
    self:focus_input()
  else
    self.input_focus = false
    self.dragging = false
  end
  core.redraw = true
  return self.visible
end

function AIPanel:on_mouse_released()
  self.dragging = false
end

local function modal_open()
  return (llm.modal_visible and llm.modal_visible())
    or (dialog.is_open and dialog.is_open())
end

local _orig_draw = RootView.draw
function RootView:draw()
  _orig_draw(self)
  local ww, wh = self.size.x, self.size.y
  if panel and panel.visible then
    layout_overlay()
    local ok, err = pcall(function() panel:draw_inner() end)
    if not ok then
      renderer.draw_rect(panel.position.x, panel.position.y, panel.size.x, panel.size.y, style.background2)
      local f = style.font or style.code_font
      if f then
        renderer.draw_text(f, "AI panel: " .. tostring(err), panel.position.x + 16, panel.position.y + 24, style.error or {255,80,80})
      end
    end
  end
  -- Restore FULL-WINDOW clip before drawing modals (panel clips to its strip)
  renderer.set_clip_rect(0, 0, ww, wh)
  if dialog.is_open and dialog.is_open() then
    pcall(function() dialog.draw(self) end)
    renderer.set_clip_rect(0, 0, ww, wh)
  end
  if llm.modal_visible and llm.modal_visible() then
    pcall(function() llm.draw_modal(self) end)
    renderer.set_clip_rect(0, 0, ww, wh)
  end
end

local _orig_move = RootView.on_mouse_moved
function RootView:on_mouse_moved(x, y, ...)
  if llm.modal_visible and llm.modal_visible() then
    return llm.modal_move(x, y) or true
  end
  if dialog.is_open and dialog.is_open() then
    return dialog.on_mouse_moved(x, y) or true
  end
  if panel and panel.visible then
    layout_overlay()
    local ox = panel.position.x or 0
    if panel.dragging then
      local rw = (core.root_view.size.x or 0) - x
      PANEL_W = math.max(panel_min_w, math.min(panel_max_w, rw))
      layout_overlay()
      core.redraw = true
      return true
    end
    if x >= ox - drag_edge and x <= ox + drag_edge then
      panel.resize_hover = true
      panel.hover = "resize"
      panel.cursor = "sizeh"
      core.redraw = true
      return true
    end
    panel.resize_hover = false
    if x >= ox then
      panel:on_mouse_moved(x, y)
      return true
    end
  end
  return _orig_move(self, x, y, ...)
end

local _orig_press = RootView.on_mouse_pressed
function RootView:on_mouse_pressed(button, x, y, clicks)
  if llm.modal_visible and llm.modal_visible() then
    return llm.modal_mouse(button, x, y, clicks)
  end
  if dialog.is_open and dialog.is_open() then
    return dialog.on_mouse_pressed(button, x, y, clicks)
  end
  if panel and panel.visible then
    layout_overlay()
    local ox = panel.position.x or 0
    if x >= ox - drag_edge and x <= ox + drag_edge then
      panel.dragging = true
      panel.hover = "resize"
      return true
    end
    if x >= ox then
      panel:focus_input()
      panel:on_mouse_pressed(button, x, y, clicks)
      return true
    end
  end
  return _orig_press(self, button, x, y, clicks)
end

local _orig_release = RootView.on_mouse_released
function RootView:on_mouse_released(button, x, y)
  if panel and panel.dragging then
    panel.dragging = false
  end
  return _orig_release(self, button, x, y)
end

local _orig_key = RootView.on_key_pressed
function RootView:on_key_pressed(key, ...)
  if llm.modal_visible and llm.modal_visible() then
    return llm.modal_key(key)
  end
  if dialog.is_open and dialog.is_open() then
    return dialog.on_key_pressed(key)
  end
  if panel and panel.visible and panel.input_focus then
    if key == "return" or key == "kpenter" then
      panel:submit()
      return true
    elseif key == "escape" then
      if panel.running then
        AIPanel.cancel()
        return true
      end
      panel.input_focus = false
      if panel.box then panel.box:focus(false) end
      return true
    end
    if panel.box then
      local handled = panel.box:on_key(key)
      if handled then return true end
    end
    return false
  end
  return _orig_key(self, key, ...)
end

local _orig_text = RootView.on_text_input
function RootView:on_text_input(text)
  if llm.modal_visible and llm.modal_visible() then
    return llm.modal_text(text)
  end
  if dialog.is_open and dialog.is_open() then
    return dialog.on_text_input(text)
  end
  if panel and panel.visible then
    if not panel.input_focus then
      panel:focus_input()
    end
    return panel:on_text_input(text)
  end
  return _orig_text(self, text)
end

function AIPanel:on_text_input(text)
  if not self.visible then return false end
  self.input = (self.input or "") .. tostring(text)
  self.input_focus = true
  core.redraw = true
  return true
end

command.add(nil, {
  ["easyai:toggle-ai-panel"] = function()
    local ok, vis = pcall(function()
      return panel:toggle()
    end)
    if not ok then
      core.error("AI panel: %s", tostring(vis))
      return
    end
    core.log(vis and "AI 面板已打开" or "AI 面板已隐藏")
  end,
  ["easyai:summarize"] = function()
    panel.action = "summarize"
    if not panel.visible then panel:toggle() end
    AIPanel.run("summarize")
  end,
  ["easyai:analyze"] = function()
    panel.action = "analyze"
    if not panel.visible then panel:toggle() end
    AIPanel.run("analyze")
  end,
  ["easyai:rewrite"] = function()
    panel.action = "rewrite"
    if not panel.visible then panel:toggle() end
    AIPanel.run("rewrite")
  end,
  ["easyai:translate"] = function()
    panel.action = "translate"
    if not panel.visible then panel:toggle() end
    AIPanel.run("translate")
  end,
  ["easyai:ask"] = function()
    panel.action = "qa"
    if not panel.visible then panel:toggle() end
    panel:focus_input()
  end,
  ["easyai:ai-cancel"] = function() AIPanel.cancel() end,
})

local mod = PLATFORM:find("Mac") and "cmd" or "ctrl"
keymap.add({ [mod .. "+shift+a"] = "easyai:toggle-ai-panel" }, true)
if PLATFORM and PLATFORM:find("Mac") then
  keymap.add({
    ["cmd+shift+a"] = "easyai:toggle-ai-panel",
    ["super+shift+a"] = "easyai:toggle-ai-panel",
  }, true)
end

panel.actions = MODES
panel.AIPanel = AIPanel
panel.run = AIPanel.run
panel.cancel = AIPanel.cancel
panel.layout_overlay = layout_overlay
panel.set_width = function(w)
  PANEL_W = math.max(panel_min_w, math.min(panel_max_w, w))
  layout_overlay()
end

-- ---------------------------------------------------------------------------
-- Hard input path: core.on_event + keymap (bypass did_keymap drop + rootview)
-- ---------------------------------------------------------------------------
local function input_log(msg)
  local f = io.open("/tmp/easyai-input.log", "a")
  if f then f:write(os.date("%H:%M:%S"), " ", msg, "\n") f:close() end
end

function panel:insert_text(str)
  if not self.box then return false end
  self.input_focus = true
  self.box:focus(true)
  local before = self.box:get_text()
  local before_caret = self.box.caret
  local ok = self.box:on_text(str)
  input_log(("insert_text %q ok=%s caret %s->%s text %q->%q"):format(
    tostring(str), tostring(ok),
    tostring(before_caret), tostring(self.box.caret),
    before, self.box:get_text()))
  core.redraw = true
  return ok
end

function panel:handle_key(key)
  if not self.visible then return false end
  self.input_focus = true
  if self.box then self.box:focus(true) end
  enable_text_input(true)
  if key == "return" or key == "kpenter" then
    self:submit()
    return true
  end
  if key == "escape" then
    if self.running then AIPanel.cancel() return true end
    return true
  end
  if self.box then
    local handled = self.box:on_key(key)
    input_log("box:on_key " .. tostring(key) .. " handled=" .. tostring(handled) .. " text=" .. self.box:get_text())
    core.redraw = true
    return handled and true or true -- always consume editing keys while focused
  end
  return false
end

local _orig_on_event = core.on_event
function core.on_event(etype, ...)
  if panel and panel.visible and panel.input_focus then
    if etype == "textinput" then
      local text = ...
      input_log("on_event textinput " .. tostring(text))
      if text and text ~= "" then
        return panel:insert_text(text) and true or false
      end
      return true
    elseif etype == "keypressed" then
      local key = ...
      input_log("on_event keypressed " .. tostring(key))
      local editing = {
        backspace=true, ["delete"]=true, left=true, right=true,
        home=true, ["end"]=true, up=true, down=true,
        ["return"]=true, kpenter=true, escape=true,
      }
      if editing[key] then
        return panel:handle_key(key)
      end
      if key == "space" then
        panel:insert_text(" ")
        return true
      end
      -- printable keys: let textinput deliver the character
      if type(key) == "string" and #key == 1 then
        return false
      end
      return false
    end
  end
  return _orig_on_event(etype, ...)
end

-- keymap: when panel input focused, don't run commands on printable keys
local ok_km, keymap_mod = pcall(require, "core.keymap")
if ok_km and keymap_mod and keymap_mod.on_key_pressed then
  local _orig_kp = keymap_mod.on_key_pressed
  function keymap_mod.on_key_pressed(k, ...)
    if panel and panel.visible and panel.input_focus then
      input_log("keymap.on_key_pressed " .. tostring(k))
      if k == "space" then
        panel:insert_text(" ")
        return true
      end
      if k == "backspace" or k == "delete" or k == "left" or k == "right"
        or k == "home" or k == "end" or k == "up" or k == "down"
        or k == "return" or k == "kpenter" then
        return panel:handle_key(k)
      end
      if type(k) == "string" and #k == 1 then
        -- suppress keymap so core.step delivers textinput
        return false
      end
    end
    return _orig_kp(k, ...)
  end
end

-- Keep SDL text input alive while panel is open (set_active_view can stop it)
core.add_thread(function()
  while true do
    if panel and panel.visible then
      enable_text_input(true)
      if panel.box and not panel.box.focused and panel.input_focus then
        panel.box:focus(true)
      end
    end
    coroutine.yield(0.25)
  end
end)

return panel
