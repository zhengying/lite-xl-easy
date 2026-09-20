# EasyAI (极简 AI 编辑器) — Internal Design Spec

Product fork of Lite XL, driven by `极简AI编辑器-需求文档.md` (V1).

## Style anchor

Apple Notes + a quiet dark code editor: notepad speed, IDE leftovers removed.
Feel: calm dark chrome, one accent, big empty-state actions, no command-palette theater.

## Palette

| Role | Hex |
|------|-----|
| Background (doc) | `#1e1e22` |
| Background2 (side panels) | `#18181b` |
| Background3 (status/command) | `#222228` |
| Text | `#d4d4d8` |
| Dim | `#71717a` |
| Accent (AI / primary) | `#6ea8fe` |
| Accent soft (selection) | `#3d4f7c` |
| Good | `#4ade80` |
| Warn | `#fbbf24` |
| Error | `#f87171` |
| Divider | `#0f0f12` |

## Typography

- Latin UI: bundled FiraSans
- Code: JetBrainsMono + system CJK fallback
- CJK fallback (system, not bundled — keeps package ≤20MB):
  - macOS: PingFang SC / Hiragino Sans GB / STHeiti
  - Windows: Microsoft YaHei / SimSun
- Empty-state title 28–36px, body 14–15px

## Layout system

- Empty state: centered column, three primary actions, recent list below
- Editing: tabs top, optional left tree, right AI panel (collapsed by default)
- Status bar: line/col · encoding · AI toggle
- Spacing: 8px rhythm, panel padding 12–14px
- Density: notepad-like; no command palette as primary path

## Signature moments

1. **Empty state** — three large native-dialog entry points + recent history (delete/clear)
2. **AI panel** — five Chinese actions; rewrite/translate replace in place; Ctrl/Cmd+Z undoes whole replacement
3. **First AI click** — one-time LLM Provider form; never asked again

## Module map (under `data/`)

| Module | Role |
|--------|------|
| `plugins/easyai_boot.lua` | Product defaults, disable non-V1 plugins, branding, empty start, open APIs |
| `plugins/easyai_history.lua` | Recent files/folders (20), persist, open/delete/clear |
| `plugins/easyai_encoding.lua` | UTF-8 only (V1); large-file highlight off |
| `plugins/easyai_http.lua` | curl process client, SSE stream, cancel |
| `plugins/easyai_llm.lua` | Provider presets, config persistence, chat completions |
| `plugins/easyai_panel.lua` | Right AI view + actions + streaming UI + replace |
| `core/emptyview.lua` | Product empty state |
| `core/style.lua` | CJK font groups |
| `colors/easyai.lua` | Product theme |

## V1 plugin policy

**Keep**: treeview, linewrapping, detectindent, autoreload, language_* (highlight only), quote, reflow, scale.

**Disable**: autocomplete, projectsearch, workspace (session restore), findfile-as-primary, toolbarview (noise), macro, drawwhitespace, tabularize, lineguide (optional keep off).

## Non-goals locked

No plugins UI, no LSP, no project search, no terminal, no git, no settings GUI beyond LLM provider, no telemetry, no session restore.

## Platform priority

1. macOS (Apple Silicon) first — `scripts/build_easyai_mac.sh` → `EasyAI.app`
2. Windows portable/installer notes — curl.exe + PowerShell encoding fallback
