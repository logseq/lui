/* OCaml dispatch helpers shared by the native C ABI and the JNI bridge.
 *
 * Every function here assumes the caller already holds the runtime lock
 * (caml_leave_blocking_section on the way in). Local roots are registered
 * only while that lock is held, and dropped before the caller releases it.
 * Values that outlive an allocation live in CAMLlocal / CAMLlocalN slots —
 * a bare C array is not a GC root.
 */

#ifndef LUI_CAML_DISPATCH_H
#define LUI_CAML_DISPATCH_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/printexc.h>

typedef void (*lui_deliver_fn)(const char *json);

/* [json] may be several batches separated by newlines. Each line is one
   JSON object; the wire encoder never emits a raw newline. */
static int lui_deliver_batches(const char *json, lui_deliver_fn deliver) {
  size_t length;
  char *copy;
  char *start;
  char *cursor;
  if (deliver == NULL || json == NULL || json[0] == '\0') {
    return 1;
  }
  length = strlen(json);
  copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return 0;
  }
  memcpy(copy, json, length + 1);
  start = copy;
  for (cursor = copy;; cursor++) {
    if (*cursor == '\n' || *cursor == '\0') {
      char saved = *cursor;
      *cursor = '\0';
      if (cursor > start) {
        deliver(start);
      }
      if (saved == '\0') {
        break;
      }
      start = cursor + 1;
    }
  }
  free(copy);
  return 1;
}

static int lui_emit_value(value result, lui_deliver_fn deliver) {
  if (Is_exception_result(result)) {
    char *message = caml_format_exception(Extract_exception(result));
    fprintf(stderr, "lui bridge: OCaml exception: %s\n", message);
    caml_stat_free(message);
    return 0;
  }
  return lui_deliver_batches(String_val(result), deliver);
}

static int32_t lui_dispatch_unit(const char *name, lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  if (callback != NULL) {
    result = caml_callback_exn(*callback, Val_unit);
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_node(const char *name, int64_t node,
                                 lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  if (callback != NULL) {
    result = caml_callback_exn(*callback, Val_long(node));
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_node_int(const char *name, int64_t node,
                                     int32_t extra, lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  if (callback != NULL) {
    result = caml_callback2_exn(*callback, Val_long(node), Val_long(extra));
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_node_bool(const char *name, int64_t node,
                                      int checked, lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  if (callback != NULL) {
    result =
        caml_callback2_exn(*callback, Val_long(node), Val_bool(checked != 0));
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_node_double(const char *name, int64_t node,
                                        double number, lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal2(number_value, result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  if (callback != NULL) {
    number_value = caml_copy_double(number);
    result = caml_callback2_exn(*callback, Val_long(node), number_value);
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_bytes(const char *name, int64_t node,
                                  const char *bytes, int32_t byte_length,
                                  lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal2(text_value, result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  if (callback != NULL && bytes != NULL && byte_length >= 0) {
    text_value = caml_alloc_initialized_string(byte_length, bytes);
    result = caml_callback2_exn(*callback, Val_long(node), text_value);
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_pointer(const char *name, int64_t node, double x,
                                    double y, int32_t modifiers, int32_t button,
                                    const char *target_class, int32_t class_len,
                                    lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal1(result);
  CAMLlocalN(argv, 6);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  const char *class_bytes = target_class != NULL ? target_class : "";
  if (target_class == NULL || class_len < 0) {
    class_len = 0;
  }
  if (callback != NULL) {
    argv[0] = Val_long(node);
    argv[1] = caml_copy_double(x);
    argv[2] = caml_copy_double(y);
    argv[3] = Val_long(modifiers);
    argv[4] = Val_long(button);
    /* Length-explicit so an embedded NUL is not a truncated class string. */
    argv[5] = caml_alloc_initialized_string(class_len, class_bytes);
    result = caml_callbackN_exn(*callback, 6, argv);
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_extension(const char *name, int64_t node,
                                      const char *identifier, int32_t id_len,
                                      const char *event_name, int32_t name_len,
                                      const char *json_values, int32_t json_len,
                                      lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal4(identifier_value, name_value, values_value, result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  value arguments[4];
  if (callback != NULL && identifier != NULL && event_name != NULL &&
      id_len >= 0 && name_len >= 0 && json_len >= 0) {
    identifier_value = caml_alloc_initialized_string(id_len, identifier);
    name_value = caml_alloc_initialized_string(name_len, event_name);
    values_value = caml_alloc_initialized_string(
        json_len, json_values != NULL ? json_values : "");
    arguments[0] = Val_long(node);
    arguments[1] = identifier_value;
    arguments[2] = name_value;
    arguments[3] = values_value;
    result = caml_callbackN_exn(*callback, 4, arguments);
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_visible_range(const char *name, int64_t node,
                                          int64_t first, int64_t last,
                                          lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  value arguments[3];
  if (callback != NULL) {
    arguments[0] = Val_long(node);
    arguments[1] = Val_long(first);
    arguments[2] = Val_long(last);
    result = caml_callbackN_exn(*callback, 3, arguments);
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_scroll_completed(const char *name, int64_t node,
                                             int64_t token, const char *outcome,
                                             int32_t outcome_len,
                                             lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal2(outcome_value, result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  value arguments[3];
  if (callback != NULL && outcome != NULL && outcome_len >= 0) {
    outcome_value = caml_alloc_initialized_string(outcome_len, outcome);
    arguments[0] = Val_long(node);
    arguments[1] = Val_long(token);
    arguments[2] = outcome_value;
    result = caml_callbackN_exn(*callback, 3, arguments);
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int32_t lui_dispatch_init(const char *name, int32_t platform_code,
                                 int32_t host_code, lui_deliver_fn deliver) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *callback = caml_named_value(name);
  if (callback != NULL) {
    result = caml_callback2_exn(*callback, Val_long(platform_code),
                                Val_long(host_code));
    accepted = lui_emit_value(result, deliver);
  }
  CAMLreturnT(int32_t, accepted);
}

static int64_t lui_dispatch_root(const char *name) {
  CAMLparam0();
  CAMLlocal1(result);
  int64_t node = -1;
  const value *callback = caml_named_value(name);
  if (callback != NULL) {
    result = caml_callback_exn(*callback, Val_unit);
    if (!Is_exception_result(result)) {
      node = Long_val(result);
    }
  }
  CAMLreturnT(int64_t, node);
}

#endif
