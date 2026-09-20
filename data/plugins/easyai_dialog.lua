-- mod-version:4
--- EasyAI modal dialogs — center card + dim overlay, mouse-first, no command palette.
local core = require "core"
local common = require "core.common"
local style = require "core.style"
local View = require "core.view"
local RootView = require "core.rootview"
local NagView = require "core.nagview"

local dialog = {}

---Active dialog state (nil when hidden).
local current = nil

local Modal = View:extend()
Modal.context = "application"

function Modal:__tostring() return "EasyAIDialog" end
function Modal:get_name() return "dialog" end
function Modal:get_filename() return "" end

function Modal:card_rect()
  local sw, sh = core.root_view.size.x, core.root_view.size.y
  local w = math.min(sw - 48 * SCALE, 420 * SCALE)
  local pad = 20 * SCALE
  local title_h = style.font:get_height() + 8 * SCALE
  local msg = current and current.message or ""
  local msg_lines = {}
  local maxw = w - pad * 2
  for paragraph in (msg .. "\n"):gmatch("(.-)\n") do
    local buf = ""
    for ch in paragraph:gmatch(utf8.charpattern) do
      local trial = buf .. ch
      if style.font:get_width(trial) > maxw and buf ~= "" then
        msg_lines[#msg_lines + 1] = buf
        buf = ch
      else
        buf = trial
      end
    end
    msg_lines[#msg_lines + 1] = buf
  end
  if #msg_lines == 0 then msg_lines = { "" } end
  local msg_h = #msg_lines * (style.font:get_height() + 4 * SCALE)
  local btn_h = style.font:get_height() + 16 * SCALE
  local h = pad * 2 + title_h + msg_h + 16 * SCALE + btn_h
  local x = math.floor((sw - w) / 2)
  local y = math.floor((sh - h) / 2)
  return x, y, w, h, pad, msg_lines, btn_h
end

function Modal:button_rects()
  local x, y, w, h, pad, _, btn_h = self:card_rect()
  local buttons = current and current.buttons or {}
  local n = #buttons
  if n == 0 then return {} end
  local gap = 10 * SCALE
  local total_min = 0
  local widths = {}
  for i, b in ipairs(buttons) do
    local tw = style.font:get_width(b.text or "") + 28 * SCALE
    widths[i] = tw
    total_min = total_min + tw
  end
  total_min = total_min + gap * (n - 1)
  local bx = x + w - pad
  local by = y + h - pad - btn_h
  local rects = {}
  for i = n, 1, -1 do
    local bw = widths[i]
    bx = bx - bw
    rects[i] = { x = bx, y = by, w = bw, h = btn_h, index = i }
    bx = bx - gap
  end
  return rects
end

function Modal:draw()
  if not current then return end
  local sw, sh = core.root_view.size.x, core.root_view.size.y
  -- dim
  renderer.draw_rect(0, 0, sw, sh, { 0, 0, 0, 140 })
  local x, y, w, h, pad, msg_lines, btn_h = self:card_rect()
  -- card
  renderer.draw_rect(x, y, w, h, style.background2)
  -- border accent
  local a = style.accent
  renderer.draw_rect(x, y, w, 1, { a[1], a[2], a[3], 90 })
  renderer.draw_rect(x, y + h - 1, w, 1, { a[1], a[2], a[3], 40 })
  renderer.draw_rect(x, y, 1, h, { a[1], a[2], a[3], 40 })
  renderer.draw_rect(x + w - 1, y, 1, h, { a[1], a[2], a[3], 40 })

  local ty = y + pad
  renderer.draw_text(style.font, current.title or "", x + pad, ty, style.accent)
  ty = ty + style.font:get_height() + 8 * SCALE
  for _, line in ipairs(msg_lines) do
    renderer.draw_text(style.font, line, x + pad, ty, style.text)
    ty = ty + style.font:get_height() + 4 * SCALE
  end

  self.rects = self:button_rects()
  for i, r in ipairs(self.rects) do
    local b = current.buttons[i]
    local hot = self.hover == i
    if b.primary then
      renderer.draw_rect(r.x, r.y, r.w, r.h, hot and { a[1] * 0.9, a[2] * 0.9, a[3] * 0.9, 255 } or a)
      renderer.draw_text(style.font, b.text or "", r.x + 14 * SCALE, r.y + 8 * SCALE, { 20, 20, 24 })
    elseif b.danger then
      renderer.draw_rect(r.x, r.y, r.w, r.h, hot and { 120, 40, 40, 255 } or style.background3)
      renderer.draw_rect(r.x, r.y, r.w, r.h, hot and { 0, 0, 0, 0 } or { style.error[1], style.error[2], style.error[3], 50 })
      renderer.draw_text(style.font, b.text or "", r.x + 14 * SCALE, r.y + 8 * SCALE, hot and style.text or style.error)
    else
      renderer.draw_rect(r.x, r.y, r.w, r.h, hot and style.selection or style.background3)
      renderer.draw_text(style.font, b.text or "", r.x + 14 * SCALE, r.y + 8 * SCALE, style.text)
    end
  end
end

function Modal:on_mouse_moved(x, y)
  self.hover = nil
  if not current then return end
  local rects = self.rects or self:button_rects()
  for i, r in ipairs(rects) do
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      self.hover = i
      self.cursor = "hand"
      return
    end
  end
  self.cursor = "arrow"
  core.redraw = true
end

local function finish(id)
  local cb = current and current.on_select
  local d = current
  current = nil
  core.redraw = true
  if d and d.previous_view then
    pcall(function() core.set_active_view(d.previous_view) end)
  end
  if cb then
    pcall(cb, id)
  end
end

function Modal:on_mouse_pressed(button, x, y, clicks)
  if not current then return false end
  if button ~= "left" then return true end
  local rects = self.rects or self:button_rects()
  for i, r in ipairs(rects) do
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      local b = current.buttons[i]
      finish(b.id or b.text)
      return true
    end
  end
  -- click on overlay: ignore (modal)
  return true
end

function Modal:on_key_pressed(key)
  if not current then return false end
  if key == "escape" then
    finish(current.escape or current.default or "cancel")
    return true
  elseif key == "return" or key == "kpenter" then
    finish(current.default or "ok")
    return true
  elseif key == "left" or key == "right" or key == "tab" then
    if self.hover and current.buttons[self.hover] then
      local n = #current.buttons
      local d = (key == "left") and -1 or 1
      self.hover = ((self.hover - 1 + d) % n) + 1
    else
      self.hover = 1
    end
    core.redraw = true
    return true
  end
  return true -- swallow keys while modal
end

-- Input/draw are driven by easyai_panel's single RootView router (z-order: panel < this).
function dialog.is_open()
  return current ~= nil
end

function dialog.draw(root)
  if current and current.modal then
    local w = root.size.x or 0
    local h = root.size.y or 0
    renderer.set_clip_rect(0, 0, w, h)
    current.modal.position.x, current.modal.position.y = 0, 0
    current.modal.size.x, current.modal.size.y = w, h
    current.modal:draw()
  end
end

function dialog.on_mouse_moved(...)
  if current and current.modal then
    return current.modal:on_mouse_moved(...)
  end
  return false
end

function dialog.on_mouse_pressed(...)
  if current and current.modal then
    return current.modal:on_mouse_pressed(...)
  end
  return false
end

function dialog.on_key_pressed(...)
  if current and current.modal then
    return current.modal:on_key_pressed(...)
  end
  return false
end

function dialog.on_text_input(...)
  if current and current.modal and current.modal.on_text_input then
    return current.modal:on_text_input(...)
  end
  return false
end

---Show a modal dialog.
---@param opts { title:string, message:string, buttons:table[], default?:string, escape?:string, on_select:fun(id:string)}
function dialog.show(opts)
  if current then
    -- queue by replacing: finish previous as cancel
    finish(current.escape or "cancel")
  end
  local buttons = opts.buttons or { { id = "ok", text = "确定", primary = true } }
  current = {
    title = opts.title or "提示",
    message = opts.message or "",
    buttons = buttons,
    default = opts.default,
    escape = opts.escape or (buttons[#buttons] and (buttons[#buttons].id or buttons[#buttons].text)),
    on_select = opts.on_select,
    previous_view = core.active_view,
    modal = Modal(),
  }
  core.redraw = true
  return current
end

function dialog.visible()
  return current ~= nil
end

function dialog.hide()
  if current then finish(current.escape or "cancel") end
end

---Convenience: yes/no style confirm
function dialog.confirm(title, message, yes_text, no_text, on_yes, on_no)
  dialog.show({
    title = title,
    message = message,
    default = "yes",
    escape = "no",
    buttons = {
      { id = "no", text = no_text or "取消" },
      { id = "yes", text = yes_text or "确定", primary = true },
    },
    on_select = function(id)
      if id == "yes" and on_yes then on_yes() end
      if id == "no" and on_no then on_no() end
    end,
  })
end

---Map lite-xl NagView option list to EasyAI modal.
local function nag_options_to_buttons(options)
  local buttons = {}
  for i, opt in ipairs(options or {}) do
    local text = opt.text or tostring(opt)
    local id = text
    local primary = opt.default_yes and true or false
    local danger = false
    local lower = text:lower()
    if lower:find("close") and (lower:find("without") or lower:find("discard")) then
      danger = true
    end
    if lower:find("不保存") or lower:find("丢弃") then danger = true end
    if lower:find("save") or lower:find("保存") then
      if not lower:find("without") then primary = primary or (not danger) end
    end
    if lower == "yes" or lower == "是" then
      id = "yes"
      primary = true
      text = "确定"
    elseif lower == "no" or lower == "否" then
      id = "no"
      text = "取消"
    end
    buttons[#buttons + 1] = { id = id, text = text, primary = primary, danger = danger, _orig = opt }
  end
  -- ensure cancel-like last for escape
  return buttons
end

---Override NagView:show so every lite-xl confirm becomes an EasyAI modal.
function NagView:show(title, message, options, callback)
  -- Never show the stock bottom nag bar.
  self.visible = false
  self.size.y = 0
  self.show_height = 0
  self.title = nil
  self.message = nil
  self.options = nil

  local buttons = nag_options_to_buttons(options)
  local default_id, escape_id
  for _, b in ipairs(buttons) do
    if b._orig and b._orig.default_yes then default_id = b.id end
    if b._orig and b._orig.default_no then escape_id = b.id end
  end
  if not default_id and buttons[#buttons] then default_id = buttons[#buttons].id end
  if not escape_id then
    for _, b in ipairs(buttons) do
      if not b.primary then escape_id = b.id end
    end
    if not escape_id then escape_id = default_id end
  end

  -- Friendly Chinese titles for common cases
  local zh_title = title
  local zh_msg = message
  if title == "Unsaved Changes" then
    zh_title = "未保存的更改"
  elseif title == "Unsaved Changes; Confirm Close" then
    zh_title = "未保存的更改"
  elseif title == "Saving failed" then
    zh_title = "保存失败"
  elseif title == "File Changed" then
    zh_title = "文件已在磁盘上更改"
  end
  if message and message:find("unsaved changes") then
    zh_msg = message
      :gsub("has unsaved changes%. Quit anyway%?", "有未保存的更改。仍要继续吗？")
      :gsub("docs have unsaved changes%. Quit anyway%?", "个文档有未保存的更改。仍要继续吗？")
  end

  dialog.show({
    title = zh_title,
    message = zh_msg,
    buttons = buttons,
    default = default_id,
    escape = escape_id,
    on_select = function(id)
      if not callback then return end
      local picked
      for _, b in ipairs(buttons) do
        if b.id == id then picked = b._orig or { text = b.text } break end
      end
      if not picked then
        picked = { text = id }
      end
      callback(picked)
    end,
  })
end

-- Keep nagview collapsed even if something tries to show it without :show
function NagView:update()
  self.size.y = 0
  self.show_height = 0
  self.visible = false
end

return dialog
