cmake_minimum_required(VERSION 3.22.1)
project(lui_components_bridge C)

# Compiles the JNI bridge into liblui_jni_bridge.so and links it against
# the OCaml runtime packaged by tooling/mobile/build_components_android.sh
# as jniLibs/<abi>/liblui_components.so.
#
# LUI_OCAML_INCLUDE must point at the OCaml headers (<prefix>/lib/ocaml)
# from the lg Android toolchain, and the liblui_components.so for this ABI
# must already exist under jniLibs. When either is missing we compile the
# stub exports instead so the app still builds and launches (the bridge
# reports "not accepted" and the gallery shows a placeholder).

set(LUI_BACKEND_DIR "${CMAKE_SOURCE_DIR}/../../../../../../platform/android/lui")
set(LUI_COMPONENTS_SO "${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/liblui_components.so")

find_library(log_lib log)

if(LUI_OCAML_INCLUDE AND EXISTS "${LUI_COMPONENTS_SO}")
    add_library(lui_jni_bridge SHARED
        "${LUI_BACKEND_DIR}/src/main/cpp/lui_jni_bridge.c")
    target_include_directories(lui_jni_bridge PRIVATE "${LUI_OCAML_INCLUDE}")

    add_library(lui_components SHARED IMPORTED)
    set_target_properties(lui_components PROPERTIES
        IMPORTED_LOCATION "${LUI_COMPONENTS_SO}")
    target_link_libraries(lui_jni_bridge lui_components ${log_lib})
else()
    message(WARNING
        "OCaml toolchain or liblui_components.so missing for ${ANDROID_ABI}; "
        "building stub LuiBridge exports")
    add_library(lui_jni_bridge SHARED
        "${CMAKE_SOURCE_DIR}/lui_jni_bridge_stub.c")
    target_link_libraries(lui_jni_bridge ${log_lib})
endif()
