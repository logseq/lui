cmake_minimum_required(VERSION 3.21)
project(lui_qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Test
)

add_subdirectory(lib)

enable_testing()
add_subdirectory(test)

option(LUI_QT_BUILD_DEMO "Build the Qt/QML demo app" ON)
if(LUI_QT_BUILD_DEMO)
    add_subdirectory(demo)
endif()
