-- mod-version:4
--- Recent files/folders history for EasyAI. Max 20 each, persist to USERDIR.
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local style = require "core.style"
local View = require "core.view"

local history = {}

local MAX_ITEMS = 20

local function store_path()
  return USERDIR .. PATHSEP .. "easyai_history.lua"
end

local function load_store()
  local ok, t = pcall(dofile, store_path())
  if ok and type(t) == "table" then
    return {
      files = t.files or {},
      folders = t.folders or {},
    }
  end
  return { files = {}, folders = {} }
end

local store = load_store()

function history.save()
  local fp = io.open(store_path(), "w")
  if not fp then return end
  fp:write("return {\n  files = {\n")
  for _, item in ipairs(store.files) do
    fp:write(string.format("    {path=%q, time=%s},\n", item.path, tostring(item.time or 0)))
  end
  fp:write("  },\n  folders = {\n")
  for _, item in ipairs(store.folders) do
    fp:write(string.format("    {path=%q, time=%s},\n", item.path, tostring(item.time or 0)))
  end
  fp:write("  },\n}\n")
  fp:close()
end

local function touch(list, path)
  if not path or path == "" then return end
  path = system.absolute_path(path) or path
  for i, item in ipairs(list) do
    if item.path == path then
      table.remove(list, i)
      break
    end
  end
  table.insert(list, 1, { path = path, time = os.time() })
  while #list > MAX_ITEMS do
    table.remove(list)
  end
end

function history.add_file(path)
  touch(store.files, path)
  history.save()
end

function history.add_folder(path)
  touch(store.folders, path)
  history.save()
end

function history.get_files()
  return store.files
end

function history.get_folders()
  return store.folders
end

function history.remove_file(path)
  for i, item in ipairs(store.files) do
    if item.path == path then
      table.remove(store.files, i)
      break
    end
  end
  history.save()
end

function history.remove_folder(path)
  for i, item in ipairs(store.folders) do
    if item.path == path then
      table.remove(store.folders, i)
      break
    end
  end
  history.save()
end

function history.clear()
  store.files = {}
  store.folders = {}
  history.save()
end

function history.open_file(path)
  local info = system.get_file_info(path)
  if not info then
    core.error("文件不存在: %s", path)
    history.remove_file(path)
    return
  end
  if info.type == "dir" then
    history.open_folder(path)
    return
  end
  core.root_view:open_doc(core.open_doc(path))
end

function history.open_folder(path)
  local info = system.get_file_info(path)
  if not info or info.type ~= "dir" then
    core.error("文件夹不存在: %s", path)
    history.remove_folder(path)
    return
  end
  core.open_project(path)
end

command.add(nil, {
  ["easyai:history-clear"] = function()
    history.clear()
    core.log("历史记录已清空")
  end,
  ["easyai:history-open-file"] = function()
    local files = history.get_files()
    if #files == 0 then
      core.log("暂无最近文件")
      return
    end
    core.command_view:enter("打开最近文件", {
      submit = function(text)
        if text and text ~= "" then history.open_file(text) end
      end,
      suggest = function(text)
        local res = {}
        for _, item in ipairs(files) do
          if not text or text == "" or item.path:lower():find(text:lower(), 1, true) then
            table.insert(res, item.path)
          end
        end
        return res
      end,
    })
  end,
})

history.MAX_ITEMS = MAX_ITEMS
return history
