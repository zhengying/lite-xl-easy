# EasyAI Windows build / package notes

## Prerequisites

- Visual Studio Build Tools (MSVC) or `cl.exe` toolchain
- Python 3 + `pip install meson ninja`
- Git (optional)
- Network proxy if needed:
  ```powershell
  $env:http_proxy = "http://127.0.0.1:10808"
  $env:https_proxy = "http://127.0.0.1:10808"
  ```

## Build (portable)

```powershell
cd lite-xl-easy
meson setup --buildtype=release -Dportable=true --prefix / build-win
meson compile -C build-win
$destdir = Join-Path (Get-Location) "dist\EasyAI"
New-Item -ItemType Directory -Force -Path $destdir | Out-Null
meson install --skip-subprojects -C build-win --destdir $destdir
```

Expected layout:

```
dist/EasyAI/
  lite-xl.exe          # rename to easyai.exe
  data/
    core/ ...
    plugins/easyai_*.lua
```

Rename `lite-xl.exe` → `easyai.exe`.

## LLM HTTP on Windows

The editor shells out to `curl.exe` (built into Windows 10 1803+).
If missing, install curl or keep the binary on PATH.

## Encoding (GBK)

`easyai_encoding.lua` uses PowerShell + .NET code pages:

- GBK/GB2312 → code page 936
- GB18030 → code page 54936

No extra dependency required on stock Windows.

## Zip package

```powershell
Compress-Archive -Path dist\EasyAI\* -DestinationPath dist\EasyAI-win64-portable.zip
```

Target size: keep ≤ 20MB (no bundled CJK fonts; uses Microsoft YaHei).

## First-run UX

1. Launch `easyai.exe`
2. Empty state: 打开文件 / 打开文件夹 / 最近打开
3. Click any AI action → LLM Provider form once
4. Providers: DeepSeek / Kimi / OpenAI / 通义 / Ollama / LM Studio
