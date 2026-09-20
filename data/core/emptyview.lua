local core = require "core"
local common = require "core.common"
local style = require "core.style"
local keymap = require "core.keymap"
local command = require "core.command"
local View = require "core.view"

local history_ok, history = pcall(require, "plugins.easyai_history")

---@class core.emptyview : core.view
---@field super core.view
local EmptyView = View:extend()

function EmptyView:__tostring() return "EmptyView" end

function EmptyView:get_name()
  return core.product_name or "EasyAI"
end

function EmptyView:get_filename()
  return ""
end

EmptyView.scrollable = true

function EmptyView:new()
  EmptyView.super.new(self)
  self.scrollable = true
  self.hot = nil
  self.item_h = 0
  self.hit_regions = {}
end

function EmptyView:get_scrollable_size()
  local h = self:content_height()
  return math.max(0, h - self.size.y + 40 * SCALE)
end

function EmptyView:content_height()
  local line = style.font:get_height()
  local big = style.big_font:copy(math.floor(36 * SCALE))
  local h = 24 * SCALE + big:get_height() + line + 24 * SCALE
  h = h + 3 * (line + 22 * SCALE) + 24 * SCALE
  h = h + line + 12 * SCALE
  if history_ok then
    h = h + #history.get_files() * (line + 10 * SCALE) + 40 * SCALE
  end
  return h
end

function EmptyView:draw()
  self:draw_background(style.background)
  self.hit_regions = {}

  local cx = self.position.x + self.size.x / 2
  local y = self.position.y + 28 * SCALE - self.scroll.to.y
  local panel_w = math.min(self.size.x - 48 * SCALE, 420 * SCALE)
  local x = cx - panel_w / 2
  local line = style.font:get_height()
  local big = style.big_font:copy(math.floor(36 * SCALE))
  local mid = style.big_font:copy(math.floor(18 * SCALE))

  local title = core.product_name or "EasyAI"
  local subtitle = (core.product_name_zh or "极简AI编辑器") .. " · 打开即用，右侧 AI"

  renderer.draw_text(big, title, cx - big:get_width(title) / 2, y, style.accent)
  y = y + big:get_height() + 6 * SCALE
  renderer.draw_text(style.font, subtitle, cx - style.font:get_width(subtitle) / 2, y, style.dim)
  y = y + line + 28 * SCALE

  local buttons = {
    { id = "open-file", label = "打开文件", cmd = "easyai:open-file" },
    { id = "open-folder", label = "打开文件夹", cmd = "easyai:open-folder" },
    { id = "ai-panel", label = "打开 AI 面板", cmd = "easyai:toggle-ai-panel" },
  }
  local btn_h = line + 20 * SCALE
  for _, b in ipairs(buttons) do
    local hot = self.hot == b.id
    local bg = hot and style.accent or style.background2
    local fg = hot and { 20, 20, 24 } or style.text
    renderer.draw_rect(x, y, panel_w, btn_h, bg)
    renderer.draw_rect(x, y, panel_w, btn_h, { style.accent[1], style.accent[2], style.accent[3], hot and 0 or 30 })
    if not hot then
      -- border accent
      renderer.draw_rect(x, y, panel_w, 1, { style.accent[1], style.accent[2], style.accent[3], 60 })
      renderer.draw_rect(x, y + btn_h - 1, panel_w, 1, { style.accent[1], style.accent[2], style.accent[3], 60 })
      renderer.draw_rect(x, y, 1, btn_h, { style.accent[1], style.accent[2], style.accent[3], 60 })
      renderer.draw_rect(x + panel_w - 1, y, 1, btn_h, { style.accent[1], style.accent[2], style.accent[3], 60 })
    end
    local tw = style.font:get_width(b.label)
    renderer.draw_text(style.font, b.label, cx - tw / 2, y + 10 * SCALE, fg)
    self.hit_regions[#self.hit_regions + 1] = {
      id = b.id, cmd = b.cmd, x = x, y = y, w = panel_w, h = btn_h
    }
    y = y + btn_h + 12 * SCALE
  end

  y = y + 12 * SCALE
  local hint = "也可以把文件 / 文件夹拖进窗口"
  renderer.draw_text(style.font, hint, cx - style.font:get_width(hint) / 2, y, style.dim)
  y = y + line + 20 * SCALE

  -- recent list
  if history_ok then
    local files = history.get_files()
    local folders = history.get_folders()
    local recent_title = "最近打开"
    renderer.draw_text(mid, recent_title, x, y, style.text)
    y = y + mid:get_height() + 10 * SCALE

    if #files == 0 and #folders == 0 then
      renderer.draw_text(style.font, "暂无历史记录", x, y, style.dim)
      y = y + line + 8 * SCALE
    end

    local function draw_item(item, kind)
      local row_h = line + 8 * SCALE
      local hot = self.hot == ("item:" .. kind .. ":" .. item.path)
      local del_hot = self.hot == ("del:" .. kind .. ":" .. item.path)
      if hot then
        renderer.draw_rect(x, y - 4 * SCALE, panel_w, row_h, style.background2)
      end
      local name = common.home_encode(item.path)
      local max_w = panel_w - 70 * SCALE
      if style.font:get_width(name) > max_w then
        while name ~= "" and style.font:get_width(name .. "…") > max_w do
          name = name:sub(1, -2)
        end
        name = name .. "…"
      end
      local prefix = kind == "folder" and "夹 " or "文 "
      renderer.draw_text(style.font, prefix .. name, x + 4 * SCALE, y, hot and style.accent or style.text)
      -- delete
      local dx = x + panel_w - 28 * SCALE
      renderer.draw_text(style.font, "×", dx, y, del_hot and style.error or style.dim)
      self.hit_regions[#self.hit_regions + 1] = {
        id = "item:" .. kind .. ":" .. item.path,
        kind = kind, path = item.path,
        x = x, y = y - 4 * SCALE, w = panel_w - 36 * SCALE, h = row_h,
      }
      self.hit_regions[#self.hit_regions + 1] = {
        id = "del:" .. kind .. ":" .. item.path,
        kind = kind, path = item.path, delete = true,
        x = dx - 4 * SCALE, y = y - 4 * SCALE, w = 24 * SCALE, h = row_h,
      }
      y = y + row_h
    end

    for _, item in ipairs(folders) do
      draw_item(item, "folder")
    end
    for _, item in ipairs(files) do
      draw_item(item, "file")
    end

    if #files + #folders > 0 then
      y = y + 12 * SCALE
      local clear_label = "清空历史"
      local cw = style.font:get_width(clear_label) + 16 * SCALE
      local clear_hot = self.hot == "clear-history"
      renderer.draw_rect(x, y, cw, line + 8 * SCALE, clear_hot and style.selection or style.background2)
      renderer.draw_text(style.font, clear_label, x + 8 * SCALE, y + 4 * SCALE, style.dim)
      self.hit_regions[#self.hit_regions + 1] = {
        id = "clear-history", x = x, y = y, w = cw, h = line + 8 * SCALE
      }
    end
  end
end

function EmptyView:hit_test(x, y)
  for i = #self.hit_regions, 1, -1 do
    local r = self.hit_regions[i]
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      return r
    end
  end
  return nil
end

function EmptyView:on_mouse_moved(x, y)
  EmptyView.super.on_mouse_moved(self, x, y)
  local r = self:hit_test(x, y)
  self.hot = r and r.id or nil
  self.cursor = r and "hand" or "arrow"
end

function EmptyView:on_mouse_pressed(button, x, y, clicks)
  if EmptyView.super.on_mouse_pressed(self, button, x, y, clicks) then
    return true
  end
  if button ~= "left" then return false end
  local r = self:hit_test(x, y)
  if not r then return false end
  if r.delete and history_ok then
    if r.kind == "file" then
      history.remove_file(r.path)
    else
      history.remove_folder(r.path)
    end
    core.redraw = true
    return true
  end
  if r.id == "clear-history" then
    if history_ok then history.clear() end
    core.log("历史记录已清空")
    core.redraw = true
    return true
  end
  if r.kind == "file" then
    if history_ok then history.open_file(r.path) else
      core.root_view:open_doc(core.open_doc(r.path))
    end
    return true
  end
  if r.kind == "folder" then
    if history_ok then history.open_folder(r.path) else
      core.open_project(r.path)
    end
    return true
  end
  if r.cmd then
    command.perform(r.cmd)
    return true
  end
  return false
end

return EmptyView
