# The lui_qml module carries the C++ retained tree (LuiQmlBackend + LuiNode)
# and the Lui QML components. QML files resolve each other relatively inside
# qt:/Lui/, and icons land at qt:/Lui/icons/<name>.svg.
file(GLOB LUI_QML_ICONS CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/../qml/icons/*.svg)
foreach(icon ${LUI_QML_ICONS})
    get_filename_component(icon_name ${icon} NAME)
    set_source_files_properties(${icon} PROPERTIES
        QT_RESOURCE_ALIAS "icons/${icon_name}")
endforeach()

# Force basename resource aliases: the sources live outside the build
# tree, so CMake would otherwise keep the ../qml/ prefix in the resource
# path and the module's qmldir would point at nonexistent locations.
file(GLOB LUI_QML_FILES CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/../qml/*.qml
    ${CMAKE_CURRENT_SOURCE_DIR}/../qml/*.js)
foreach(qml_file ${LUI_QML_FILES})
    get_filename_component(qml_name ${qml_file} NAME)
    set_source_files_properties(${qml_file} PROPERTIES
        QT_RESOURCE_ALIAS "${qml_name}")
endforeach()

qt_add_qml_module(lui_qml
    URI Lui
    RESOURCE_PREFIX /qt/qml
    VERSION 1.0
    STATIC
    SOURCES
        lui_node.h
        lui_node.cpp
        lui_schema.h
        lui_schema.cpp
        lui_wire_schema.h
        lui_extension_registry.h
        lui_extension_registry.cpp
        lui_qml_backend.h
        lui_qml_backend.cpp
    QML_FILES
        ../qml/LuiAccordion.qml
        ../qml/LuiAlert.qml
        ../qml/LuiAvatar.qml
        ../qml/LuiBottomTab.qml
        ../qml/LuiBottomTabs.qml
        ../qml/LuiBox.qml
        ../qml/LuiBreadcrumb.qml
        ../qml/LuiBubble.qml
        ../qml/LuiButton.qml
        ../qml/LuiButtonGroup.qml
        ../qml/LuiCard.qml
        ../qml/LuiCheckbox.qml
        ../qml/LuiColumn.qml
        ../qml/LuiCombobox.qml
        ../qml/LuiContextMenu.qml
        ../qml/LuiDialog.qml
        ../qml/LuiDivider.qml
        ../qml/LuiDrawer.qml
        ../qml/LuiDropdownMenu.qml
        ../qml/LuiGrid.qml
        ../qml/LuiHeading.qml
        ../qml/LuiIcon.qml
        ../qml/LuiImage.qml
        ../qml/LuiInput.qml
        ../qml/LuiInputGroup.qml
        ../qml/LuiInputGroupActions.qml
        ../qml/LuiLabel.qml
        ../qml/LuiList.qml
        ../qml/LuiListItem.qml
        ../qml/LuiMediaSurface.qml
        ../qml/LuiMenuItem.qml
        ../qml/LuiNodeView.qml
        ../qml/LuiPagination.qml
        ../qml/LuiPanel.qml
        ../qml/LuiParagraph.qml
        ../qml/LuiProgress.qml
        ../qml/LuiRadio.qml
        ../qml/LuiRadioGroup.qml
        ../qml/LuiResizable.qml
        ../qml/LuiRoot.qml
        ../qml/LuiRow.qml
        ../qml/LuiScroll.qml
        ../qml/LuiSearchField.qml
        ../qml/LuiSecureField.qml
        ../qml/LuiSelect.qml
        ../qml/LuiSheet.qml
        ../qml/LuiSlider.qml
        ../qml/LuiSpacer.qml
        ../qml/LuiSpinner.qml
        ../qml/LuiSplit.qml
        ../qml/LuiStack.qml
        ../qml/LuiStatusBar.qml
        ../qml/LuiStep.qml
        ../qml/LuiStepper.qml
        ../qml/LuiSwitch.qml
        ../qml/LuiTable.qml
        ../qml/LuiTableCell.qml
        ../qml/LuiTableRow.qml
        ../qml/LuiTabs.qml
        ../qml/LuiText.qml
        ../qml/LuiTextField.qml
        ../qml/LuiTextarea.qml
        ../qml/LuiTimeline.qml
        ../qml/LuiTimelineItem.qml
        ../qml/LuiToast.qml
        ../qml/LuiToggle.qml
        ../qml/LuiToggleButton.qml
        ../qml/LuiToggleGroup.qml
        ../qml/LuiToolbar.qml
        ../qml/LuiTooltip.qml
        ../qml/LuiTree.qml
        ../qml/LuiVirtualList.qml
    RESOURCES
        ../qml/LuiStyle.js
        ${LUI_QML_ICONS}
)

target_link_libraries(lui_qml PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)

target_include_directories(lui_qml PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
