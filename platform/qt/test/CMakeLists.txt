qt_add_executable(tst_lui_qml_backend
    tst_backend.cpp
)

target_link_libraries(tst_lui_qml_backend PRIVATE
    lui_qml
    Qt6::Test
    Qt6::Qml
)

add_test(NAME tst_lui_qml_backend COMMAND tst_lui_qml_backend)
