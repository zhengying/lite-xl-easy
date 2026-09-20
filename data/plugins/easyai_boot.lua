-- mod-version:4
--- EasyAI product bootstrap: untitled start, bottom-left menu, native dialogs.
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"
local ContextMenu = require "core.contextmenu"

global {
  PRODUCT_NAME = "EasyAI",
  PRODUCT_NAME_ZH = "极简AI编辑器",
}

core.product_name = PRODUCT_NAME
core.product_name_zh = PRODUCT_NAME_ZH

config.use_system_file_picker = true
config.file_size_limit = 64
config.max_tabs = 20
config.always_show_tabs = true
config.large_file_size = 10 * 1024 * 1024

for _, name in ipairs({
  "autocomplete",
  "projectsearch",
  "workspace",
  "findfile",
  "toolbarview",
  "macro",
  "drawwhitespace",
  "tabularize",
  "lineguide",
  "autorestart",
  "scale",
}) do
  config.plugins[name] = false
end

do
  local tv = config.plugins.treeview
  if type(tv) == "table" then
    tv.visible = false
    tv.size = 220 * SCALE
  else
    config.plugins.treeview = { visible = false, size = 220 * SCALE }
  end
end
config.plugins.easyai_panel = { visible = false, size = 340 * SCALE }

function core.compose_window_title(title)
  if not title or title == "" then
    return PRODUCT_NAME
  end
  return title .. " — " .. PRODUCT_NAME
end

function core.open_project(project)
  local Project = require "core.project"
  local path = type(project) == "string" and project or (project and project.path)
  path = common.normalize_volume(path) or path
  project = type(project) == "string" and Project(path) or project
  core.set_project(project.path or path)
  local ok, history = pcall(require, "plugins.easyai_history")
  if ok and history and history.add_folder then
    history.add_folder(project.path or path)
  end
  local tv = package.loaded["plugins.treeview"]
  if tv then
    tv.visible = true
    tv.cache = {}
  end
  core.redraw = true
  return project
end

---Open a fresh untitled document as the active tab.
function core.open_untitled()
  local doc = core.open_doc()
  core.root_view:open_doc(doc)
  core.set_active_view(core.active_view)
  return doc
end

-- If nothing is open (startup or all tabs closed), show untitled, not empty-state UI.
local function ensure_untitled_if_empty()
  core.add_thread(function()
    coroutine.yield(0.05)
    local primary = core.root_view:get_primary_node()
    if not primary then return end
    local has_doc = false
    for _, v in ipairs(primary.views) do
      if v.doc then has_doc = true break end
    end
    if not has_doc then
      core.open_untitled()
    end
  end)
end
ensure_untitled_if_empty()

-- Re-open untitled when the last document tab is closed
local Node = require "core.node"
local old_close_view = Node.close_view
function Node:close_view(root, view)
  old_close_view(self, root, view)
  -- if this leaf now only has EmptyView, open untitled
  core.add_thread(function()
    coroutine.yield(0)
    local primary = core.root_view:get_primary_node()
    if not primary then return end
    local only_empty = true
    local has_doc = false
    for _, v in ipairs(primary.views) do
      if tostring(v) == "EmptyView" then
        -- empty
      elseif v.doc then
        has_doc = true
        only_empty = false
      else
        only_empty = false
      end
    end
    if not has_doc and (only_empty or #primary.views == 0) then
      core.open_untitled()
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Open helpers (native dialogs)
-- ---------------------------------------------------------------------------
local function open_files_dialog()
  core.open_file_dialog(core.window, function(status, result)
    if status ~= "accept" or not result then
      if status == "error" then
        core.error("Failed to open file: %s", tostring(result))
      end
      return
    end
    for _, filename in ipairs(result) do
      local doc = core.open_doc(filename)
      core.root_view:open_doc(doc)
    end
  end, { allow_many = true, title = "打开文件" })
end

local function open_folder_dialog()
  core.open_directory_dialog(core.window, function(status, result)
    if status ~= "accept" or not result or not result[1] then
      if status == "error" then
        core.error("Failed to open folder: %s", tostring(result))
      end
      return
    end
    core.open_project(result[1])
  end, { allow_many = false, title = "打开文件夹" })
end

-- ---------------------------------------------------------------------------
-- Native Save As for untitled / Save As
-- ---------------------------------------------------------------------------
local function save_doc_as_native(doc)
  if not doc then return end
  local default_location
  local view = core.active_view
  if view and view.doc and view.doc.abs_filename then
    default_location = view.doc.abs_filename:match("(.*)[/\\].+$")
  end
  if not default_location and core.root_project() then
    default_location = core.root_project().path
  end
  core.save_file_dialog(core.window, function(status, result)
    if status ~= "accept" then
      if status == "error" then
        core.error("Save dialog failed: %s", tostring(result))
      end
      return
    end
    local path = result
    if type(result) == "table" then path = result[1] end
    if not path or path == "" then return end
    local abs = system.absolute_path(path) or path
    if not abs:match("%.%w+$") then
      abs = abs .. ".txt"
    end
    local ok, err = pcall(function()
      doc:save(common.basename(abs), abs)
    end)
    if not ok then
      core.error("Save failed: %s", tostring(err))
      return
    end
    local okh, history = pcall(require, "plugins.easyai_history")
    if okh and history and history.add_file then
      history.add_file(abs)
    end
    core.log("Saved %s", abs)
  end, {
    title = "保存文件",
    default_location = default_location,
    -- SDL: pattern may only be "*" or [A-Za-z0-9_.-]+ — not "*.txt"
    filters = {
      { name = "All files", pattern = "*" },
    },
  })
end

-- Override doc:save / doc:save-as to use native dialog
command.add(nil, {
  ["easyai:open-file"] = open_files_dialog,
  ["easyai:open-folder"] = open_folder_dialog,
  ["easyai:new-doc"] = function()
    core.open_untitled()
  end,
  ["easyai:save-as"] = function()
    local view = core.active_view
    if view and view.doc then
      save_doc_as_native(view.doc)
    end
  end,
  ["easyai:save"] = function()
    local view = core.active_view
    if not view or not view.doc then return end
    if view.doc.filename and view.doc.abs_filename then
      command.perform("doc:save")
    else
      save_doc_as_native(view.doc)
    end
  end,
  ["easyai:configure-llm"] = function()
    local ok, llm = pcall(require, "plugins.easyai_llm")
    if ok and llm and llm.open_config then llm.open_config() end
  end,
  ["easyai:toggle-ai-panel"] = function()
    local ok, panel = pcall(require, "plugins.easyai_panel")
    if ok and panel and panel.toggle then panel:toggle() end
  end,
  ["easyai:show-menu"] = function()
    command.perform("easyai:open-app-menu")
  end,
})

-- Replace doc:save / doc:save-as predicates via command override
-- command.add replaces existing if same name in some versions; use explicit rebind
local doc_commands = package.loaded["core.commands.doc"]
-- Safer: wrap by re-registering
pcall(function()
  command.add("core.docview", {
    ["doc:save"] = function(dv)
      dv = dv or core.active_view
      if not dv or not dv.doc then return end
      if dv.doc.filename and dv.doc.abs_filename then
        local abs = dv.doc.abs_filename
        local ok, err = pcall(function() dv.doc:save() end)
        if not ok then
          core.error("Save failed: %s", tostring(err))
        else
          core.log("Saved %s", abs)
        end
      else
        save_doc_as_native(dv.doc)
      end
    end,
    ["doc:save-as"] = function(dv)
      dv = dv or core.active_view
      if not dv or not dv.doc then return end
      save_doc_as_native(dv.doc)
    end,
  })
end)

local old_open_doc = core.open_doc
function core.open_doc(filename)
  local doc = old_open_doc(filename)
  if doc and doc.abs_filename and not doc.new_file then
    local ok, history = pcall(require, "plugins.easyai_history")
    if ok and history and history.add_file then
      history.add_file(doc.abs_filename)
    end
  end
  return doc
end

local RootView = require "core.rootview"
local old_drop = RootView.on_file_dropped
function RootView:on_file_dropped(filename, x, y)
  local info = system.get_file_info(filename)
  if info and info.type == "dir" then
    local abspath = system.absolute_path(filename)
    if abspath then
      core.open_project(abspath)
      return true
    end
  elseif info and info.type == "file" then
    local abspath = system.absolute_path(filename)
    if abspath then
      core.root_view:open_doc(core.open_doc(abspath))
      return true
    end
  end
  return old_drop(self, filename, x, y)
end

pcall(function()
  local theme = require "colors.easyai"
  if type(theme) == "table" then
    for k, v in pairs(theme) do
      style[k] = v
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Bottom-left app menu on status bar
-- ---------------------------------------------------------------------------
local menu_x, menu_y = 0, 0
local history = nil
pcall(function() history = require "plugins.easyai_history" end)

local function show_context_items(items)
  local cm = core.root_view.context_menu
  if not cm then return false end
  local h = 0
  for _, it in ipairs(items) do
    if it == ContextMenu.DIVIDER then
      h = h + 14 * SCALE
    else
      h = h + style.font:get_height() + style.padding.y
    end
  end
  local x = math.max(4, menu_x)
  local y = menu_y - h - 6
  if y < 8 then y = 8 end
  return cm:show(x, y, items)
end

local function history_is_empty()
  if not history then
    pcall(function() history = require "plugins.easyai_history" end)
  end
  if not history then return true end
  local files = history.get_files() or {}
  local folders = history.get_folders() or {}
  return #files == 0 and #folders == 0
end

local function app_menu_items()
  local mod = PLATFORM:find("Mac") and "⌘" or "Ctrl"
  local empty_hist = history_is_empty()
  return {
    { text = "新建文档", command = "easyai:new-doc", info = mod .. "+N" },
    { text = "打开…", command = "easyai:open" },
    ContextMenu.DIVIDER,
    { text = "保存", command = "easyai:save", info = mod .. "+S" },
    { text = "另存为…", command = "easyai:save-as" },
    ContextMenu.DIVIDER,
    { text = "AI 面板", command = "easyai:toggle-ai-panel", info = mod .. "+⇧A" },
    { text = "配置 LLM…", command = "easyai:configure-llm" },
    ContextMenu.DIVIDER,
    {
      text = "最近打开…",
      command = "easyai:history-menu",
      disabled = empty_hist,
      info = empty_hist and "（空）" or nil,
    },
  }
end

-- Modal dialog kit — load early so NagView:show is overridden
pcall(function()
  require "plugins.easyai_dialog"
end)

-- One native dialog: pick files and/or folders
local function open_path_dialog(callback, options)
  if system.open_path_dialog then
    core.path_dialog_id = (core.path_dialog_id or 9000) + 1
    local id = core.path_dialog_id
    core.active_file_dialogs[id] = callback
    system.open_path_dialog(core.window, id, options or {})
  else
    core.open_file_dialog(core.window, callback, options)
  end
end

local function open_any_dialog()
  open_path_dialog(function(status, result)
    if status ~= "accept" or not result then
      if status == "error" then
        core.error("打开失败: %s", tostring(result))
      end
      return
    end
    for _, path in ipairs(result) do
      local abs = system.absolute_path(path) or path
      local info = system.get_file_info(abs)
      if info and info.type == "dir" then
        core.open_project(abs)
      elseif info then
        core.root_view:open_doc(core.open_doc(abs))
      else
        core.error("路径不存在: %s", abs)
      end
    end
  end, { allow_many = true, title = "打开" })
end

command.add(nil, {
  ["easyai:open"] = open_any_dialog,
  ["easyai:open-menu"] = open_any_dialog,
  ["easyai:history-menu"] = function()
    if not history then
      pcall(function() history = require "plugins.easyai_history" end)
    end
    if not history then return end
    local files = history.get_files() or {}
    local folders = history.get_folders() or {}
    if #files == 0 and #folders == 0 then
      -- Disabled in the menu; if invoked anyway, do nothing noisy.
      return
    end
    local picks = {}
    local items = {}
    for _, item in ipairs(folders) do
      if item.path and item.path ~= "" then
        picks[#picks + 1] = { kind = "folder", path = item.path }
        items[#items + 1] = {
          text = "文件夹  " .. common.home_encode(item.path),
          command = "easyai:history-pick-" .. #picks,
        }
      end
    end
    for _, item in ipairs(files) do
      if item.path and item.path ~= "" then
        picks[#picks + 1] = { kind = "file", path = item.path }
        items[#items + 1] = {
          text = "文件  " .. common.home_encode(item.path),
          command = "easyai:history-pick-" .. #picks,
        }
      end
    end
    if #items == 0 then
      return
    end
    items[#items + 1] = ContextMenu.DIVIDER
    items[#items + 1] = { text = "清空历史", command = "easyai:history-clear" }
    for i, pick in ipairs(picks) do
      local p = pick
      command.add(nil, {
        ["easyai:history-pick-" .. i] = function()
          if p.kind == "folder" then
            history.open_folder(p.path)
          else
            history.open_file(p.path)
          end
        end,
      })
    end
    core.add_thread(function()
      coroutine.yield(0)
      show_context_items(items)
    end)
  end,
  ["easyai:open-app-menu"] = function()
    local status = core.status_view
    menu_x = 6
    menu_y = (status and status.position and status.position.y) or (core.root_view.size.y - 28 * SCALE)
    if status then
      status:remove_tooltip()
      status.hovered_item = {}
    end
    show_context_items(app_menu_items())
  end,
})

-- Status bar: leftmost menu button (plain text — no missing glyphs) + encoding + AI
if core.status_view and core.status_view.add_item then
  core.status_view:add_item({
    name = "easyai:menu",
    alignment = StatusView.Item.LEFT,
    position = 1,
    command = "easyai:open-app-menu",
    get_item = function()
      return { style.accent, style.font, "菜单" }
    end,
  })
  core.status_view:add_item({
    name = "easyai:encoding",
    alignment = StatusView.Item.RIGHT,
    position = 10,
    get_item = function()
      return { style.dim, "ENC ", style.text, "UTF-8" }
    end,
  })
  core.status_view:add_item({
    name = "easyai:ai",
    alignment = StatusView.Item.RIGHT,
    position = 9,
    command = "easyai:toggle-ai-panel",
    get_item = function()
      local mod = PLATFORM:find("Mac") and "Cmd" or "Ctrl"
      local m = (PLATFORM and PLATFORM:find("Mac")) and "Cmd" or "Ctrl"
      return { style.accent, "AI " .. m .. "+Shift+A" }
    end,
  })

  -- Hide status tooltips while any context menu is open (e.g. 菜单 popup)
  local sv = core.status_view
  local old_moved = sv.on_mouse_moved
  function sv:on_mouse_moved(x, y, dx, dy)
    local cm = core.root_view and core.root_view.context_menu
    if cm and cm.visible then
      self:remove_tooltip()
      self.hovered_item = {}
      self.cursor = "arrow"
      return
    end
    return old_moved(self, x, y, dx, dy)
  end
  local old_draw = sv.draw
  function sv:draw(...)
    local cm = core.root_view and core.root_view.context_menu
    if cm and cm.visible then
      self:remove_tooltip()
    end
    return old_draw(self, ...)
  end
end

-- Status view: ensure menu button is clickable even outside docview predicate
-- (status items with command work when present; LEFT position 1)

local mod = PLATFORM:find("Mac") and "cmd" or "ctrl"
-- SDL3 may report PLATFORM="macOS"; bind both cmd (mac modkeys) and super (generic fallback)
pcall(function()
  local map = {
    [mod .. "+n"] = "easyai:new-doc",
    [mod .. "+o"] = "easyai:open",
    [mod .. "+shift+o"] = "easyai:open-folder",
    [mod .. "+s"] = "easyai:save",
    [mod .. "+shift+s"] = "easyai:save-as",
    [mod .. "+shift+a"] = "easyai:toggle-ai-panel",
  }
  keymap.add(map, true)
  keymap.add_direct(map)
  if PLATFORM and PLATFORM:find("Mac") then
    local smap = {
      ["super+s"] = "easyai:save",
      ["super+shift+s"] = "easyai:save-as",
      ["super+n"] = "easyai:new-doc",
      ["super+o"] = "easyai:open",
      ["super+shift+o"] = "easyai:open-folder",
      ["super+shift+a"] = "easyai:toggle-ai-panel",
    }
    keymap.add(smap, true)
    keymap.add_direct(smap)
  end
end)

-- Native save for unsaved docs; named files save in place
local function easyai_save()
  local view = core.active_view
  if not view or not view.doc then return end
  if view.doc.filename and view.doc.abs_filename then
    local abs = view.doc.abs_filename
    local ok, err = pcall(function() view.doc:save() end)
    if not ok then
      core.error("Save failed: %s", tostring(err))
    else
      core.log("Saved %s", abs)
    end
  else
    save_doc_as_native(view.doc)
  end
end

command.add(nil, {
  ["easyai:save"] = easyai_save,
})
command.add("core.docview", {
  ["doc:save"] = function()
    easyai_save()
  end,
  ["doc:save-as"] = function(dv)
    dv = dv or core.active_view
    if dv and dv.doc then save_doc_as_native(dv.doc) end
  end,
})
-- Also re-bind mac default save strokes onto our commands
pcall(function()
  if PLATFORM and PLATFORM:find("Mac") then
    keymap.add_direct({
      ["cmd+s"] = "easyai:save",
      ["cmd+shift+s"] = "easyai:save-as",
      ["cmd+n"] = "easyai:new-doc",
      ["cmd+o"] = "easyai:open",
    })
  else
    keymap.add_direct({
      ["ctrl+s"] = "easyai:save",
      ["ctrl+shift+s"] = "easyai:save-as",
      ["ctrl+n"] = "easyai:new-doc",
      ["ctrl+o"] = "easyai:open",
    })
  end
end)

-- Open untitled after init if no files came from CLI
core.add_thread(function()
  coroutine.yield(0.15)
  local primary = core.root_view:get_primary_node()
  if not primary then return end
  local has_doc = false
  for _, v in ipairs(primary.views) do
    if v.doc then has_doc = true break end
  end
  if not has_doc then
    core.open_untitled()
  end
  core.redraw = true
end)

return {
  open_file = open_files_dialog,
  open_folder = open_folder_dialog,
  open_untitled = core.open_untitled,
  save_as = save_doc_as_native,
  product = PRODUCT_NAME,
}
