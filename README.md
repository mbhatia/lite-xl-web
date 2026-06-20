# lite-xl-web

A lightweight [Lite XL](https://lite-xl.com/) plugin for previewing local HTML files and browsing local web apps with the system native webview.

The MVP intentionally avoids bundling Chromium. On macOS it uses `WKWebView` through a small Lite XL native module. On other platforms the Lua UI loads, but the native bridge currently reports that the webview backend is unavailable.

## Status

- Opens local files as `file://` URLs.
- Opens `http://localhost` / `127.0.0.1` development servers.
- Can load public `http`/`https` pages when the system webview allows them.
- Provides Lite XL commands for open, location, reload, back, forward, copy URL, and close.
- Renders the native webview inside a Lite XL editor tab on macOS.

## Requirements

- Lite XL 2.1.x.
- macOS for the current native backend.
- CMake 3.19+ and Xcode command line tools for source builds.
- A Lite XL source checkout for `resources/include/lite_xl_plugin_api.h`. The default build expects `../lite-xl`; override with `-DLITE_XL_INCLUDE_DIR=/path/to/lite-xl/resources/include`.

## Build

```sh
./build.sh
# or, if Lite XL is elsewhere:
./build.sh -DLITE_XL_INCLUDE_DIR=/path/to/lite-xl/resources/include
```

This creates `libraries/web_lxl/init.lib` on macOS. Linux/Windows builds produce a stub module until a native WebKit backend is added.

## Install during development

Symlink or copy this repository so Lite XL can load `plugins/web`, then load the plugin normally.

## Commands

- `web:open-active-file` — open the active document, best for `.html` files.
- `web:open-url` — open any URL or file path.
- `web:open-localhost` — prompt for a local development server URL.
- `web:set-location` — navigate the active web tab.
- `web:reload`
- `web:back`
- `web:forward`
- `web:copy-url`
- `web:close`

Default keys:

- `ctrl+shift+b`: open active file.
- `ctrl+shift+l`: open local server prompt.

## Lua API

```lua
local web = require "plugins.web"
web.open_tab("http://localhost:3000")
web.open_tab("/absolute/path/to/index.html")
```

## Known gaps

- The current backend is macOS-only.
- The macOS backend overlays a native `WKWebView` subview on top of Lite XL's SDL/OpenGL content; very complex editor overlays may need more clipping work.
- No developer tools, request interception, or full browser chrome.
