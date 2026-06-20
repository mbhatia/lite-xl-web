#define LITE_XL_PLUGIN_ENTRYPOINT
#include <lite_xl_plugin_api.h>

static int f_new(lua_State *L) {
  return luaL_error(L, "lite-xl-web has no native webview backend for this platform yet");
}

static const luaL_Reg module_methods[] = {
  { "new", f_new },
  { NULL, NULL }
};

static int open_module(lua_State *L) {
  lua_newtable(L);
  luaL_setfuncs(L, module_methods, 0);
  lua_pushliteral(L, "0.1.4");
  lua_setfield(L, -2, "version");
  lua_pushboolean(L, 0);
  lua_setfield(L, -2, "supported");
  lua_pushliteral(L, "native webview backend is currently implemented for macOS only");
  lua_setfield(L, -2, "reason");
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
