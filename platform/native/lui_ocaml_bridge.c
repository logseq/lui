#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/printexc.h>
#include <caml/signals.h>
#include <caml/startup.h>

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
   Callers must therefore be OCaml-registered threads (the thread that ran
   lui_ocaml_start, or one registered via caml_c_thread_register) and must
   not re-enter these functions from inside the patch callback, which runs
   while the lock is held. */

static int emit_patch(value result) {
  if (Is_exception_result(result)) {
    char *message = caml_format_exception(Extract_exception(result));
    fprintf(stderr, "lui_ocaml_bridge: OCaml exception: %s\n", message);
    caml_stat_free(message);
    return 0;
  }
  const char *json = String_val(result);
  if (patch_callback != NULL && json[0] != '\0') {
    patch_callback(json);
  }
  return 1;
}

LUI_EXPORT int32_t lui_ocaml_start(
    lui_patch_callback callback,
    int32_t platform_code,
    int32_t host_code) {
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

  const value *initialize = caml_named_value("lui_ocaml_init");
  if (initialize != NULL) {
    accepted = emit_patch(caml_callback2_exn(
        *initialize,
        Val_long(platform_code),
        Val_long(host_code)));
  }
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_appear(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_appear");
  int32_t accepted = 0;
  if (dispatch == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_press");
  int32_t accepted = 0;
  if (dispatch == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

/* Press carrying the host's modifier state at tap time. `modifiers` is a
   bitmask: 1=ctrl, 2=shift, 4=command/meta, 8=secondary (right click). */
static int32_t press_ex_locked(int64_t node, int32_t modifiers) {
  const value *dispatch = caml_named_value("lui_ocaml_press_ex");
  if (dispatch == NULL) {
    /* Fall back to the plain press dispatch while the lock is held. */
    dispatch = caml_named_value("lui_ocaml_press");
    if (dispatch == NULL) {
      return 0;
    }
    return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  }
  return emit_patch(caml_callback2_exn(
      *dispatch, Val_long(node), Val_long(modifiers)));
}

LUI_EXPORT int32_t lui_ocaml_press_ex(int64_t node, int32_t modifiers) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = press_ex_locked(node, modifiers);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_long_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_long_press");
  int32_t accepted = 0;
  if (dispatch == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

static int32_t text_changed_locked(
    int64_t node,
    const char *text,
    int32_t byte_length) {
  CAMLparam0();
  CAMLlocal2(text_value, result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_ocaml_text_changed");
  if (dispatch != NULL && text != NULL && byte_length >= 0) {
    text_value = caml_alloc_initialized_string(byte_length, text);
    result = caml_callback2_exn(*dispatch, Val_long(node), text_value);
    accepted = emit_patch(result);
  }
  CAMLreturnT(int32_t, accepted);
}

/* Length-explicit variant: text may contain embedded NUL bytes. */
LUI_EXPORT int32_t lui_ocaml_text_changed_utf8(
    int64_t node,
    const char *text,
    int32_t byte_length) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = text_changed_locked(node, text, byte_length);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_text_changed(int64_t node, const char *text) {
  if (text == NULL) {
    return 0;
  }
  return lui_ocaml_text_changed_utf8(node, text, (int32_t)strlen(text));
}

LUI_EXPORT int32_t lui_ocaml_submit(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_submit");
  int32_t accepted = 0;
  if (dispatch == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_dismiss(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_dismiss");
  int32_t accepted = 0;
  if (dispatch == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

static int32_t picked_locked(
    int64_t node,
    const char *payload,
    int32_t byte_length) {
  CAMLparam0();
  CAMLlocal2(payload_value, result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_ocaml_picked");
  if (dispatch != NULL && payload != NULL && byte_length >= 0) {
    payload_value = caml_alloc_initialized_string(byte_length, payload);
    result = caml_callback2_exn(*dispatch, Val_long(node), payload_value);
    accepted = emit_patch(result);
  }
  CAMLreturnT(int32_t, accepted);
}

/* Length-explicit variant: payload may contain embedded NUL bytes. */
LUI_EXPORT int32_t lui_ocaml_picked_utf8(
    int64_t node,
    const char *payload,
    int32_t byte_length) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = picked_locked(node, payload, byte_length);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_picked(int64_t node, const char *payload) {
  if (payload == NULL) {
    return 0;
  }
  return lui_ocaml_picked_utf8(node, payload, (int32_t)strlen(payload));
}

LUI_EXPORT int32_t lui_ocaml_double_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_double_press");
  int32_t accepted = 0;
  if (dispatch == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

static int32_t toggle_changed_locked(int64_t node, int32_t checked) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_ocaml_toggle_changed");
  if (dispatch != NULL) {
    result = caml_callback2_exn(
        *dispatch,
        Val_long(node),
        Val_bool(checked != 0));
    accepted = emit_patch(result);
  }
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_toggle_changed(int64_t node, int32_t checked) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = toggle_changed_locked(node, checked);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_radio_changed(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_radio_changed");
  int32_t accepted = 0;
  if (dispatch == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

static int32_t slider_changed_locked(int64_t node, double fraction) {
  CAMLparam0();
  CAMLlocal2(value_value, result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_ocaml_slider_changed");
  if (dispatch != NULL) {
    value_value = caml_copy_double(fraction);
    result = caml_callback2_exn(*dispatch, Val_long(node), value_value);
    accepted = emit_patch(result);
  }
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_slider_changed(int64_t node, double fraction) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = slider_changed_locked(node, fraction);
  caml_enter_blocking_section();
  return accepted;
}

LUI_EXPORT int32_t lui_ocaml_stop(void) {
  const value *dispose = caml_named_value("lui_ocaml_dispose");
  int32_t accepted = 0;
  if (dispose == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispose, Val_unit));
  caml_enter_blocking_section();
  return accepted;
}

static int64_t read_node(const char *callback_name) {
  const value *callback = caml_named_value(callback_name);
  value result;
  int64_t node;
  if (callback == NULL) {
    return -1;
  }
  caml_leave_blocking_section();
  result = caml_callback_exn(*callback, Val_unit);
  node = Is_exception_result(result) ? -1 : Long_val(result);
  caml_enter_blocking_section();
  return node;
}

LUI_EXPORT int64_t lui_ocaml_root_node(void) {
  return read_node("lui_ocaml_root_node");
}

static int32_t extension_event_locked(
    int64_t node,
    const char *identifier,
    const char *name,
    const char *json_values) {
  CAMLparam0();
  CAMLlocal4(identifier_value, name_value, values_value, result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_ocaml_extension_event");
  if (dispatch != NULL && identifier != NULL && name != NULL) {
    value arguments[4];
    identifier_value = caml_copy_string(identifier);
    name_value = caml_copy_string(name);
    values_value = caml_copy_string(json_values == NULL ? "" : json_values);
    arguments[0] = Val_long(node);
    arguments[1] = identifier_value;
    arguments[2] = name_value;
    arguments[3] = values_value;
    result = caml_callbackN_exn(*dispatch, 4, arguments);
    accepted = emit_patch(result);
  }
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_extension_event(
    int64_t node,
    const char *identifier,
    const char *name,
    const char *json_values) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = extension_event_locked(node, identifier, name, json_values);
  caml_enter_blocking_section();
  return accepted;
}
