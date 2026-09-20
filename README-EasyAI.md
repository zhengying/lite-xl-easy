# EasyAI — 极简 AI 编辑器

Lite XL fork transformed into a notepad-fast, LLM-enabled text editor (V1).

> 打开任何文本 ≤ 0.5s · 右侧 AI 面板（总结/分析/改写/问答/翻译）· 只有 LLM Provider 一个配置项

## Product surface (V1)

| Area | Behavior |
|------|----------|
| Empty state | 打开文件 / 打开文件夹 / 最近历史 |
| Open | Native OS dialogs + drag & drop |
| History | 20 files + 20 folders, delete item / clear all |
| Tabs | Multi-tab, not persisted across restarts |
| Folder | Left tree, click opens tab; collapsible |
| Edit | Edit / save / find-replace / undo |
| Encoding | UTF-8 only (V1). GBK/GB18030 deferred to later. |
| AI panel | Right dock, collapsed by default, `Ctrl/Cmd+Shift+A` |
| AI actions | 总结 · 分析 · 改写 · 问答 · 翻译 |
| Rewrite/Translate | Replace in place; one-step undo |
| LLM config | One-time provider form on first AI click |
| Offline | All editing works without network/LLM |

### Providers (OpenAI-compatible)

- OpenAI / DeepSeek / Kimi / 通义千问
- 本地 Ollama (`http://127.0.0.1:11434/v1`)
- 本地 LM Studio (`http://127.0.0.1:1234/v1`)
- Custom base URL + model + API key

## Fonts

Chinese UI/file text uses bundled `data/fonts/NotoSansSC-Regular.otf` (Noto Sans SC).
UI font is Noto Sans SC; code font is JetBrains Mono + Noto fallback for CJK.
Package size is ~11MB with the font included.

## Repository layout

```
极简AI编辑器-需求文档.md   # V1 requirements
DESIGN.md                  # internal design spec
lite-xl-easy/              # this fork (source)
  data/plugins/easyai_*.lua
  data/core/emptyview.lua  # product empty state
  data/colors/easyai.lua
  scripts/build_easyai_mac.sh
  scripts/BUILD_WINDOWS.md
```

## Build macOS (priority platform)

```bash
export http_proxy=http://127.0.0.1:10808
export https_proxy=http://127.0.0.1:10808
# need: meson, ninja, SDL2, freetype, pcre2 (Homebrew)
cd lite-xl-easy
bash scripts/build_easyai_mac.sh
open dist/EasyAI.app
```

## Build Windows

See `lite-xl-easy/scripts/BUILD_WINDOWS.md`. Portable zip + `curl.exe` + PowerShell code pages for GBK.

## CJK font

Bundled `NotoSansSC-Regular.otf` under `data/fonts/` (~8MB) so Chinese UI/document text renders correctly on macOS and Windows without system font dependencies.

- UI font: Noto Sans SC
- Code font: JetBrains Mono + Noto Sans SC fallback

Package size is ~11MB with this font (still under the 20MB target).

## User data location


- macOS/Linux: `~/.config/easyai/`
- Windows portable: `<exe>/user/` if present, else `%APPDATA%` path with `easyai`

Contains:

- `easyai_history.lua` — recent files/folders
- `easyai_llm.lua` — provider / base_url / model / api_key
- `session.lua` — window size only (docs are **not** restored)

## Explicit non-goals (V1)

No plugins UI, LSP, project search, terminal, git, markdown preview, session restore, telemetry, or settings GUI beyond LLM provider.
