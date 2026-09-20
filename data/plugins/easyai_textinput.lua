-- mod-version:4
--- EasyAI reusable text controls: TextInput + TextBox
--- MUST declare class tables before methods (strict.lua TextInput error).
local core = require "core"
local common = require "core.common"
local style = require "core.style"

local ime = nil
pcall(function() ime = require "core.ime" end)

local textui = {}
local PAT_UTF8 = "[\0-\x7f\xc2-\xf4][\x80-\xbf]*"

local function utf8_len(s)
  if not s or s == "" then return 0 end
  local n = 0
  for _ in s:gmatch(PAT_UTF8) do n = n + 1 end
  return n
end
local function chars_of(s)
  local t = {}
  for ch in (s or ""):gmatch(PAT_UTF8) do t[#t+1] = ch end
  return t
end
local function delete_prev(s, caret)
  if caret <= 0 then return s, 0 end
  local chars = chars_of(s)
  local out = {}
  for i, ch in ipairs(chars) do
    if i ~= caret then out[#out+1] = ch end
  end
  return table.concat(out), caret - 1
end
local function delete_next(s, caret)
  local n = utf8_len(s)
  if caret >= n then return s, caret end
  local chars = chars_of(s)
  local out = {}
  for i, ch in ipairs(chars) do
    if i ~= caret + 1 then out[#out+1] = ch end
  end
  return table.concat(out), caret
end
local function insert_at(s, caret, str)
  if not str or str == "" then return s, caret end
  local chars = chars_of(s)
  local out = {}
  for i = 1, caret do out[#out+1] = chars[i] end
  out[#out+1] = str
  for i = caret + 1, #chars do out[#out+1] = chars[i] end
  return table.concat(out), caret + utf8_len(str)
end
local function char_index_at_x(chars, x0, px, font)
  local acc, prev_w = "", 0
  for i, ch in ipairs(chars) do
    acc = acc .. ch
    local w = font:get_width(acc)
    if px <= x0 + w then
      if px < x0 + (prev_w + w) / 2 then return i - 1 end
      return i
    end
    prev_w = w
  end
  return #chars
end
local function report_ime_rect(x, y, w, h)
  if not ime or not ime.set_location or not core.window then return end
  pcall(function() ime.set_location(x, y, math.max(w,2), math.max(h,2)) end)
end

local TextInput, TextBox = {}, {}
TextInput.__index = TextInput
TextBox.__index = TextBox

function TextInput.new(opts)
  opts = opts or {}
  local self = setmetatable({}, TextInput)
  self.text = opts.text or ""
  self.placeholder = opts.placeholder or ""
  self.caret = utf8_len(self.text)
  self.scroll_x = 0
  self.focused = opts.focused or false
  self.password = opts.password or false
  self.on_change = opts.on_change
  self.on_submit = opts.on_submit
  self.enabled = opts.enabled ~= false
  self.rect = { x=0,y=0,w=0,h=0 }
  self.blink_period = 0.53
  return self
end
function TextInput:set_text(t)
  self.text = t or ""
  self.caret = math.min(self.caret, utf8_len(self.text))
  self:notify()
end
function TextInput:get_text() return self.text end
function TextInput:notify() if self.on_change then pcall(self.on_change, self.text) end end
function TextInput:display_text()
  if not self.password then return self.text end
  return string.rep("*", utf8_len(self.text))
end
function TextInput:focus(on)
  self.focused = on ~= false
  if self.focused then pcall(function() system.text_input(core.window, true) end) end
end
function TextInput:insert(str)
  if not self.enabled or not str or str == "" then return end
  self.text, self.caret = insert_at(self.text, self.caret, str)
  self:notify()
end
function TextInput:backspace()
  if not self.enabled or self.caret <= 0 then return end
  self.text, self.caret = delete_prev(self.text, self.caret)
  self:notify()
end
function TextInput:delete_forward()
  if not self.enabled then return end
  self.text, self.caret = delete_next(self.text, self.caret)
  self:notify()
end
function TextInput:on_key(key)
  if not self.enabled then return false end
  local n = utf8_len(self.text)
  if key == "left" then self.caret = math.max(0, self.caret-1) return true
  elseif key == "right" then self.caret = math.min(n, self.caret+1) return true
  elseif key == "home" then self.caret = 0 return true
  elseif key == "end" then self.caret = n return true
  elseif key == "backspace" then self:backspace() return true
  elseif key == "delete" then self:delete_forward() return true
  elseif key == "return" or key == "kpenter" then
    if self.on_submit then pcall(self.on_submit, self.text) end
    return true
  end
  return false
end
function TextInput:on_text(str)
  if not self.enabled or not str or str == "" then return false end
  self:insert(str) core.redraw = true return true
end
function TextInput:on_mouse_pressed(button, mx, my)
  if button ~= "left" then return false end
  local r = self.rect
  if mx < r.x or mx > r.x+r.w or my < r.y or my > r.y+r.h then return false end
  self:focus(true)
  local font = self.font or style.font
  local pad = self.pad or (8*SCALE)
  local chars = chars_of(self:display_text())
  local idx = char_index_at_x(chars, r.x + pad - self.scroll_x, mx, font)
  self.caret = math.max(0, math.min(utf8_len(self.text), idx))
  return true
end
function TextInput:draw(x,y,w,h,opts)
  opts = opts or {}
  self.font = opts.font or style.font
  self.pad = opts.pad or (8*SCALE)
  self.rect = {x=x,y=y,w=w,h=h}
  if opts.password ~= nil then self.password = opts.password end
  local font, pad = self.font, self.pad
  local border = self.focused and (opts.border_focus or style.accent) or (opts.border or {60,60,66,255})
  renderer.draw_rect(x,y,w,h, opts.bg or style.background3)
  renderer.draw_rect(x,y,w,1,border)
  renderer.draw_rect(x,y+h-1,w,1,border)
  renderer.draw_rect(x,y,1,h,border)
  renderer.draw_rect(x+w-1,y,1,h,border)
  local display = self:display_text()
  local line_h = font:get_height()
  local ty = y + math.max(0, (h-line_h)/2)
  local chars = chars_of(display)
  local prefix = ""
  for i=1, math.min(self.caret, #chars) do prefix = prefix .. chars[i] end
  local caret_w = font:get_width(prefix)
  local text_w = font:get_width(display)
  local view_w = w - pad*2
  if caret_w - self.scroll_x > view_w - 8 then self.scroll_x = caret_w - view_w + 8
  elseif caret_w < self.scroll_x then self.scroll_x = math.max(0, caret_w - 8) end
  if text_w - self.scroll_x < view_w then self.scroll_x = math.max(0, text_w - view_w) end
  if self.scroll_x < 0 then self.scroll_x = 0 end
  local tx = x + pad - self.scroll_x
  if display == "" and self.placeholder ~= "" and not self.focused then
    renderer.draw_text(font, self.placeholder, x+pad, ty, style.dim)
  else
    renderer.draw_text(font, display, tx, ty, opts.text_color or style.text)
  end
  if self.focused and self.enabled then
    local t = system.get_time()
    if (t % (self.blink_period*2)) < self.blink_period then
      local cx = tx + caret_w
      if cx >= x+pad-1 and cx <= x+w-pad+2 then
        renderer.draw_rect(cx, ty+1, math.max(1, common.round(1.5*SCALE)), line_h-2, style.caret or style.accent)
      end
    end
    report_ime_rect(tx + caret_w, ty, 2, line_h)
  end
end

function TextBox.new(opts)
  opts = opts or {}
  local self = setmetatable({}, TextBox)
  self.text = opts.text or ""
  self.placeholder = opts.placeholder or ""
  self.caret = utf8_len(self.text)
  self.scroll_y = 0
  self.focused = opts.focused or false
  self.on_change = opts.on_change
  self.rect = {x=0,y=0,w=0,h=0}
  self.enabled = opts.enabled ~= false
  self.wrap_width = 200
  return self
end
function TextBox:set_text(t)
  self.text = t or ""
  self.caret = math.min(self.caret, utf8_len(self.text))
  self:notify()
end
function TextBox:get_text() return self.text end
function TextBox:notify() if self.on_change then pcall(self.on_change, self.text) end end
function TextBox:focus(on)
  self.focused = on ~= false
  if self.focused then pcall(function() system.text_input(core.window, true) end) end
end
function TextBox:insert(str)
  if not self.enabled then return end
  self.text, self.caret = insert_at(self.text, self.caret, str)
  self:notify()
end
function TextBox:backspace()
  if not self.enabled or self.caret <= 0 then return end
  self.text, self.caret = delete_prev(self.text, self.caret)
  self:notify()
end
function TextBox:delete_forward()
  if not self.enabled then return end
  self.text, self.caret = delete_next(self.text, self.caret)
  self:notify()
end
function TextBox:on_key(key)
  if not self.enabled then return false end
  local n = utf8_len(self.text)
  if key == "left" then self.caret = math.max(0, self.caret-1) return true
  elseif key == "right" then self.caret = math.min(n, self.caret+1) return true
  elseif key == "home" then self.caret = 0 return true
  elseif key == "end" then self.caret = n return true
  elseif key == "backspace" then self:backspace() return true
  elseif key == "delete" then self:delete_forward() return true
  elseif key == "return" or key == "kpenter" then self:insert("\n") return true
  end
  return false
end
function TextBox:on_text(str)
  if not self.enabled or not str or str == "" then return false end
  self:insert(str) core.redraw = true return true
end
function TextBox:layout_lines(font, width)
  width = math.max(40, width or self.wrap_width or 200)
  local s = self.text
  local lines, map = {}, {}
  local pos, char_base = 1, 0
  while true do
    local nl = s:find("\n", pos, true)
    local seg_end = nl and (nl-1) or #s
    local seg = s:sub(pos, seg_end)
    local line_char0, line_byte0 = char_base, pos
    local acc = ""
    for _, ch in ipairs(chars_of(seg)) do
      local trial = acc .. ch
      if font:get_width(trial) > width and acc ~= "" then
        local byte_len = #acc
        lines[#lines+1] = acc
        map[#map+1] = { byte0=line_byte0, byte1=line_byte0+byte_len-1, char0=line_char0, char1=line_char0+utf8_len(acc) }
        line_char0 = line_char0 + utf8_len(acc)
        line_byte0 = line_byte0 + byte_len
        acc = ch
      else
        acc = trial
      end
    end
    lines[#lines+1] = acc
    map[#map+1] = { byte0=line_byte0, byte1=seg_end, char0=line_char0, char1=line_char0+utf8_len(acc) }
    if not nl then break end
    pos = nl + 1
    char_base = map[#map].char1 + 1
  end
  if #lines == 0 then
    lines = {""}
    map = { { byte0=0,byte1=0,char0=0,char1=0 } }
  end
  return lines, map
end
function TextBox:on_mouse_pressed(button, mx, my)
  if button ~= "left" then return false end
  local r = self.rect
  if mx < r.x or mx > r.x+r.w or my < r.y or my > r.y+r.h then return false end
  self:focus(true)
  local font = self.font or style.font
  local pad = self.pad or (10*SCALE)
  local width = self.wrap_width or (r.w - pad*2)
  local lines, map = self:layout_lines(font, width)
  local line_h = font:get_height() + 2*SCALE
  local local_y = my - (r.y + pad) + (self.scroll_y or 0)
  local li = math.floor(local_y / line_h) + 1
  if li < 1 then li = 1 end
  if li > #lines then li = #lines end
  local chars = chars_of(lines[li])
  local idx = char_index_at_x(chars, r.x + pad, mx, font)
  local info = map[li]
  self.caret = math.max(0, math.min(utf8_len(self.text), info.char0 + idx))
  return true
end
function TextBox:draw(x,y,w,h,opts)
  opts = opts or {}
  self.font = opts.font or style.font
  self.pad = opts.pad or (10*SCALE)
  self.rect = {x=x,y=y,w=w,h=h}
  self.wrap_width = w - self.pad*2
  local font, pad = self.font, self.pad
  renderer.draw_rect(x,y,w,h, opts.bg or style.background3)
  local border = self.focused and (opts.border_focus or style.accent) or (opts.border or {60,60,66,255})
  renderer.draw_rect(x,y,w,1,border)
  renderer.draw_rect(x,y+h-1,w,1,border)
  renderer.draw_rect(x,y,1,h,border)
  renderer.draw_rect(x+w-1,y,1,h,border)
  local lines, map = self:layout_lines(font, self.wrap_width)
  local line_h = font:get_height() + 2*SCALE
  local content_h = #lines * line_h
  local view_h = h - pad*2
  if content_h - (self.scroll_y or 0) < view_h then
    self.scroll_y = math.max(0, content_h - view_h)
  end
  if (self.scroll_y or 0) < 0 then self.scroll_y = 0 end
  if self.text == "" and self.placeholder ~= "" then
    renderer.draw_text(font, self.placeholder, x+pad, y+pad, style.dim)
  end
  local caret_line, caret_col = 1, 0
  for i, info in ipairs(map) do
    if self.caret >= info.char0 and self.caret <= info.char1 then
      caret_line, caret_col = i, self.caret - info.char0
      break
    end
    if self.caret > info.char1 then
      caret_line, caret_col = i, info.char1 - info.char0
    end
  end
  for i, ln in ipairs(lines) do
    local ly = y + pad + (i-1)*line_h - (self.scroll_y or 0)
    if ly + line_h >= y + pad - 2 and ly <= y + h - pad + 2 and ln ~= "" then
      renderer.draw_text(font, ln, x+pad, ly, opts.text_color or style.text)
    end
  end
  if self.focused and self.enabled then
    local prefix = ""
    local chars = chars_of(lines[caret_line] or "")
    for i=1, math.min(caret_col, #chars) do prefix = prefix .. chars[i] end
    local cx = x + pad + font:get_width(prefix)
    local cy = y + pad + (caret_line-1)*line_h - (self.scroll_y or 0)
    local t = system.get_time()
    if (t % 1.06) < 0.53 and cy + line_h > y and cy < y + h then
      renderer.draw_rect(cx, cy+2, math.max(1, common.round(1.5*SCALE)), line_h-4, style.caret or style.accent)
    end
    report_ime_rect(cx, cy, 2, line_h)
  end
end

textui.TextInput = TextInput
textui.TextInput.new = TextInput.new
textui.TextBox = TextBox
textui.TextBox.new = TextBox.new
textui.utf8_len = utf8_len
textui.chars_of = chars_of
textui.report_ime_rect = report_ime_rect
textui.insert_at = insert_at
textui.delete_prev = delete_prev
textui.delete_next = delete_next

return textui
