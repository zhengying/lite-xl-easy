local style = require "core.style"
local common = require "core.common"

style.background = { common.color "#1e1e22" }
style.background2 = { common.color "#18181b" }
style.background3 = { common.color "#222228" }
style.text = { common.color "#d4d4d8" }
style.caret = { common.color "#6ea8fe" }
style.accent = { common.color "#6ea8fe" }
style.dim = { common.color "#71717a" }
style.divider = { common.color "#0f0f12" }
style.selection = { common.color "#3d4f7c" }
style.line_number = { common.color "#52525b" }
style.line_number2 = { common.color "#a1a1aa" }
style.line_highlight = { common.color "#27272a" }
style.scrollbar = { common.color "#3f3f46" }
style.scrollbar2 = { common.color "#52525b" }
style.scrollbar_track = { common.color "#18181b" }
style.nagbar = { common.color "#dc2626" }
style.nagbar_text = { common.color "#ffffff" }
style.nagbar_dim = { common.color "rgba(0, 0, 0, 0.45)" }
style.drag_overlay = { common.color "rgba(255,255,255,0.08)" }
style.drag_overlay_tab = { common.color "#6ea8fe" }
style.good = { common.color "#4ade80" }
style.warn = { common.color "#fbbf24" }
style.error = { common.color "#f87171" }
style.modified = { common.color "#3b82f6" }

style.syntax["normal"] = { common.color "#e4e4e7" }
style.syntax["symbol"] = { common.color "#e4e4e7" }
style.syntax["comment"] = { common.color "#71717a" }
style.syntax["keyword"] = { common.color "#c084fc" }
style.syntax["keyword2"] = { common.color "#f472b6" }
style.syntax["number"] = { common.color "#fbbf24" }
style.syntax["literal"] = { common.color "#fbbf24" }
style.syntax["string"] = { common.color "#86efac" }
style.syntax["operator"] = { common.color "#6ea8fe" }
style.syntax["function"] = { common.color "#6ea8fe" }

style.log["INFO"]  = { icon = "i", color = style.text }
style.log["WARN"]  = { icon = "!", color = style.warn }
style.log["ERROR"] = { icon = "!", color = style.error }

return style
