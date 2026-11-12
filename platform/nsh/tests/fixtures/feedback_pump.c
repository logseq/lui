/* ABI fixture for the real Desktop request pump; native NSH computes feedback. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>

typedef void (*patch_fn)(const char *);
typedef void (*wake_fn)(void);
typedef void (*request_fn)(const char *, int32_t);
static patch_fn patches;
static pthread_t owner;
static int running;
static unsigned generation;
static unsigned feedback;
static int same_thread(void) { return running && pthread_equal(owner, pthread_self()); }

int32_t lui_ocaml_start(patch_fn emit, wake_fn wakeup, request_fn service,
                       int32_t platform, int32_t host, const char *payload, int32_t len) {
  (void)wakeup; (void)platform;
  if (running || host != 6 || len != 2 || memcmp(payload, "{}", 2) != 0) return 0;
  owner = pthread_self(); running = 1; generation = 1; feedback = 0; patches = emit;
  patches("[{\"generation\":1,\"ops\":["
    "{\"op\":\"create-node\",\"id\":1,\"kind\":\"column\"},"
    "{\"op\":\"create-node\",\"id\":2,\"kind\":\"virtual-list\"},"
    "{\"op\":\"set-prop\",\"id\":2,\"property\":\"height\",\"value\":320},"
    "{\"op\":\"set-prop\",\"id\":2,\"property\":\"width\",\"value\":400},"
    "{\"op\":\"set-prop\",\"id\":2,\"property\":\"virtual-total-count\",\"value\":100},"
    "{\"op\":\"set-prop\",\"id\":2,\"property\":\"virtual-generation\",\"value\":1},"
    "{\"op\":\"set-prop\",\"id\":2,\"property\":\"virtual-indices\",\"value\":\"[]\"},"
    "{\"op\":\"set-prop\",\"id\":2,\"property\":\"track-visible-range\",\"value\":true},"
    "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},"
    "{\"op\":\"create-node\",\"id\":3,\"kind\":\"text\"},"
    "{\"op\":\"set-prop\",\"id\":3,\"property\":\"text\",\"value\":\"Waiting for native feedback\"},"
    "{\"op\":\"insert-child\",\"parent\":1,\"child\":3,\"index\":1}]}]");
  const char request[] = "saturate-before-layout\n{}";
  service(request, (int32_t)strlen(request));
  return 1;
}
static int record_feedback(unsigned kind) {
  if (!same_thread()) return 0;
  feedback |= kind;
  char batch[512];
  int len = snprintf(batch, sizeof(batch),
    "[{\"generation\":%u,\"ops\":[{\"op\":\"set-prop\",\"id\":3,"
    "\"property\":\"text\",\"value\":\"%s\"}]}]", ++generation,
    feedback == 3 ? "Both native feedback kinds delivered" : "One native feedback kind delivered");
  if (len < 0 || (size_t)len >= sizeof(batch)) return 0;
  patches(batch);
  return 1;
}
int32_t lui_ocaml_virtual_window(int64_t node, int64_t source, int64_t first,
                                int64_t last, const int64_t *pins, int32_t len) {
  (void)pins;
  return node == 2 && source == 1 && first >= 0 && last > first && len == 0
    && record_feedback(1);
}
int32_t lui_ocaml_visible_range(int64_t node, int64_t first, int64_t last) {
  return node == 2 && first >= 0 && last >= first && record_feedback(2);
}
int32_t lui_ocaml_pump(void) { return same_thread(); }
int32_t lui_ocaml_platform_event(const char *data, int32_t len) {
  (void)data; (void)len; return same_thread();
}
int32_t lui_ocaml_stop(void) { if (!same_thread()) return 0; running = 0; return 1; }
int64_t lui_ocaml_root_node(void) { return same_thread() ? 1 : 0; }
int32_t lui_ocaml_resync(void) { return 0; }
#define NODE(name) int32_t name(int64_t node) { (void)node; return same_thread(); }
NODE(lui_ocaml_submit)
NODE(lui_ocaml_appear)
NODE(lui_ocaml_radio_changed)
NODE(lui_ocaml_dismiss)
int32_t lui_ocaml_press_ex(int64_t n, int32_t m) { (void)n; (void)m; return same_thread(); }
int32_t lui_ocaml_toggle_changed(int64_t n, int32_t v) { (void)n; (void)v; return same_thread(); }
int32_t lui_ocaml_slider_changed(int64_t n, double v) { (void)n; (void)v; return same_thread(); }
int32_t lui_ocaml_text_changed_utf8(int64_t n, const char *s, int32_t l) {
  (void)n; (void)s; (void)l; return same_thread();
}
