local common = require "core.common"
local style = {}

style.divider_size = common.round(1 * SCALE)
style.scrollbar_size = common.round(4 * SCALE)
style.expanded_scrollbar_size = common.round(12 * SCALE)
style.minimum_thumb_size = common.round(20 * SCALE)
style.contracted_scrollbar_margin = common.round(8 * SCALE)
style.expanded_scrollbar_margin = common.round(12 * SCALE)
style.caret_width = common.round(2 * SCALE)
style.tab_width = common.round(170 * SCALE)

style.padding = {
  x = common.round(14 * SCALE),
  y = common.round(7 * SCALE),
}

style.margin = {
  tab = {
    top = common.round(-style.divider_size * SCALE)
  }
}

local function try_font(path, size, opts)
  local ok, font = pcall(renderer.font.load, path, size, opts)
  if ok and font then return font end
  return nil
end

local function make_group(list)
  if #list < 2 then return list[1] end
  local ok, group = pcall(renderer.font.group, list)
  if ok and group then return group end
  return list[#list]
end

-- Bundled CJK font — must ship inside the .app
local NOTO = DATADIR .. "/fonts/NotoSansSC-Regular.otf"
local noto = try_font(NOTO, 15 * SCALE)
local noto_big = try_font(NOTO, 28 * SCALE)
local noto_code = try_font(NOTO, 15 * SCALE)

local fira = try_font(DATADIR .. "/fonts/FiraSans-Regular.ttf", 15 * SCALE)
local mono = try_font(DATADIR .. "/fonts/JetBrainsMono-Regular.ttf", 15 * SCALE)

-- UI: Noto Sans SC first so Chinese never shows as tofu/乱码 in chrome
style.font = noto or fira
style.big_font = noto_big or try_font(NOTO, 28 * SCALE) or style.font
if not style.big_font then
  local okc, copied = pcall(function() return style.font:copy(28 * SCALE) end)
  style.big_font = (okc and copied) or style.font
end

style.icon_font = try_font(DATADIR .. "/fonts/icons.ttf", 16 * SCALE, {antialiasing="grayscale", hinting="full"})
local ok_icon, icon_big = pcall(function() return style.icon_font:copy(23 * SCALE) end)
style.icon_big_font = (ok_icon and icon_big) or style.icon_font

-- Code/doc: JetBrains Mono + Noto Sans SC fallback (Noto also covers Latin)
if mono and noto_code then
  style.code_font = make_group({ mono, noto_code }) or noto_code
elseif noto_code then
  style.code_font = noto_code
else
  style.code_font = mono or style.font
end

style.syntax = {}
style.syntax_fonts = {}
style.log = {}

return style
