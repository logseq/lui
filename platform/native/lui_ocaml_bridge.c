#include <stdint.h>
#include <string.h>

#include <caml/callback.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <caml/startup.h>

#include "lui_caml_dispatch.h"

#if defined(_WIN32)
#define LUI_EXPORT __declspec(dllexport)
#else
#define LUI_EXPORT __attribute__((visibility("default")))
#endif

typedef void (*lui_patch_callback)(const char *json);

static int runtime_started = 0;
static lui_patch_callback patch_callback = NULL;

/* Lock discipline: after lui_ocaml_start the host thread does NOT hold the
   OCaml runtime lock between calls, so OCaml worker domains keep running
   (stop-the-world GC included) while the host sits in its event loop. Every
   exported entry re-acquires the lock with caml_leave_blocking_section() on
   the way in and releases it with caml_enter_blocking_section() on the way
   out — including lui_ocaml_start, whose caml_startup leaves the lock held.
   caml_named_value runs only while the lock is held. Callers must be
   OCaml-registered threads and must not re-enter these functions from inside
   the patch callback, which runs while the lock is held.

   A dispatch may flush more than once. The OCaml side joins those batches
   with newlines; each line is delivered as its own callback so a re-entrant
   flush cannot drop a batch. */

static void deliver(const char *json) {
  if (patch_callback != NULL) {
    patch_callback(json);
  }
}

#define LUI_NODE_EXPORT(c_name, callback_name)                                \
  LUI_EXPORT int32_t c_name(int64_t node) {                                   \
    int32_t accepted;                                                         \
    caml_leave_blocking_section();                                            \
    accepted = lui_dispatch_node(callback_name, node, deliver);               \
    caml_enter_blocking_section();                                            \
    return accepted;                                                          \
  }

LUI_EXPORT int32_t lui_ocaml_start(lui_patch_callback callback,
                                   int32_t platform_code, int32_t host_code) {
  int32_t accepted = 0;
  patch_callback = callback;
  if (!runtime_started) {
#if defined(_WIN32)
    char_os *arguments[] = {(char_os *)L"lui_ocaml", NULL};
#else
    char *arguments[] = {"lui_ocaml", NULL};
#endif
    caml_startup(arguments);
    runtime_started = 1;
  } else {
    caml_leave_blocking_section();
  }
  accepted = lui_dispatch_init("lui_ocaml_init", platform_code, host_code,
                               deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_NODE_EXPORT(lui_ocaml_appear, "lui_ocaml_appear")
LUI_NODE_EXPORT(lui_ocaml_press, "lui_ocaml_press")
LUI_NODE_EXPORT(lui_ocaml_pointer_enter, "lui_ocaml_pointer_enter")
LUI_NODE_EXPORT(lui_ocaml_pointer_leave, "lui_ocaml_pointer_leave")
LUI_NODE_EXPORT(lui_ocaml_long_press, "lui_ocaml_long_press")
LUI_NODE_EXPORT(lui_ocaml_submit, "lui_ocaml_submit")
LUI_NODE_EXPORT(lui_ocaml_dismiss, "lui_ocaml_dismiss")
LUI_NODE_EXPORT(lui_ocaml_double_press, "lui_ocaml_double_press")
LUI_NODE_EXPORT(lui_ocaml_radio_changed, "lui_ocaml_radio_changed")
LUI_NODE_EXPORT(lui_ocaml_load, "lui_ocaml_load")

LUI_EXPORT int32_t lui_ocaml_stop(void) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_unit("lui_ocaml_dispose", deliver);
  caml_enter_blocking_section();
  return accepted;
}

/* Press carrying the host's modifier state at tap time. `modifiers` is a
   bitmask: 1=ctrl, 2=shift, 4=command/meta, 8=secondary (right click). */
LUI_EXPORT int32_t lui_ocaml_press_ex(int64_t node, int32_t modifiers) {
  int32_t accepted;
  const value *callback;
  caml_leave_blocking_section();
  callback = caml_named_value("lui_ocaml_press_ex");
  if (callback == NULL) {
    accepted = lui_dispatch_node("lui_ocaml_press", node, deliver);
  } else {
    accepted = lui_dispatch_node_int("lui_ocaml_press_ex", node, modifiers,
                                     deliver);
  }
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_press_detail(int64_t node, double x, double y,
                                          int32_t modifiers, int32_t button,
                                          const char *target_class) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_pointer(
      "lui_ocaml_press_detail", node, x, y, modifiers, button, target_class,
      target_class != NULL ? (int32_t)strlen(target_class) : 0, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_pointer_down(int64_t node, double x, double y,
                                          int32_t modifiers, int32_t button,
                                          const char *target_class) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_pointer(
      "lui_ocaml_pointer_down", node, x, y, modifiers, button, target_class,
      target_class != NULL ? (int32_t)strlen(target_class) : 0, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_pointer_up(int64_t node, double x, double y,
                                        int32_t modifiers, int32_t button,
                                        const char *target_class) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_pointer(
      "lui_ocaml_pointer_up", node, x, y, modifiers, button, target_class,
      target_class != NULL ? (int32_t)strlen(target_class) : 0, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_context_menu_press(int64_t node, double x, double y,
                                                int32_t modifiers, int32_t button,
                                                const char *target_class) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_pointer(
      "lui_ocaml_context_menu_press", node, x, y, modifiers, button,
      target_class, target_class != NULL ? (int32_t)strlen(target_class) : 0,
      deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_text_changed_utf8(int64_t node, const char *text,
                                               int32_t byte_length) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_bytes("lui_ocaml_text_changed", node, text,
                                byte_length, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_text_changed(int64_t node, const char *text) {
  if (text == NULL) {
    return 0;
  }
  return lui_ocaml_text_changed_utf8(node, text, (int32_t)strlen(text));
}

LUI_EXPORT int32_t lui_ocaml_picked_utf8(int64_t node, const char *payload,
                                         int32_t byte_length) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_bytes("lui_ocaml_picked", node, payload, byte_length,
                                deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_picked(int64_t node, const char *payload) {
  if (payload == NULL) {
    return 0;
  }
  return lui_ocaml_picked_utf8(node, payload, (int32_t)strlen(payload));
}

LUI_EXPORT int32_t lui_ocaml_toggle_changed(int64_t node, int32_t checked) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_node_bool("lui_ocaml_toggle_changed", node, checked,
                                    deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_slider_changed(int64_t node, double fraction) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_node_double("lui_ocaml_slider_changed", node,
                                      fraction, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_visible_range(int64_t node, int64_t first,
                                           int64_t last) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_visible_range("lui_ocaml_visible_range", node, first,
                                        last, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_scroll_completed(int64_t node, int64_t token,
                                              const char *outcome) {
  int32_t accepted;
  int32_t length;
  if (outcome == NULL) {
    return 0;
  }
  length = (int32_t)strlen(outcome);
  caml_leave_blocking_section();
  accepted = lui_dispatch_scroll_completed("lui_ocaml_scroll_completed", node,
                                           token, outcome, length, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_extension_event_utf8(
    int64_t node, const char *identifier, int32_t identifier_len,
    const char *name, int32_t name_len, const char *json_values,
    int32_t json_len) {
  int32_t accepted;
  if (identifier == NULL || name == NULL || identifier_len < 0 ||
      name_len < 0) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = lui_dispatch_extension(
      "lui_ocaml_extension_event", node, identifier, identifier_len, name,
      name_len, json_values != NULL ? json_values : "",
      json_values != NULL && json_len >= 0 ? json_len : 0, deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_extension_event(int64_t node, const char *identifier,
                                             const char *name,
                                             const char *json_values) {
  if (identifier == NULL || name == NULL) {
    return 0;
  }
  return lui_ocaml_extension_event_utf8(
      node, identifier, (int32_t)strlen(identifier), name, (int32_t)strlen(name),
      json_values, json_values != NULL ? (int32_t)strlen(json_values) : 0);
}

/* Host recovery: deliver a full-tree batch at the runtime's current
   generation. The host clears its mirror, then applies the batch. */
LUI_EXPORT int32_t lui_ocaml_resync(void) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_unit("lui_ocaml_resync", deliver);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int64_t lui_ocaml_root_node(void) {
  int64_t node;
  caml_leave_blocking_section();
  node = lui_dispatch_root("lui_ocaml_root_node");
  caml_enter_blocking_section();
  return node;
}
