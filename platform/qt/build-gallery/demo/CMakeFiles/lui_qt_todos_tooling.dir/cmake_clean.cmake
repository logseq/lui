file(REMOVE_RECURSE
  "LuiDemo/main.qml"
)

# Per-language clean rules from dependency scanning.
foreach(lang )
  include(CMakeFiles/lui_qt_todos_tooling.dir/cmake_clean_${lang}.cmake OPTIONAL)
endforeach()
