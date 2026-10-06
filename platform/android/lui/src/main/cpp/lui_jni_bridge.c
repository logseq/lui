/* JNI bridge between the Kotlin backend and the OCaml LUI runtime.
 *
 * Ported from platform/flutter/native/lui_ocaml_bridge.c. Each exported
 * Java method corresponds to one OCaml-side dispatch entry; the named
 * values use the "lui_kotlin_" prefix, which the app registers alongside
 * the other host prefixes (see examples/components/native/components_bridge.ml).
 *
 * Lock discipline (same contract as the Flutter bridge): after start() the
 * host thread does NOT hold the OCaml runtime lock between calls, so OCaml
 * worker domains keep running (stop-the-world GC included) while the host
 * sits in its event loop. Every export re-acquires the lock with
 * caml_leave_blocking_section() on the way in and releases it with
 * caml_enter_blocking_section() on the way out — including start, whose
 * caml_startup leaves the lock held.
 *
 * Callers must be OCaml-registered threads: the thread that ran
 * nativeStart, or one registered via caml_c_thread_register (exposed here
 * as nativeThreadRegister). LuiBridge routes every call through its
 * dedicated LuiThread to satisfy this.
 *
 * The patch callback runs while the OCaml domain lock is held. It copies
 * the JSON into a Java string and hands it to LuiBridge.dispatchPatch,
 * which enqueues to the UI thread — it must not call back into OCaml
 * exports from inside the callback.
 */

#include <jni.h>
#include <stdint.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <caml/startup.h>

static JavaVM *lui_jvm = NULL;
static jmethodID lui_dispatch_patch = NULL;
static int runtime_started = 0;

#define LUI_JNI_NAME(name) Java_dev_lui_LuiBridge_##name

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
  (void)reserved;
  JNIEnv *env = NULL;
  lui_jvm = vm;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    return JNI_ERR;
  }
  jclass bridge = (*env)->FindClass(env, "dev/lui/LuiBridge");
  if (bridge == NULL) {
    return JNI_ERR;
  }
  lui_dispatch_patch = (*env)->GetStaticMethodID(
      env, bridge, "dispatchPatch", "(Ljava/lang/String;)V");
  if (lui_dispatch_patch == NULL) {
    return JNI_ERR;
  }
  return JNI_VERSION_1_6;
}

/* Invoked by OCaml while the runtime lock is held. Copy the JSON out and
 * enqueue it; never call back into the exports below from here. */
static void dispatch_patch_to_jvm(const char *json) {
  JNIEnv *env = NULL;
  int attached = 0;
  jstring value;
  if (lui_jvm == NULL || lui_dispatch_patch == NULL || json == NULL) {
    return;
  }
  if ((*lui_jvm)->GetEnv(lui_jvm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    if ((*lui_jvm)->AttachCurrentThread(lui_jvm, &env, NULL) != JNI_OK) {
      return;
    }
    attached = 1;
  }
  value = (*env)->NewStringUTF(env, json);
  if (value != NULL) {
    jclass bridge =
        (*env)->FindClass(env, "dev/lui/LuiBridge");
    if (bridge != NULL) {
      (*env)->CallStaticVoidMethod(env, bridge, lui_dispatch_patch, value);
      if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
      }
    }
    (*env)->DeleteLocalRef(env, value);
  }
  if (attached) {
    (*lui_jvm)->DetachCurrentThread(lui_jvm);
  }
}

static int emit_patch(value result) {
  if (Is_exception_result(result)) {
    return 0;
  }
  const char *json = String_val(result);
  if (json[0] != '\0') {
    dispatch_patch_to_jvm(json);
  }
  return 1;
}

/* Dispatches a zero-argument named callback under the lock. */
static int dispatch_unit(const char *callback_name, int64_t node) {
  const value *callback = caml_named_value(callback_name);
  int accepted = 0;
  if (callback == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*callback, Val_long(node)));
  caml_enter_blocking_section();
  return accepted;
}

/* Dispatches a (node, string) named callback under the lock. The string is
 * passed as an explicit byte length so embedded NULs survive. */
static int dispatch_string(
    const char *callback_name,
    JNIEnv *env,
    int64_t node,
    jstring text) {
  CAMLparam0();
  CAMLlocal2(text_value, result);
  int accepted = 0;
  const value *callback = caml_named_value(callback_name);
  const char *bytes;
  jsize length;
  if (callback == NULL || text == NULL) {
    CAMLreturnT(int, 0);
  }
  bytes = (*env)->GetStringUTFChars(env, text, NULL);
  if (bytes == NULL) {
    CAMLreturnT(int, 0);
  }
  length = (*env)->GetStringUTFLength(env, text);
  caml_leave_blocking_section();
  text_value = caml_alloc_initialized_string((intnat)length, bytes);
  (*env)->ReleaseStringUTFChars(env, text, bytes);
  result = caml_callback2_exn(*callback, Val_long(node), text_value);
  accepted = emit_patch(result);
  caml_enter_blocking_section();
  CAMLreturnT(int, accepted);
}

/* Dispatches a pointer event under the lock. The OCaml callback receives
 * (node, x, y, modifiers, button, target_class) — six arguments, matching
 * the registered lui_kotlin_* entry points in components_bridge.ml. */
static int dispatch_pointer(
    const char *callback_name,
    JNIEnv *env,
    int64_t node,
    jdouble x,
    jdouble y,
    jint modifiers,
    jint button,
    jstring target_class) {
  CAMLparam0();
  CAMLlocal4(x_value, y_value, class_value, result);
  int accepted = 0;
  const value *callback = caml_named_value(callback_name);
  const char *class_bytes;
  value arguments[6];
  if (callback == NULL) {
    CAMLreturnT(int, 0);
  }
  class_bytes =
      target_class == NULL ? NULL : (*env)->GetStringUTFChars(env, target_class, NULL);
  caml_leave_blocking_section();
  x_value = caml_copy_double(x);
  y_value = caml_copy_double(y);
  class_value = caml_copy_string(class_bytes == NULL ? "" : class_bytes);
  if (class_bytes != NULL) {
    (*env)->ReleaseStringUTFChars(env, target_class, class_bytes);
  }
  arguments[0] = Val_long(node);
  arguments[1] = x_value;
  arguments[2] = y_value;
  arguments[3] = Val_long(modifiers);
  arguments[4] = Val_long(button);
  arguments[5] = class_value;
  result = caml_callbackN_exn(*callback, 6, arguments);
  accepted = emit_patch(result);
  caml_enter_blocking_section();
  CAMLreturnT(int, accepted);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeStart)(
    JNIEnv *env,
    jclass clazz,
    jint platform_code,
    jint host_code) {
  int32_t accepted = 0;
  (void)env;
  (void)clazz;
  if (!runtime_started) {
    char *arguments[] = {"lui_kotlin", NULL};
    caml_startup(arguments);
    runtime_started = 1;
  } else {
    caml_leave_blocking_section();
  }

  const value *initialize = caml_named_value("lui_kotlin_init");
  if (initialize != NULL) {
    accepted = emit_patch(caml_callback2_exn(
        *initialize,
        Val_long(platform_code),
        Val_long(host_code)));
  }
  caml_enter_blocking_section();
  return accepted;
}

/* Registers the calling thread with the OCaml runtime so it can invoke the
 * exports below. The caller must have previously released the runtime lock
 * (any thread other than the one that ran nativeStart is fine). */
JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeThreadRegister)(
    JNIEnv *env,
    jclass clazz) {
  (void)env;
  (void)clazz;
  return caml_c_thread_register() == 1 ? 1 : 0;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeAppear)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_appear", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePress)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_press", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeLongPress)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_long_press", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeTextChanged)(
    JNIEnv *env, jclass clazz, jlong node, jstring text) {
  (void)clazz;
  return dispatch_string("lui_kotlin_text_changed", env, node, text);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeSubmit)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_submit", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeDismiss)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_dismiss", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePicked)(
    JNIEnv *env, jclass clazz, jlong node, jstring payload) {
  (void)clazz;
  return dispatch_string("lui_kotlin_picked", env, node, payload);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeDoublePress)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_double_press", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeToggleChanged)(
    JNIEnv *env, jclass clazz, jlong node, jint checked) {
  CAMLparam0();
  CAMLlocal1(result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_kotlin_toggle_changed");
  (void)env; (void)clazz;
  if (dispatch == NULL) {
    CAMLreturnT(jint, 0);
  }
  caml_leave_blocking_section();
  result = caml_callback2_exn(
      *dispatch, Val_long(node), Val_bool(checked != 0));
  accepted = emit_patch(result);
  caml_enter_blocking_section();
  CAMLreturnT(jint, accepted);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeRadioChanged)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_radio_changed", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeSliderChanged)(
    JNIEnv *env, jclass clazz, jlong node, jdouble fraction) {
  CAMLparam0();
  CAMLlocal2(value_value, result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_kotlin_slider_changed");
  (void)env; (void)clazz;
  if (dispatch == NULL) {
    CAMLreturnT(jint, 0);
  }
  caml_leave_blocking_section();
  value_value = caml_copy_double(fraction);
  result = caml_callback2_exn(*dispatch, Val_long(node), value_value);
  accepted = emit_patch(result);
  caml_enter_blocking_section();
  CAMLreturnT(jint, accepted);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePressDetail)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jstring target_class) {
  (void)clazz;
  return dispatch_pointer(
      "lui_kotlin_press_detail", env, node, x, y, modifiers, button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerDown)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jstring target_class) {
  (void)clazz;
  return dispatch_pointer(
      "lui_kotlin_pointer_down", env, node, x, y, modifiers, button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerUp)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jstring target_class) {
  (void)clazz;
  return dispatch_pointer(
      "lui_kotlin_pointer_up", env, node, x, y, modifiers, button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerEnter)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_pointer_enter", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerLeave)(
    JNIEnv *env, jclass clazz, jlong node) {
  (void)env; (void)clazz;
  return dispatch_unit("lui_kotlin_pointer_leave", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeContextMenuPress)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jstring target_class) {
  (void)clazz;
  return dispatch_pointer(
      "lui_kotlin_context_menu_press", env, node, x, y, modifiers, button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeExtensionEvent)(
    JNIEnv *env,
    jclass clazz,
    jlong node,
    jstring identifier,
    jstring name,
    jstring json_values) {
  CAMLparam0();
  CAMLlocal4(identifier_value, name_value, values_value, result);
  int32_t accepted = 0;
  const value *dispatch = caml_named_value("lui_kotlin_extension_event");
  const char *identifier_bytes;
  const char *name_bytes;
  const char *values_bytes;
  value arguments[4];
  (void)clazz;
  if (dispatch == NULL || identifier == NULL || name == NULL) {
    CAMLreturnT(jint, 0);
  }
  identifier_bytes = (*env)->GetStringUTFChars(env, identifier, NULL);
  name_bytes = (*env)->GetStringUTFChars(env, name, NULL);
  values_bytes =
      json_values == NULL ? NULL : (*env)->GetStringUTFChars(env, json_values, NULL);
  if (identifier_bytes == NULL || name_bytes == NULL) {
    if (identifier_bytes != NULL) {
      (*env)->ReleaseStringUTFChars(env, identifier, identifier_bytes);
    }
    if (name_bytes != NULL) {
      (*env)->ReleaseStringUTFChars(env, name, name_bytes);
    }
    if (values_bytes != NULL) {
      (*env)->ReleaseStringUTFChars(env, json_values, values_bytes);
    }
    CAMLreturnT(jint, 0);
  }
  caml_leave_blocking_section();
  identifier_value = caml_copy_string(identifier_bytes);
  name_value = caml_copy_string(name_bytes);
  values_value = caml_copy_string(values_bytes == NULL ? "" : values_bytes);
  (*env)->ReleaseStringUTFChars(env, identifier, identifier_bytes);
  (*env)->ReleaseStringUTFChars(env, name, name_bytes);
  if (values_bytes != NULL) {
    (*env)->ReleaseStringUTFChars(env, json_values, values_bytes);
  }
  arguments[0] = Val_long(node);
  arguments[1] = identifier_value;
  arguments[2] = name_value;
  arguments[3] = values_value;
  result = caml_callbackN_exn(*dispatch, 4, arguments);
  accepted = emit_patch(result);
  caml_enter_blocking_section();
  CAMLreturnT(jint, accepted);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeStop)(JNIEnv *env, jclass clazz) {
  const value *dispose = caml_named_value("lui_kotlin_dispose");
  int32_t accepted = 0;
  (void)env; (void)clazz;
  if (dispose == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = emit_patch(caml_callback_exn(*dispose, Val_unit));
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jlong JNICALL LUI_JNI_NAME(nativeRootNode)(JNIEnv *env, jclass clazz) {
  const value *callback = caml_named_value("lui_kotlin_root_node");
  value result;
  int64_t node;
  (void)env; (void)clazz;
  if (callback == NULL) {
    return -1;
  }
  caml_leave_blocking_section();
  result = caml_callback_exn(*callback, Val_unit);
  node = Is_exception_result(result) ? -1 : Long_val(result);
  caml_enter_blocking_section();
  return node;
}
