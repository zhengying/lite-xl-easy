-- mod-version:4
--- EasyAI product bootstrap. UTF-8 only. Empty start, V1 plugin policy, open APIs.
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"

-- strict.lua requires defining globals via global{}
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

-- V1: disable non-core plugins (IDE extras / session restore / palette-as-primary)
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

-- Tree hidden until a folder is opened
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
  end, { allow_many = true, title = "Open File" })
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
  end, { allow_many = false, title = "Open Folder" })
end

command.add(nil, {
  ["easyai:open-file"] = open_files_dialog,
  ["easyai:open-folder"] = open_folder_dialog,
  ["easyai:configure-llm"] = function()
    local ok, llm = pcall(require, "plugins.easyai_llm")
    if ok and llm and llm.open_config then llm.open_config() end
  end,
  ["easyai:toggle-ai-panel"] = function()
    local ok, panel = pcall(require, "plugins.easyai_panel")
    if ok and panel and panel.toggle then panel:toggle() end
  end,
})

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

-- Re-apply product theme keys
pcall(function()
  local theme = require "colors.easyai"
  if type(theme) == "table" then
    for k, v in pairs(theme) do
      style[k] = v
    end
  end
end)

-- Status bar: encoding (always UTF-8 for now) + AI toggle
if core.status_view and core.status_view.add_item then
  local mod = PLATFORM:find("Mac") and "Cmd" or "Ctrl"
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
      return { style.accent, "AI  " .. mod .. "+Shift+A" }
    end,
  })
end

local mod = PLATFORM:find("Mac") and "cmd" or "ctrl"
pcall(function()
  keymap.add({
    [mod .. "+o"] = "easyai:open-file",
    [mod .. "+shift+o"] = "easyai:open-folder",
    [mod .. "+shift+a"] = "easyai:toggle-ai-panel",
  }, true)
end)

return {
  open_file = open_files_dialog,
  open_folder = open_folder_dialog,
  product = PRODUCT_NAME,
}
