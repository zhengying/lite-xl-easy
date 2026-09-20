local core = require "core"
local common = require "core.common"
local style = require "core.style"
local command = require "core.command"
local View = require "core.view"

---Fallback view when no document is open.
---Primary UX is an untitled buffer; this only appears briefly if that fails.
local EmptyView = View:extend()

function EmptyView:__tostring() return "EmptyView" end

function EmptyView:get_name()
  return core.product_name or "EasyAI"
end

function EmptyView:get_filename()
  return ""
end

function EmptyView:draw()
  self:draw_background(style.background)
  local cx = self.position.x + self.size.x / 2
  local cy = self.position.y + self.size.y / 2
  local line = style.font:get_height()
  local title = "准备中…"
  local hint = "左下角「菜单」可打开文件 / 文件夹 / AI 面板"
  local tw = style.font:get_width(title)
  local hw = style.font:get_width(hint)
  renderer.draw_text(style.font, title, cx - tw / 2, cy - line, style.dim)
  renderer.draw_text(style.font, hint, cx - hw / 2, cy + 4 * SCALE, style.dim)
end

function EmptyView:on_mouse_pressed(button, x, y, clicks)
  if EmptyView.super.on_mouse_pressed(self, button, x, y, clicks) then
    return true
  end
  if button == "left" then
    if type(core.open_untitled) == "function" then
      core.open_untitled()
    else
      command.perform("easyai:new-doc")
    end
    return true
  end
  return false
end

return EmptyView
