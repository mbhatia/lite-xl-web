#define LITE_XL_PLUGIN_ENTRYPOINT
#include <lite_xl_plugin_api.h>

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <dispatch/dispatch.h>

#define LXL_WEB_USERDATA "lite_xl_web_lxl.view"

@interface LxlEmbeddedWebView : NSObject <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, weak) NSView *hostView;
@property(nonatomic, copy) NSString *lastURL;
@property(nonatomic, copy) NSString *lastTitle;
@property(nonatomic, assign) CGFloat uiScale;
@property(nonatomic, assign) BOOL closed;
@end

@implementation LxlEmbeddedWebView
- (instancetype)initWithScale:(CGFloat)scale {
  self = [super init];
  if (!self) return nil;
  WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
  self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
  self.webView.navigationDelegate = self;
  self.webView.autoresizingMask = NSViewNotSizable;
  self.webView.hidden = YES;
  self.uiScale = MAX(scale, 0.2);
  self.closed = NO;
  [self applyScale];
  return self;
}

- (NSView *)currentHostView {
  NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow;
  if (!window) {
    for (NSWindow *candidate in NSApp.windows) {
      if (candidate.isVisible && candidate.contentView) {
        window = candidate;
        break;
      }
    }
  }
  return window.contentView;
}

- (void)attachIfNeeded {
  if (self.closed) return;
  NSView *host = [self currentHostView];
  if (!host) return;
  if (self.webView.superview != host) {
    [self.webView removeFromSuperview];
    [host addSubview:self.webView positioned:NSWindowAbove relativeTo:nil];
    self.hostView = host;
  }
}

- (void)setLiteX:(CGFloat)x y:(CGFloat)y width:(CGFloat)width height:(CGFloat)height visible:(BOOL)visible {
  if (self.closed) return;
  [self attachIfNeeded];
  NSView *host = self.webView.superview ?: self.hostView;
  if (!host) return;
  CGFloat clampedWidth = MAX(width, 1.0);
  CGFloat clampedHeight = MAX(height, 1.0);
  CGFloat flippedY = NSHeight(host.bounds) - y - clampedHeight;
  self.webView.frame = NSIntegralRect(NSMakeRect(x, flippedY, clampedWidth, clampedHeight));
  self.webView.hidden = !visible;
}

- (void)setVisible:(BOOL)visible {
  if (self.closed) return;
  if (visible) [self attachIfNeeded];
  self.webView.hidden = !visible;
}

- (BOOL)responderIsWebViewOrDescendant:(NSResponder *)responder {
  if (!responder) return NO;
  if (responder == self.webView) return YES;
  if (![responder isKindOfClass:[NSView class]]) return NO;
  NSView *view = (NSView *)responder;
  return view == self.webView || [view isDescendantOf:self.webView];
}

- (void)focus {
  if (self.closed) return;
  [self attachIfNeeded];
  self.webView.hidden = NO;
  [self.webView.window makeFirstResponder:self.webView];
}

- (void)blur {
  if (self.closed) return;
  NSWindow *window = self.webView.window ?: self.hostView.window;
  if (!window) return;
  if (![self responderIsWebViewOrDescendant:window.firstResponder]) return;

  NSView *fallback = self.hostView ?: window.contentView;
  if (!fallback || fallback.window != window || ![window makeFirstResponder:fallback]) {
    [window makeFirstResponder:nil];
  }
}

- (void)detach {
  if (self.closed) return;
  [self blur];
  self.webView.hidden = YES;
  [self.webView removeFromSuperview];
}

- (void)closeView {
  if (self.closed) return;
  self.closed = YES;
  self.webView.navigationDelegate = nil;
  [self.webView removeFromSuperview];
}

- (void)loadURLString:(NSString *)urlString {
  if (self.closed || !urlString.length) return;
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  self.lastURL = url.absoluteString;
  if (url.fileURL) {
    NSURL *accessURL = [url URLByDeletingLastPathComponent] ?: url;
    [self.webView loadFileURL:url allowingReadAccessToURL:accessURL];
  } else {
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
  }
}

- (void)setUIScale:(CGFloat)scale {
  if (self.closed) return;
  self.uiScale = MAX(scale, 0.2);
  [self applyScale];
}

- (void)applyScale {
  if (!self.webView) return;
  if (@available(macOS 11.0, *)) {
    self.webView.pageZoom = self.uiScale;
  } else {
    self.webView.magnification = self.uiScale;
  }
}

- (void)reload {
  if (!self.closed) [self.webView reload:nil];
}

- (void)goBack {
  if (!self.closed && self.webView.canGoBack) [self.webView goBack];
}

- (void)goForward {
  if (!self.closed && self.webView.canGoForward) [self.webView goForward];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
  (void)navigation;
  self.lastURL = webView.URL.absoluteString;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  (void)navigation;
  self.lastURL = webView.URL.absoluteString;
  self.lastTitle = webView.title;
  [self applyScale];
}
@end

typedef struct {
  void *view;
} LuaWebView;

static void on_main_sync(dispatch_block_t block) {
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
}

static LuaWebView *check_view(lua_State *L, int index) {
  return (LuaWebView *)luaL_checkudata(L, index, LXL_WEB_USERDATA);
}

static LxlEmbeddedWebView *get_view(lua_State *L, int index) {
  LuaWebView *ud = check_view(L, index);
  if (!ud->view) luaL_error(L, "webview is closed");
  return (__bridge LxlEmbeddedWebView *)ud->view;
}

static NSString *lua_string(lua_State *L, int index, const char *fallback) {
  const char *value = lua_tostring(L, index);
  if (!value) value = fallback;
  return [NSString stringWithUTF8String:value ?: ""];
}

static void close_userdata(LuaWebView *ud) {
  if (!ud || !ud->view) return;
  LxlEmbeddedWebView *view = (__bridge_transfer LxlEmbeddedWebView *)ud->view;
  ud->view = NULL;
  on_main_sync(^{ [view closeView]; });
}

static int f_gc(lua_State *L) {
  close_userdata(check_view(L, 1));
  return 0;
}

static int f_close(lua_State *L) {
  close_userdata(check_view(L, 1));
  return 0;
}

static int f_new(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  lua_getfield(L, 1, "url");
  NSString *url = lua_string(L, -1, "about:blank");
  lua_pop(L, 1);
  lua_getfield(L, 1, "scale");
  CGFloat scale = lua_isnumber(L, -1) ? (CGFloat)lua_tonumber(L, -1) : 1.0;
  lua_pop(L, 1);

  __block LxlEmbeddedWebView *view = nil;
  on_main_sync(^{
    [NSApplication sharedApplication];
    view = [[LxlEmbeddedWebView alloc] initWithScale:scale];
    [view loadURLString:url];
  });

  LuaWebView *ud = (LuaWebView *)lua_newuserdata(L, sizeof(*ud));
  ud->view = (__bridge_retained void *)view;
  luaL_getmetatable(L, LXL_WEB_USERDATA);
  lua_setmetatable(L, -2);
  return 1;
}

static int f_load_url(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  NSString *url = lua_string(L, 2, "about:blank");
  on_main_sync(^{ [view loadURLString:url]; });
  return 0;
}

static int f_set_rect(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  CGFloat x = (CGFloat)luaL_checknumber(L, 2);
  CGFloat y = (CGFloat)luaL_checknumber(L, 3);
  CGFloat width = (CGFloat)luaL_checknumber(L, 4);
  CGFloat height = (CGFloat)luaL_checknumber(L, 5);
  BOOL visible = lua_isnoneornil(L, 6) ? YES : lua_toboolean(L, 6);
  on_main_sync(^{ [view setLiteX:x y:y width:width height:height visible:visible]; });
  return 0;
}

static int f_set_scale(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  CGFloat scale = (CGFloat)luaL_checknumber(L, 2);
  on_main_sync(^{ [view setUIScale:scale]; });
  return 0;
}

static int f_set_visible(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  BOOL visible = lua_toboolean(L, 2);
  on_main_sync(^{ [view setVisible:visible]; });
  return 0;
}

static int f_reload(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  on_main_sync(^{ [view reload]; });
  return 0;
}

static int f_back(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  on_main_sync(^{ [view goBack]; });
  return 0;
}

static int f_forward(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  on_main_sync(^{ [view goForward]; });
  return 0;
}

static int f_focus(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  on_main_sync(^{ [view focus]; });
  return 0;
}

static int f_blur(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  on_main_sync(^{ [view blur]; });
  return 0;
}

static int f_detach(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  on_main_sync(^{ [view detach]; });
  return 0;
}

static int f_status(lua_State *L) {
  LxlEmbeddedWebView *view = get_view(L, 1);
  __block BOOL closed = NO;
  __block BOOL loading = NO;
  __block BOOL canGoBack = NO;
  __block BOOL canGoForward = NO;
  __block NSString *url = @"";
  __block NSString *title = @"";

  on_main_sync(^{
    closed = view.closed;
    loading = view.webView.loading;
    canGoBack = view.webView.canGoBack;
    canGoForward = view.webView.canGoForward;
    url = view.webView.URL.absoluteString ?: view.lastURL ?: @"";
    title = view.webView.title ?: view.lastTitle ?: @"";
  });

  lua_newtable(L);
  lua_pushboolean(L, closed);
  lua_setfield(L, -2, "closed");
  lua_pushboolean(L, loading);
  lua_setfield(L, -2, "loading");
  lua_pushboolean(L, canGoBack);
  lua_setfield(L, -2, "can_go_back");
  lua_pushboolean(L, canGoForward);
  lua_setfield(L, -2, "can_go_forward");
  lua_pushstring(L, url.UTF8String ?: "");
  lua_setfield(L, -2, "url");
  lua_pushstring(L, title.UTF8String ?: "");
  lua_setfield(L, -2, "title");
  return 1;
}

static const luaL_Reg view_methods[] = {
  { "__gc", f_gc },
  { "close", f_close },
  { "load_url", f_load_url },
  { "set_rect", f_set_rect },
  { "set_scale", f_set_scale },
  { "set_visible", f_set_visible },
  { "reload", f_reload },
  { "back", f_back },
  { "forward", f_forward },
  { "focus", f_focus },
  { "blur", f_blur },
  { "detach", f_detach },
  { "status", f_status },
  { NULL, NULL }
};

static const luaL_Reg module_methods[] = {
  { "new", f_new },
  { NULL, NULL }
};

static int open_module(lua_State *L) {
  luaL_newmetatable(L, LXL_WEB_USERDATA);
  luaL_setfuncs(L, view_methods, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);

  lua_newtable(L);
  luaL_setfuncs(L, module_methods, 0);
  lua_pushliteral(L, "0.1.5");
  lua_setfield(L, -2, "version");
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "supported");
  return 1;
}

int luaopen_lite_xl_libweb_lxl(lua_State *L, void *XL) {
  lite_xl_plugin_init(XL);
  return open_module(L);
}

int luaopen_lite_xl_web_lxl(lua_State *L, void *XL) {
  lite_xl_plugin_init(XL);
  return open_module(L);
}
