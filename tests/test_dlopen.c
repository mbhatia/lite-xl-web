#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static char *read_file(const char *path, size_t *size) {
  FILE *file = fopen(path, "rb");
  char *buffer;
  long length;

  if (!file) {
    fprintf(stderr, "open failed: %s\n", path);
    return NULL;
  }

  if (fseek(file, 0, SEEK_END) != 0) {
    fprintf(stderr, "seek failed: %s\n", path);
    fclose(file);
    return NULL;
  }

  length = ftell(file);
  if (length < 0) {
    fprintf(stderr, "tell failed: %s\n", path);
    fclose(file);
    return NULL;
  }
  rewind(file);

  buffer = malloc((size_t)length + 1);
  if (!buffer) {
    fprintf(stderr, "allocation failed\n");
    fclose(file);
    return NULL;
  }

  if (fread(buffer, 1, (size_t)length, file) != (size_t)length) {
    fprintf(stderr, "read failed: %s\n", path);
    free(buffer);
    fclose(file);
    return NULL;
  }

  buffer[length] = '\0';
  fclose(file);
  if (size) *size = (size_t)length;
  return buffer;
}

static int contains_bytes(const char *haystack, size_t haystack_size, const char *needle) {
  size_t needle_size = strlen(needle);
  size_t i;

  if (needle_size == 0 || haystack_size < needle_size) return 0;
  for (i = 0; i <= haystack_size - needle_size; i++) {
    if (memcmp(haystack + i, needle, needle_size) == 0) return 1;
  }
  return 0;
}

static int require_file_contains(const char *path, const char *needle) {
  size_t size = 0;
  char *contents = read_file(path, &size);
  int ok;

  if (!contents) return 1;
  ok = contains_bytes(contents, size, needle);
  free(contents);

  if (!ok) {
    fprintf(stderr, "%s does not contain expected interface string: %s\n", path, needle);
    return 1;
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s MODULE LUA_PLUGIN EXPECT_NATIVE_DETACH\n", argv[0]);
    return 2;
  }

  void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!handle) {
    fprintf(stderr, "dlopen failed: %s\n", dlerror());
    return 1;
  }

  void *entrypoint = dlsym(handle, "luaopen_lite_xl_web_lxl");
  if (!entrypoint) {
    fprintf(stderr, "dlsym failed: %s\n", dlerror());
    dlclose(handle);
    return 1;
  }

  dlclose(handle);

  if (strcmp(argv[3], "1") == 0 && require_file_contains(argv[1], "detach")) return 1;
  if (require_file_contains(argv[2], "function WebView:detach")) return 1;

  return 0;
}
