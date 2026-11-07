/* Stub exports for builds without the lg Android OCaml toolchain: every
 * dev.lui.LuiBridge JNI entry resolves but returns "not accepted", so the
 * gallery app still compiles and launches while showing its
 * runtime-unavailable placeholder. The real implementation is
 * platform/android/lui/src/main/cpp/lui_jni_bridge.c. */

#include <jni.h>

#define LUI_JNI_NAME(name) Java_dev_lui_LuiBridge_##name

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeStart)(
    JNIEnv *env, jclass clazz, jint platform_code, jint host_code) {
  (void)env; (void)clazz; (void)platform_code; (void)host_code;
  return 0;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeThreadRegister)(JNIEnv *env, jclass clazz) {
  (void)env; (void)clazz;
  return 0;
}

#define LUI_STUB_NODE(name)                                                 \
  JNIEXPORT jint JNICALL LUI_JNI_NAME(name)(JNIEnv *env, jclass clazz,      \
                                            jlong node) {                  \
    (void)env; (void)clazz; (void)node;                                    \
    return 0;                                                              \
  }

LUI_STUB_NODE(nativeAppear)
LUI_STUB_NODE(nativePress)
LUI_STUB_NODE(nativeLongPress)
LUI_STUB_NODE(nativeSubmit)
LUI_STUB_NODE(nativeDismiss)
LUI_STUB_NODE(nativeDoublePress)
LUI_STUB_NODE(nativeRadioChanged)
LUI_STUB_NODE(nativePointerEnter)
LUI_STUB_NODE(nativePointerLeave)

#define LUI_STUB_NODE_STRING(name)                                          \
  JNIEXPORT jint JNICALL LUI_JNI_NAME(name)(JNIEnv *env, jclass clazz,      \
                                            jlong node, jstring text) {    \
    (void)env; (void)clazz; (void)node; (void)text;                        \
    return 0;                                                              \
  }

LUI_STUB_NODE_STRING(nativeTextChanged)
LUI_STUB_NODE_STRING(nativePicked)

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeToggleChanged)(
    JNIEnv *env, jclass clazz, jlong node, jint checked) {
  (void)env; (void)clazz; (void)node; (void)checked;
  return 0;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeSliderChanged)(
    JNIEnv *env, jclass clazz, jlong node, jdouble fraction) {
  (void)env; (void)clazz; (void)node; (void)fraction;
  return 0;
}

#define LUI_STUB_POINTER(name)                                              \
  JNIEXPORT jint JNICALL LUI_JNI_NAME(name)(                                \
      JNIEnv *env, jclass clazz, jlong node, jdouble x, jdouble y,         \
      jint modifiers, jint button, jstring target_class) {                 \
    (void)env; (void)clazz; (void)node; (void)x; (void)y;                  \
    (void)modifiers; (void)button; (void)target_class;                     \
    return 0;                                                              \
  }

LUI_STUB_POINTER(nativePressDetail)
LUI_STUB_POINTER(nativePointerDown)
LUI_STUB_POINTER(nativePointerUp)
LUI_STUB_POINTER(nativeContextMenuPress)

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeExtensionEvent)(
    JNIEnv *env, jclass clazz, jlong node, jstring identifier,
    jstring name, jstring json_values) {
  (void)env; (void)clazz; (void)node;
  (void)identifier; (void)name; (void)json_values;
  return 0;
}

JNIEXPORT jint JNICALL LUI_JNI_NAME(nativeStop)(JNIEnv *env, jclass clazz) {
  (void)env; (void)clazz;
  return 0;
}

JNIEXPORT jlong JNICALL LUI_JNI_NAME(nativeRootNode)(JNIEnv *env, jclass clazz) {
  (void)env; (void)clazz;
  return -1;
}
