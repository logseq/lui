/* Real dynamic-library ABI fixture; deliberately no generic clock/error APIs.
   This checks the Rust/C contract, not OCaml startup or Logseq application UX. */
#include <stdint.h>
#include <string.h>
#include <pthread.h>

typedef void (*patch_fn)(const char *);
typedef void (*wake_fn)(void);
typedef void (*request_fn)(const char *, int32_t);
static patch_fn patches;
static wake_fn wake;
static request_fn request;
static pthread_t owner;
static int running;
static int pending;
static int same_thread(void) { return running && pthread_equal(owner, pthread_self()); }
static void *foreign_wakeup(void *unused) { (void)unused; wake(); return NULL; }

int32_t lui_ocaml_start(patch_fn emit, wake_fn wakeup, request_fn service,
                       int32_t platform, int32_t host, const char *payload, int32_t len) {
  const char expected[] = "{\"paintsCaret\":false}";
  if (running || platform != 1 || host != 6 || len != (int32_t)strlen(expected)
      || memcmp(payload, expected, (size_t)len) != 0) return 0;
  owner = pthread_self(); running = 1; pending = 1;
  patches = emit; wake = wakeup; request = service;
  const char icons[] = "app-icons\n{\"app:test\":\"<svg/>\"}";
  request(icons, (int32_t)strlen(icons));
  patches("[{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"column\"}]}]");
  pthread_t thread;
  if (pthread_create(&thread, NULL, foreign_wakeup, NULL) != 0) return 0;
  return pthread_join(thread, NULL) == 0;
}
int32_t lui_ocaml_pump(void) {
  if (!same_thread()) return 0;
  if (pending == 1) {
    pending = 0;
    patches("[{\"generation\":2,\"ops\":[]}]");
    const char measure[] = "measure-node\n{\"ref\":\"#sidebar\"}";
    request(measure, (int32_t)strlen(measure));
  } else if (pending == 2) {
    pending = 0;
    patches("[{\"generation\":3,\"ops\":[]}]");
  }
  return 1;
}
int32_t lui_ocaml_platform_event(const char *data, int32_t len) {
  const char expected[] = "node-rect\nA\0\xE4\xB8\xAD";
  if (!same_thread() || len != (int32_t)sizeof(expected)-1
      || memcmp(data, expected, (size_t)len) != 0) return 0;
  pending = 2;
  return 1;
}
int32_t lui_ocaml_stop(void) { if (!same_thread()) return 0; running = 0; return 1; }
int64_t lui_ocaml_root_node(void) { return same_thread() ? 1 : 0; }
int32_t lui_ocaml_resync(void) {
  if (!same_thread()) return 0;
  patches("[{\"generation\":3,\"ops\":[]}]"); return 1;
}
#define NODE(name) int32_t name(int64_t node) { (void)node; return same_thread(); }
NODE(lui_ocaml_submit)
NODE(lui_ocaml_appear)
NODE(lui_ocaml_radio_changed)
NODE(lui_ocaml_dismiss)
int32_t lui_ocaml_press_ex(int64_t n, int32_t m) { (void)n; (void)m; return same_thread(); }
int32_t lui_ocaml_toggle_changed(int64_t n, int32_t v) { (void)n; (void)v; return same_thread(); }
int32_t lui_ocaml_toggle_changed_detail(int64_t node, int32_t checked, int32_t modifiers) {
  return same_thread() && node == 29 && checked == 1 && modifiers == 15;
}
int32_t lui_ocaml_slider_changed(int64_t n, double v) { (void)n; (void)v; return same_thread(); }
int32_t lui_ocaml_text_changed_utf8(int64_t n, const char *s, int32_t l) { (void)n; (void)s; (void)l; return same_thread(); }
int32_t lui_ocaml_press_detail_clicks_utf8(int64_t n, double x, double y,
    int32_t modifiers, int32_t button, const char *target, int32_t len, int32_t clicks) {
  const char expected[] = "A\0\xE4\xB8\xAD";
  return same_thread() && n == 31 && x == 12.5 && y == -6.25
    && modifiers == 5 && button == 0 && clicks == 2
    && len == (int32_t)sizeof(expected)-1 && target != NULL
    && memcmp(target, expected, (size_t)len) == 0;
}
int32_t lui_ocaml_visible_range(int64_t n, int64_t a, int64_t b) { (void)n; (void)a; (void)b; return same_thread(); }
int32_t lui_ocaml_editor_snapshot_utf8(const char *id, int32_t len, request_fn receive) {
  if (!same_thread()) return 0;
  const char active[] = "block\0id";
  const char *json = len == (int32_t)sizeof(active)-1 && memcmp(id, active, (size_t)len) == 0
    ? "{\"source\":\"A\xE4\xB8\xAD\",\"anchor\":1,\"caret\":4}" : "null";
  receive(json, (int32_t)strlen(json));
  return 1;
}
int32_t lui_ocaml_agent_utf8(const char *data, int32_t len, patch_fn reply) {
  const char expected[] = "{\"op\":\"hello\",\"probe\":\"\xE4\xB8\xAD\"}";
  if (!same_thread() || len != (int32_t)sizeof(expected)-1
      || memcmp(data, expected, (size_t)len) != 0 || reply == NULL) return 0;
  patches("[{\"generation\":4,\"ops\":[]}]");
  const char service[] = "agent-probe\n{\"ordered\":true}";
  request(service, (int32_t)strlen(service));
  reply("{\"ok\":true,\"op\":\"hello\",\"host\":\"logseq-native\"}");
  return 1;
}
