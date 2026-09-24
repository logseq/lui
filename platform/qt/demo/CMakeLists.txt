# The demo links the merged OCaml runtime object produced by
# build-runtime.sh (lui_todos_runtime.o next to this file). The object is
# not PIC-safe, so it goes into the executable itself rather than a library.
set(LUI_RUNTIME_OBJ
    ${CMAKE_CURRENT_SOURCE_DIR}/lui_todos_runtime.o
    CACHE FILEPATH "Merged OCaml LUI runtime object for the demo")

if(NOT EXISTS ${LUI_RUNTIME_OBJ})
    message(WARNING
        "lui_todos_runtime.o not found — run demo/build-runtime.sh first; "
        "skipping lui_qt_todos target")
    return()
endif()

execute_process(
    COMMAND ocamlfind ocamlc -where
    OUTPUT_VARIABLE OCAML_STDLIB_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE OCAMLFIND_RESULT)
if(NOT OCAMLFIND_RESULT EQUAL 0)
    message(WARNING "ocamlfind not found — needed to link the OCaml runtime")
    return()
endif()

qt_add_executable(lui_qt_todos main.cpp)
qt_add_qml_module(lui_qt_todos
    URI LuiDemo
    RESOURCE_PREFIX /qt/qml
    VERSION 1.0
    QML_FILES main.qml
)

target_link_libraries(lui_qt_todos PRIVATE
    ${LUI_RUNTIME_OBJ}
    ${OCAML_STDLIB_DIR}/libasmrun.a
    ${OCAML_STDLIB_DIR}/libunixnat.a
    lui_qml
    lui_qmlplugin
    Qt6::Quick
    Qt6::QuickControls2
    dl
    m
    pthread
)

qt_import_qml_plugins(lui_qt_todos)
