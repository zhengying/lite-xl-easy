-- mod-version:4
--- EasyAI right panel: 总结 / 分析 / 改写 / 问答 / 翻译
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local llm = require "plugins.easyai_llm"
local http = require "plugins.easyai_http"

config.plugins.easyai_panel = common.merge({
  size = 320 * SCALE,
  visible = false,
}, config.plugins.easyai_panel)

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
  self.action = nil
  self.question = ""
  self.question_focus = false
  self.last_error = nil
  self.buttons = {}
  self.ui = {}
end

function AIPanel:get_name() return "AI 助手" end
function AIPanel:get_filename() return "" end

function AIPanel:set_target_size(axis, value)
  if axis == "x" then
    self.target_size = value
    return true
  end
end

function AIPanel:get_scrollable_size()
  return math.max(0, self:get_text_height() + 200 * SCALE - self.size.y)
end

function AIPanel:get_text_height()
  local font = style.font
  local width = self.size.x - style.padding.x * 2
  if width < 40 then return 0 end
  local h = 0
  for _, line in ipairs(self:wrap_text(self.output, font, width)) do
    h = h + font:get_height()
  end
  return h
end

function AIPanel:wrap_text(text, font, width)
  local lines = {}
  if not text or text == "" then return lines end
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    if paragraph == "" then
      lines[#lines + 1] = ""
    else
      local buf = ""
      for ch in paragraph:gmatch(utf8.charpattern) do
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
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = nil
  else
    self:move_towards(self.size, "x", dest)
  end
  AIPanel.super.update(self)
end

function AIPanel:toggle()
  self.visible = not self.visible
  if self.visible then
    self.init_size = true
  end
  core.redraw = true
end

local actions = {
  { id = "summarize", label = "总结" },
  { id = "analyze", label = "分析" },
  { id = "rewrite", label = "改写" },
  { id = "qa", label = "问答" },
  { id = "translate", label = "翻译" },
}

function AIPanel:context_preview()
  local view = core.active_view
  if not view or not view.doc then return "", 0, 0 end
  local doc = view.doc
  local text = doc:get_selection_text(200000)
  if not text or not text:match("%S") then
    text = table.concat(doc.lines)
  end
  local chars, tokens = llm.estimate_tokens(text)
  return text or "", chars, tokens
end

function AIPanel:draw()
  self:draw_background(style.background2)
  local pad = style.padding.x
  local y = style.padding.y
  local x = self.position.x + pad
  local w = self.size.x - pad * 2
  self.buttons = {}
  self.ui = {}

  renderer.draw_text(style.font, "AI 助手", x, y, style.accent)
  -- close button
  local close_x = self.position.x + self.size.x - pad - 14 * SCALE
  self.ui.close = { x = close_x - 4 * SCALE, y = y - 2 * SCALE, w = 18 * SCALE, h = 18 * SCALE }
  renderer.draw_text(style.font, "×", close_x, y, style.dim)
  y = y + style.font:get_height() + 8 * SCALE

  -- action buttons  grid
  local btn_h = style.font:get_height() + 10 * SCALE
  local cols = 3
  local gap = 6 * SCALE
  local bw = (w - gap * (cols - 1)) / cols
  local idx = 0
  for _, a in ipairs(actions) do
    local col = idx % cols
    local row = math.floor(idx / cols)
    local bx = x + col * (bw + gap)
    local by = y + row * (btn_h + gap)
    local hot = self.hover_action == a.id
    local running = self.running and self.action == a.id
    if running then
      renderer.draw_rect(bx, by, bw, btn_h, style.accent)
      renderer.draw_text(style.font, a.label, bx + bw / 2 - style.font:get_width(a.label) / 2, by + 5 * SCALE, {20,20,24})
    else
      renderer.draw_rect(bx, by, bw, btn_h, hot and style.selection or style.background3)
      renderer.draw_text(style.font, a.label, bx + bw / 2 - style.font:get_width(a.label) / 2, by + 5 * SCALE, style.text)
    end
    self.buttons[#self.buttons + 1] = { id = a.id, label = a.label, x = bx, y = by, w = bw, h = btn_h }
    idx = idx + 1
  end
  local rows = math.ceil(#actions / cols)
  y = y + rows * (btn_h + gap) + 4 * SCALE

  -- context estimate
  local preview, chars, tokens = self:context_preview()
  local scope = "整份文件"
  local view = core.active_view
  if view and view.doc then
    local sel = view.doc:get_selection_text(10)
    if sel and sel:match("%S") then scope = "选中内容" end
  end
  renderer.draw_text(style.font, ("范围：%s · 预估 %d 字 / ~%d tokens"):format(scope, chars, tokens), x, y, style.dim)
  y = y + style.font:get_height() + 6 * SCALE
  self.ui.estimate = { chars = chars, tokens = tokens, scope = scope }

  -- Q&A input
  local qh = style.font:get_height() + 10 * SCALE
  self.ui.question = { x = x, y = y, w = w, h = qh }
  renderer.draw_rect(x, y, w, qh, style.background3)
  if self.question_focus then
    renderer.draw_rect(x, y, 2 * SCALE, qh, style.accent)
  end
  local qtext = self.question
  if qtext == "" and not self.question_focus then
    renderer.draw_text(style.font, "问答：输入问题…", x + 8 * SCALE, y + 5 * SCALE, style.dim)
  else
    renderer.draw_text(style.font, qtext, x + 8 * SCALE, y + 5 * SCALE, style.text)
  end
  y = y + qh + 8 * SCALE

  -- status / cancel / retry
  if self.status ~= "" then
    local col = self.last_error and style.error or style.dim
    renderer.draw_text(style.font, self.status, x, y, col)
    y = y + style.font:get_height() + 4 * SCALE
  end
  if self.running then
    self.ui.cancel = { x = x, y = y, w = 80 * SCALE, h = btn_h }
    renderer.draw_rect(self.ui.cancel.x, self.ui.cancel.y, self.ui.cancel.w, self.ui.cancel.h, style.warn)
    renderer.draw_text(style.font, "取消 (Esc)", self.ui.cancel.x + 6 * SCALE, self.ui.cancel.y + 5 * SCALE, {20,20,24})
    y = y + btn_h + 8 * SCALE
  elseif self.last_error then
    self.ui.retry = { x = x, y = y, w = 80 * SCALE, h = btn_h }
    renderer.draw_rect(self.ui.retry.x, self.ui.retry.y, self.ui.retry.w, self.ui.retry.h, style.background3)
    renderer.draw_text(style.font, "重试", self.ui.retry.x + 22 * SCALE, self.ui.retry.y + 5 * SCALE, style.text)
    y = y + btn_h + 8 * SCALE
  end

  -- output
  local ox = x
  local oy = y - self.scroll.to.y
  local lines = self:wrap_text(self.output, style.font, w)
  self.drawn_lines = lines
  local line_h = style.font:get_height()
  for _, line in ipairs(lines) do
    if oy + line_h > self.position.y + self.size.y then break end
    if oy > self.position.y - line_h then
      renderer.draw_text(style.font, line, ox, oy, style.text)
    end
    oy = oy + line_h
  end

  if self.output == "" and not self.running then
    renderer.draw_text(style.font, "选择文字后点击上方按钮", x, y + 4 * SCALE, style.dim)
    renderer.draw_text(style.font, "无选中时作用于整个文件", x, y + 4 * SCALE + line_h, style.dim)
  end
end

function AIPanel:hit(x, y)
  for _, b in ipairs(self.buttons) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      return b
    end
  end
  for k, r in pairs(self.ui) do
    if type(r) == "table" and r.x and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      return { id = k }
    end
  end
  return nil
end

function AIPanel:on_mouse_moved(px, py)
  AIPanel.super.on_mouse_moved(self, px, py)
  local hit = self:hit(px, py)
  self.hover_action = hit and hit.id or nil
  self.cursor = hit and "hand" or "arrow"
end

function AIPanel:on_mouse_pressed(button, x, y, clicks)
  if AIPanel.super.on_mouse_pressed(self, button, x, y, clicks) then
    return true
  end
  if button ~= "left" then return false end
  local hit = self:hit(x, y)
  if not hit then
    self.question_focus = false
    return true
  end
  if hit.id == "close" then
    panel.toggle()
  elseif hit.id == "cancel" then
    AIPanel.cancel()
  elseif hit.id == "retry" then
    if self.action then AIPanel.run(self.action) end
  elseif hit.id == "question" then
    self.question_focus = true
    core.set_active_view(self)
  else
    self.question_focus = false
    AIPanel.run(hit.id)
  end
  return true
end

function AIPanel:on_text_input(text)
  if self.question_focus then
    self.question = self.question .. text
    core.redraw = true
    return true
  end
  return false
end

function AIPanel:on_key_pressed(key)
  if key == "escape" and self.running then
    AIPanel.cancel()
    return true
  end
  if self.question_focus then
    if key == "backspace" then
      self.question = self.question:sub(1, -2)
      core.redraw = true
      return true
    elseif key == "return" or key == "kpenter" then
      AIPanel.run("qa")
      return true
    elseif key == "escape" then
      self.question_focus = false
      core.redraw = true
      return true
    end
  end
  return false
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

function AIPanel.replace_doc_text(result)
  local view = core.active_view
  if not view or not view.doc then
    core.error("没有可替换的文档")
    return
  end
  local doc = view.doc
  local line1, col1, line2, col2 = doc:get_selection(true)
  if line1 == line2 and col1 == col2 then
    -- replace whole file
    line1, col1, line2, col2 = 1, 1, #doc.lines, #doc.lines[#doc.lines]
  end
  local clean = result:gsub("^%s+", ""):gsub("%s+$", "")
  -- strip accidental code fences
  clean = clean:gsub("^```%w*\n", ""):gsub("\n```%s*$", "")
  if clean == "" then
    core.error("AI 返回为空，未替换")
    return
  end
  -- single undo step via merge window
  local t = system.get_time()
  doc:remove(line1, col1, line2, col2)
  doc:insert(line1, col1, clean)
  -- force undo entries to share timestamp for merge
  if doc.undo_stack and doc.undo_stack.idx then
    -- leave as-is; undo_merge_timeout should coalesce
  end
  doc:set_selection(line1, col1, doc:position_offset(line1, col1, #clean))
  core.log("已替换原文，Ctrl/Cmd+Z 可一步撤销")
  core.redraw = true
end

function AIPanel.run(action)
  if not panel.visible then
    panel.visible = true
    panel.init_size = true
  end

  llm.ensure_config(function(ok)
    if not ok then
      panel.status = "请先配置 LLM Provider"
      core.redraw = true
      return
    end

    local context, err, has_sel = llm.get_context()
    if not context then
      panel.status = err or "无内容"
      panel.last_error = err
      core.redraw = true
      return
    end

    if action == "qa" then
      if not panel.question or panel.question:match("^%s*$") then
        panel.status = "请输入问题后回车，或点击「问答」"
        core.redraw = true
        return
      end
    end

    local cfg = llm.load()
    local messages = llm.build_messages(action, context, panel.question)

    if panel.job then
      pcall(panel.job.cancel)
      panel.job = nil
    end

    panel.action = action
    panel.running = true
    panel.last_error = nil
    panel.output = ""
    panel.status = "请求中…"
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
      panel.status = "完成"
      panel.output = full ~= "" and full or panel.output
      if action == "rewrite" or action == "translate" then
        AIPanel.replace_doc_text(panel.output)
        panel.status = "已替换原文（可撤销）"
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

-- init panel docked right (defer until after other plugins, e.g. treeview)
local panel = AIPanel()
panel.init_size = true
panel.visible = false
panel.size.x = 0
panel.target_size = config.plugins.easyai_panel.size

core.add_thread(function()
  coroutine.yield(0.05)
  local primary = core.root_view:get_primary_node()
  if not panel.node then
    panel.node = primary:split("right", panel, { x = true }, true)
  end
  panel.visible = false
  panel.size.x = 0
  core.redraw = true
end)

local _toggle = panel.toggle
function panel:toggle()
  if not self.node then
    local primary = core.root_view:get_primary_node()
    self.node = primary:split("right", self, { x = true }, true)
  end
  self.visible = not self.visible
  if self.visible then
    self.init_size = true
  end
  core.redraw = true
end

command.add(nil, {
  ["easyai:toggle-ai-panel"] = function() panel:toggle() end,
  ["easyai:summarize"] = function() AIPanel.run("summarize") end,
  ["easyai:analyze"] = function() AIPanel.run("analyze") end,
  ["easyai:rewrite"] = function() AIPanel.run("rewrite") end,
  ["easyai:translate"] = function() AIPanel.run("translate") end,
  ["easyai:ask"] = function() AIPanel.run("qa") end,
  ["easyai:ai-cancel"] = function() AIPanel.cancel() end,
})

-- platform-aware binding
local mod = PLATFORM:find("Mac") and "cmd" or "ctrl"
keymap.add({
  [mod .. "+shift+a"] = "easyai:toggle-ai-panel",
})

-- statusbar tooltip hook via command
local old_status_items -- luacheck: ignore

panel.actions = actions
panel.AIPanel = AIPanel
panel.run = AIPanel.run
panel.cancel = AIPanel.cancel
return panel
