#include <stdint.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/mlvalues.h>
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
    char *arguments[] = {"lui_flutter", NULL};
    caml_startup(arguments);
    runtime_started = 1;
  }

  const value *initialize = caml_named_value("lui_flutter_init");
  if (initialize == NULL) {
    return 0;
  }
  return emit_patch(caml_callback2_exn(
      *initialize,
      Val_long(platform_code),
      Val_long(host_code)));
}

LUI_EXPORT int32_t lui_ocaml_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_flutter_press");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_hold(int64_t node) {
  const value *dispatch = caml_named_value("lui_flutter_hold");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_text_changed(int64_t node, const char *text) {
  CAMLparam0();
  CAMLlocal2(text_value, result);
  const value *dispatch = caml_named_value("lui_flutter_text_changed");
  if (dispatch == NULL || text == NULL) {
    CAMLreturnT(int32_t, 0);
  }
  text_value = caml_copy_string(text);
  result = caml_callback2_exn(*dispatch, Val_long(node), text_value);
  int32_t accepted = emit_patch(result);
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_submit(int64_t node) {
  const value *dispatch = caml_named_value("lui_flutter_submit");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_dismiss(int64_t node) {
  const value *dispatch = caml_named_value("lui_flutter_dismiss");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_double_press(int64_t node) {
  const value *dispatch = caml_named_value("lui_flutter_double_press");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_toggle_changed(int64_t node, int32_t checked) {
  CAMLparam0();
  CAMLlocal1(result);
  const value *dispatch = caml_named_value("lui_flutter_toggle_changed");
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
  const value *dispatch = caml_named_value("lui_flutter_radio_changed");
  if (dispatch == NULL) {
    return 0;
  }
  return emit_patch(caml_callback_exn(*dispatch, Val_long(node)));
}

LUI_EXPORT int32_t lui_ocaml_slider_changed(int64_t node, double fraction) {
  CAMLparam0();
  CAMLlocal2(value_value, result);
  const value *dispatch = caml_named_value("lui_flutter_slider_changed");
  if (dispatch == NULL) {
    CAMLreturnT(int32_t, 0);
  }
  value_value = caml_copy_double(fraction);
  result = caml_callback2_exn(*dispatch, Val_long(node), value_value);
  int32_t accepted = emit_patch(result);
  CAMLreturnT(int32_t, accepted);
}

LUI_EXPORT int32_t lui_ocaml_stop(void) {
  const value *dispose = caml_named_value("lui_flutter_dispose");
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
  return read_node("lui_flutter_root_node");
}
