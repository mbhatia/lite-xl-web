-- mod-version:3
local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local renderer = require "renderer"
local system = require "system"

local defaults = {
  home_url = "about:blank",
  localhost_url = "http://localhost:3000",
  title = "Web Preview",
}

defaults.config_spec = {
  name = "Web Preview",
  { label = "Home URL", path = "home_url", type = "STRING", default = defaults.home_url },
  { label = "Localhost URL", path = "localhost_url", type = "STRING", default = defaults.localhost_url },
}

config.plugins.web = common.merge(defaults, config.plugins.web)

local ok, native = pcall(require, "libraries.web_lxl")
if not ok then native = nil end

local WebView = View:extend()

local function current_ui_scale()
  return tonumber(SCALE) or 1
end

local function is_url(text)
  return type(text) == "string" and text:match("^%a[%w+.-]*://") ~= nil
end

local function encode_path(path)
  path = path:gsub("\\", "/")
  return (path:gsub("([^%w%-%._~/])", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

local function path_to_file_url(path)
  path = system.absolute_path(common.home_expand(path))
  local encoded = encode_path(path)
  if encoded:sub(1, 1) == "/" then
    return "file://" .. encoded
  end
  return "file:///" .. encoded
end

local function target_to_url(target)
  if not target or target == "" then return config.plugins.web.home_url end
  if is_url(target) or target == "about:blank" then return target end
  return path_to_file_url(target)
end

local function active_doc_filename()
  local view = core.active_view
  local doc = view and view.doc
  return doc and (doc.abs_filename or doc.filename)
end

local function title_for_url(url)
  if not url or url == "" or url == "about:blank" then return config.plugins.web.title end
  local name = url:match("([^/]+)$") or url
  name = name:gsub("%%20", " ")
  return name ~= "" and name or config.plugins.web.title
end

local function browser_error()
  if native and native.supported == false then
    return native.reason or "Native webview backend is unavailable on this platform"
  end
  if not native then return "Native webview module is not built" end
  return nil
end

function WebView:new(target, options)
  WebView.super.new(self)
  options = options or {}
  self.url = target_to_url(target or options.url)
  self.title = options.title or title_for_url(self.url)
  self.status = { url = self.url, title = self.title, loading = false }
  self.error = browser_error()
  self.browser = nil
  self.native_focused = false
  self.core_active = false

  if not self.error then
    local ok_new, browser_or_error = pcall(native.new, {
      url = self.url,
      title = self.title,
      scale = current_ui_scale(),
    })
    if ok_new then
      self.browser = browser_or_error
    else
      self.error = tostring(browser_or_error)
      core.error("web: %s", self.error)
    end
  end
end

function WebView:sync_scale(scale)
  if self.browser and self.browser.set_scale then
    local ok_scale, err = pcall(self.browser.set_scale, self.browser, scale or current_ui_scale())
    if not ok_scale then
      self.error = tostring(err)
      self.browser = nil
      core.redraw = true
    end
  end
end

function WebView:on_scale_change(new_scale)
  self:sync_scale(new_scale)
end

function WebView:get_name()
  return self.title or config.plugins.web.title
end

function WebView:focus()
  if self.browser and self.browser.focus then
    self.browser:focus()
    self.native_focused = true
  end
end

function WebView:blur()
  if self.browser and self.browser.blur then
    pcall(self.browser.blur, self.browser)
  end
  self.native_focused = false
end

function WebView:detach()
  if self.browser then
    if self.browser.detach then
      pcall(self.browser.detach, self.browser)
    else
      self:blur()
      if self.browser.set_visible then
        pcall(self.browser.set_visible, self.browser, false)
      end
    end
  end
  self.native_focused = false
end

function WebView:close()
  self:blur()
  if self.browser then
    self.browser:close()
    self.browser = nil
  end
end

function WebView:try_close(do_close)
  self:close()
  do_close()
end

function WebView:navigate(target)
  self.url = target_to_url(target)
  self.title = title_for_url(self.url)
  if self.browser then self.browser:load_url(self.url) end
  core.redraw = true
end

function WebView:update()
  WebView.super.update(self)
  if not self.browser then return end

  local node = core.root_view.root_node:get_node_for_view(self)
  local is_core_active = core.active_view == self
  if self.core_active and not is_core_active then self:detach() end
  self.core_active = is_core_active

  if self.native_focused and not is_core_active then self:detach() end

  if not node or node.active_view ~= self then
    self:detach()
  end

  local ok_status, status = pcall(self.browser.status, self.browser)
  if not ok_status then
    self.error = tostring(status)
    self.browser = nil
    core.redraw = true
    return
  end
  self.status = status or self.status
  if self.status.url then self.url = self.status.url end
  if self.status.title and self.status.title ~= "" then self.title = self.status.title end
  if self.status.closed then self.browser = nil end
end

local function draw_lines(font, x, y, lines, color)
  local line_height = font:get_height()
  for _, line in ipairs(lines) do
    renderer.draw_text(font, line, x, y, color)
    y = y + line_height + 4
  end
end

function WebView:draw()
  self:draw_background(style.background)
  if self.browser then
    local ok_rect, err = pcall(
      self.browser.set_rect,
      self.browser,
      self.position.x,
      self.position.y,
      self.size.x,
      self.size.y,
      true
    )
    if not ok_rect then
      self.error = tostring(err)
      self.browser = nil
    else
      return
    end
  end

  local font = style.font
  local x, y = self.position.x + 12, self.position.y + 12
  local lines = {
    "Web Preview",
    self.error or "Native webview is unavailable",
    "Build the native module with ./build.sh, then restart Lite XL.",
  }
  draw_lines(font, x, y, lines, self.error and style.error or style.text)
end

function WebView:on_mouse_pressed(button)
  if button == "left" and self.browser then
    self:focus()
    return true
  end
  return false
end

local function open_tab(target, options)
  local view = WebView(target, options)
  core.root_view:get_active_node_default():add_view(view)
  return view
end

local function active_web_view()
  local view = core.active_view
  if view and view:is(WebView) then return view end
end

local function prompt(label, text, submit)
  core.command_view:enter(label, {
    text = text or "",
    submit = function(input)
      if input and input ~= "" then submit(input) end
    end,
  })
end

local function open_prompt(label, default)
  prompt(label, default, function(input) open_tab(input) end)
end

command.add(nil, {
  ["web:open-active-file"] = function()
    local filename = active_doc_filename()
    if filename then return open_tab(filename) end
    open_prompt("Open HTML File or URL", config.plugins.web.home_url)
  end,

  ["web:open-url"] = function()
    open_prompt("Open URL or File", config.plugins.web.home_url)
  end,

  ["web:open-localhost"] = function()
    open_prompt("Open Local Web App", config.plugins.web.localhost_url)
  end,
})

command.add(function()
  return active_web_view() ~= nil, active_web_view()
end, {
  ["web:set-location"] = function(view)
    prompt("Web Location", view.url or config.plugins.web.home_url, function(input)
      view:navigate(input)
    end)
  end,

  ["web:reload"] = function(view)
    if view.browser then view.browser:reload() end
  end,

  ["web:back"] = function(view)
    if view.browser then view.browser:back() end
  end,

  ["web:forward"] = function(view)
    if view.browser then view.browser:forward() end
  end,

  ["web:copy-url"] = function(view)
    system.set_clipboard(view.url or "")
  end,

  ["web:close"] = function(view)
    local node = core.root_view.root_node:get_node_for_view(view)
    if node then node:close_view(core.root_view.root_node, view) end
  end,
})

keymap.add {
  ["ctrl+shift+b"] = "web:open-active-file",
  ["ctrl+shift+l"] = "web:open-localhost",
}

return {
  WebView = WebView,
  open_tab = open_tab,
  target_to_url = target_to_url,
}
