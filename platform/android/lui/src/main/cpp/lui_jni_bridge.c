/* JNI bridge between the Kotlin backend and the OCaml LUI runtime.
 *
 * Shares dispatch helpers with platform/native/lui_ocaml_bridge.c
 * (lui_caml_dispatch.h). Named values use the "lui_kotlin_" prefix.
 *
 * Lock discipline: after nativeStart the host thread does NOT hold the
 * OCaml runtime lock between calls. Every export re-acquires it with
 * caml_leave_blocking_section() before any CAMLparam/CAMLlocal/caml_named_value
 * use, and releases it with caml_enter_blocking_section() only after
 * CAMLreturn has dropped those roots. JNI string traffic is UTF-8 byte
 * arrays copied on the JVM side of the lock — never Modified UTF-8.
 *
 * Callers must be OCaml-registered threads (the thread that ran
 * nativeStart, or one registered via nativeThreadRegister). The patch
 * callback runs while the lock is held and must not re-enter these exports.
 */

#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <caml/callback.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <caml/startup.h>

#include "../../../../../native/lui_caml_dispatch.h"

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
  lui_dispatch_patch =
      (*env)->GetStaticMethodID(env, bridge, "dispatchPatch", "([B)V");
  if (lui_dispatch_patch == NULL) {
    return JNI_ERR;
  }
  return JNI_VERSION_1_6;
}

/* Invoked by OCaml while the runtime lock is held. Copy the JSON out as
 * raw UTF-8 bytes and enqueue it; never call back into the exports. */
static void dispatch_patch_to_jvm(const char *json) {
  JNIEnv *env = NULL;
  int attached = 0;
  jbyteArray value;
  jsize length;
  if (lui_jvm == NULL || lui_dispatch_patch == NULL || json == NULL) {
    return;
  }
  if ((*lui_jvm)->GetEnv(lui_jvm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    if ((*lui_jvm)->AttachCurrentThread(lui_jvm, &env, NULL) != JNI_OK) {
      return;
    }
    attached = 1;
  }
  length = (jsize)strlen(json);
  value = (*env)->NewByteArray(env, length);
  if (value != NULL) {
    jclass bridge;
    (*env)->SetByteArrayRegion(env, value, 0, length, (const jbyte *)json);
    bridge = (*env)->FindClass(env, "dev/lui/LuiBridge");
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

/* Copy a Java byte[] to a NUL-terminated C buffer before the runtime lock
 * is taken. The caller frees the result. */
static char *copy_jbytes(JNIEnv *env, jbyteArray array, int32_t *out_len) {
  jsize length;
  jbyte *raw;
  char *copy;
  if (array == NULL) {
    return NULL;
  }
  length = (*env)->GetArrayLength(env, array);
  if (length < 0) {
    return NULL;
  }
  raw = (*env)->GetByteArrayElements(env, array, NULL);
  if (raw == NULL) {
    return NULL;
  }
  copy = (char *)malloc((size_t)length + 1);
  if (copy == NULL) {
    (*env)->ReleaseByteArrayElements(env, array, raw, JNI_ABORT);
    return NULL;
  }
  memcpy(copy, raw, (size_t)length);
  copy[length] = '\0';
  *out_len = (int32_t)length;
  (*env)->ReleaseByteArrayElements(env, array, raw, JNI_ABORT);
  return copy;
}

static int32_t dispatch_node(const char *name, int64_t node) {
  int32_t accepted;
  caml_leave_blocking_section();
  accepted = lui_dispatch_node(name, node, dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  return accepted;
}

static int32_t dispatch_bytes(const char *name, JNIEnv *env, int64_t node,
                              jbyteArray text) {
  int32_t accepted = 0;
  int32_t length = 0;
  char *bytes = copy_jbytes(env, text, &length);
  if (text != NULL && bytes == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = lui_dispatch_bytes(name, node, bytes != NULL ? bytes : "",
                                bytes != NULL ? length : 0,
                                dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  free(bytes);
  return accepted;
}

static int32_t dispatch_pointer(const char *name, JNIEnv *env, int64_t node,
                                jdouble x, jdouble y, jint modifiers,
                                jint button, jbyteArray target_class) {
  int32_t accepted;
  int32_t class_len = 0;
  char *class_bytes = copy_jbytes(env, target_class, &class_len);
  if (target_class != NULL && class_bytes == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = lui_dispatch_pointer(
      name, node, x, y, modifiers, button,
      class_bytes != NULL ? class_bytes : "",
      class_bytes != NULL ? class_len : 0, dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  free(class_bytes);
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeStart)(JNIEnv *env, jclass clazz,
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
  accepted = lui_dispatch_init("lui_kotlin_init", platform_code, host_code,
                               dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeThreadRegister)(JNIEnv *env,
                                                          jclass clazz) {
  (void)env;
  (void)clazz;
  return caml_c_thread_register() == 1 ? 1 : 0;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeAppear)(JNIEnv *env, jclass clazz,
                                                  jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_appear", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePress)(JNIEnv *env, jclass clazz,
                                                 jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_press", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePressEx)(JNIEnv *env, jclass clazz,
                                                   jlong node,
                                                   jint modifiers) {
  int32_t accepted;
  const value *callback;
  (void)env;
  (void)clazz;
  caml_leave_blocking_section();
  callback = caml_named_value("lui_kotlin_press_ex");
  if (callback == NULL) {
    accepted = lui_dispatch_node("lui_kotlin_press", node, dispatch_patch_to_jvm);
  } else {
    accepted = lui_dispatch_node_int("lui_kotlin_press_ex", node, modifiers,
                                     dispatch_patch_to_jvm);
  }
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeLongPress)(JNIEnv *env, jclass clazz,
                                                     jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_long_press", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeTextChanged)(JNIEnv *env, jclass clazz,
                                                       jlong node,
                                                       jbyteArray text) {
  (void)clazz;
  return dispatch_bytes("lui_kotlin_text_changed", env, node, text);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeSubmit)(JNIEnv *env, jclass clazz,
                                                  jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_submit", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeDismiss)(JNIEnv *env, jclass clazz,
                                                   jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_dismiss", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePicked)(JNIEnv *env, jclass clazz,
                                                  jlong node,
                                                  jbyteArray payload) {
  (void)clazz;
  return dispatch_bytes("lui_kotlin_picked", env, node, payload);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeDoublePress)(JNIEnv *env, jclass clazz,
                                                       jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_double_press", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeToggleChanged)(JNIEnv *env,
                                                         jclass clazz,
                                                         jlong node,
                                                         jint checked) {
  int32_t accepted;
  (void)env;
  (void)clazz;
  caml_leave_blocking_section();
  accepted = lui_dispatch_node_bool("lui_kotlin_toggle_changed", node, checked,
                                    dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeRadioChanged)(JNIEnv *env,
                                                        jclass clazz,
                                                        jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_radio_changed", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeSliderChanged)(JNIEnv *env,
                                                         jclass clazz,
                                                         jlong node,
                                                         jdouble fraction) {
  int32_t accepted;
  (void)env;
  (void)clazz;
  caml_leave_blocking_section();
  accepted = lui_dispatch_node_double("lui_kotlin_slider_changed", node,
                                      fraction, dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePressDetail)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jbyteArray target_class) {
  (void)clazz;
  return dispatch_pointer("lui_kotlin_press_detail", env, node, x, y,
                          modifiers, button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerDown)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jbyteArray target_class) {
  (void)clazz;
  return dispatch_pointer("lui_kotlin_pointer_down", env, node, x, y,
                          modifiers, button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerUp)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jbyteArray target_class) {
  (void)clazz;
  return dispatch_pointer("lui_kotlin_pointer_up", env, node, x, y, modifiers,
                          button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerEnter)(JNIEnv *env,
                                                        jclass clazz,
                                                        jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_pointer_enter", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativePointerLeave)(JNIEnv *env,
                                                        jclass clazz,
                                                        jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_pointer_leave", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeContextMenuPress)(
    JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,
    jint modifiers, jint button, jbyteArray target_class) {
  (void)clazz;
  return dispatch_pointer("lui_kotlin_context_menu_press", env, node, x, y,
                          modifiers, button, target_class);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeExtensionEvent)(
    JNIEnv *env, jclass clazz, jlong node, jbyteArray identifier,
    jbyteArray name, jbyteArray json_values) {
  int32_t accepted = 0;
  int32_t id_len = 0;
  int32_t name_len = 0;
  int32_t json_len = 0;
  char *id_bytes;
  char *name_bytes;
  char *json_bytes;
  (void)clazz;
  id_bytes = copy_jbytes(env, identifier, &id_len);
  name_bytes = copy_jbytes(env, name, &name_len);
  json_bytes = copy_jbytes(env, json_values, &json_len);
  if (identifier == NULL || name == NULL || id_bytes == NULL ||
      name_bytes == NULL || (json_values != NULL && json_bytes == NULL)) {
    free(id_bytes);
    free(name_bytes);
    free(json_bytes);
    return 0;
  }
  caml_leave_blocking_section();
  accepted = lui_dispatch_extension(
      "lui_kotlin_extension_event", node, id_bytes, id_len, name_bytes,
      name_len, json_bytes != NULL ? json_bytes : "",
      json_bytes != NULL ? json_len : 0, dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  free(id_bytes);
  free(name_bytes);
  free(json_bytes);
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeVisibleRange)(
    JNIEnv *env, jclass clazz, jlong node, jlong first, jlong last) {
  int32_t accepted;
  (void)env;
  (void)clazz;
  caml_leave_blocking_section();
  accepted = lui_dispatch_visible_range("lui_kotlin_visible_range", node, first,
                                        last, dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeScrollCompleted)(
    JNIEnv *env, jclass clazz, jlong node, jlong token, jbyteArray outcome) {
  int32_t accepted = 0;
  int32_t length = 0;
  char *bytes;
  (void)clazz;
  bytes = copy_jbytes(env, outcome, &length);
  if (outcome != NULL && bytes == NULL) {
    return 0;
  }
  caml_leave_blocking_section();
  accepted = lui_dispatch_scroll_completed(
      "lui_kotlin_scroll_completed", node, token, bytes != NULL ? bytes : "",
      bytes != NULL ? length : 0, dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  free(bytes);
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeLoad)(JNIEnv *env, jclass clazz,
                                                jlong node) {
  (void)env;
  (void)clazz;
  return dispatch_node("lui_kotlin_load", node);
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeStop)(JNIEnv *env, jclass clazz) {
  int32_t accepted;
  (void)env;
  (void)clazz;
  caml_leave_blocking_section();
  accepted = lui_dispatch_unit("lui_kotlin_dispose", dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeResync)(JNIEnv *env, jclass clazz) {
  int32_t accepted;
  (void)env;
  (void)clazz;
  caml_leave_blocking_section();
  accepted = lui_dispatch_unit("lui_kotlin_resync", dispatch_patch_to_jvm);
  caml_enter_blocking_section();
  return accepted;
}

JNIEXPORT jlong JNICALL LUI_JNI_NAME(nativeRootNode)(JNIEnv *env,
                                                     jclass clazz) {
  int64_t node;
  (void)env;
  (void)clazz;
  caml_leave_blocking_section();
  node = lui_dispatch_root("lui_kotlin_root_node");
  caml_enter_blocking_section();
  return node;
}
