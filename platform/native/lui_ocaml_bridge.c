#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/printexc.h>
#include <caml/startup.h>

#if defined(_WIN32)
#define LUI_EXPORT __declspec(dllexport)
#else
#define LUI_EXPORT __attribute__((visibility("default")))
#endif

typedef void (*lui_patch_callback)(const char *json);

static int runtime_started = 0;
static lui_patch_callback patch_callback = NULL;

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
  patch_callback = callback;
  if (!runtime_started) {
    char *arguments[] = {"lui_ocaml", NULL};
    caml_startup(arguments);
    runtime_started = 1;
  }

  const value *initialize = caml_named_value("lui_ocaml_init");
  if (initialize == NULL) {
    return 0;
  }
  return emit_patch(caml_callback2_exn(
      *initialize,
      Val_long(platform_code),
      Val_long(host_code)));
}

LUI_EXPORT int32_t lui_ocaml_appear(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_appear");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_press");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_long_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_long_press");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_text_changed(int64_t node, const char *text) {
  CAMLparam0();
  CAMLlocal2(text_value, result);
  const value *dispatch = caml_named_value("lui_ocaml_text_changed");
  if (dispatch == NULL || text == NULL) {
    CAMLreturnT(int32_t, 0);
  }
  text_value = caml_copy_string(text);
  result = caml_callback2_exn(*dispatch, Val_long(node), text_value);
  int32_t accepted = emit_patch(result);
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_submit(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_submit");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_dismiss(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_dismiss");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_double_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_double_press");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_toggle_changed(int64_t node, int32_t checked) {
  CAMLparam0();
  CAMLlocal1(result);
  const value *dispatch = caml_named_value("lui_ocaml_toggle_changed");
  if (dispatch == NULL) {
    CAMLreturnT(int32_t, 0);
  }
  result = caml_callback2_exn(
      *dispatch,
      Val_long(node),
      Val_bool(checked != 0));
  int32_t accepted = emit_patch(result);
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_radio_changed(int64_t node) {
  const value *dispatch = caml_named_value("lui_ocaml_radio_changed");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_slider_changed(int64_t node, double fraction) {
  CAMLparam0();
  CAMLlocal2(value_value, result);
  const value *dispatch = caml_named_value("lui_ocaml_slider_changed");
  if (dispatch == NULL) {
    CAMLreturnT(int32_t, 0);
  }
  value_value = caml_copy_double(fraction);
  result = caml_callback2_exn(*dispatch, Val_long(node), value_value);
  int32_t accepted = emit_patch(result);
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_stop(void) {
  const value *dispose = caml_named_value("lui_ocaml_dispose");
  if (dispose == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispose, Val_unit));
}

static int64_t read_node(const char *callback_name) {
  const value *callback = caml_named_value(callback_name);
  if (callback == NULL) {
    return -1;
  }
  value result = caml_callback_exn(*callback, Val_unit);
  return Is_exception_result(result) ? -1 : Long_val(result);
}

LUI_EXPORT int64_t lui_ocaml_root_node(void) {
  return read_node("lui_ocaml_root_node");
}

LUI_EXPORT int32_t lui_ocaml_extension_event(
    int64_t node,
    const char *identifier,
    const char *name,
    const char *json_values) {
  CAMLparam0();
  CAMLlocal4(identifier_value, name_value, values_value, result);
  const value *dispatch = caml_named_value("lui_ocaml_extension_event");
  if (dispatch == NULL || identifier == NULL || name == NULL) {
    CAMLreturnT(int32_t, 0);
  }
  identifier_value = caml_copy_string(identifier);
  name_value = caml_copy_string(name);
  values_value = caml_copy_string(json_values == NULL ? "" : json_values);
  {
    value arguments[4];
    int32_t accepted;
    arguments[0] = Val_long(node);
    arguments[1] = identifier_value;
    arguments[2] = name_value;
    arguments[3] = values_value;
    result = caml_callbackN_exn(*dispatch, 4, arguments);
    accepted = emit_patch(result);
    CAMLreturnT(int32_t, accepted);
  }
}
