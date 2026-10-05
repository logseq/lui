//! Event gates mirroring `Lui_protocol.event_supported`: a host may only fire
//! events the node's kind declares, plus the opt-in `*-enabled` props used by
//! role-driven kinds (e.g. treeitems).

use crate::store::Node;
use crate::wire_schema::{NodeKind, Property};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventKind {
    Press,
    PressModifiers,
    LongPress,
    TextChanged,
    Submit,
    ToggleChanged,
    Change,
    ValueChanged,
    Dismiss,
    DoublePress,
    Appear,
    ScrollCompleted,
    VisibleRange,
    Picked,
    PressDetail,
    PointerDown,
    PointerUp,
    PointerEnter,
    PointerLeave,
    ContextMenuPress,
    ExtensionEvent,
}

/// Kind-level support table — keep in sync with
/// `src/lui_protocol.ml:event_supported`.
pub fn event_supported(kind: NodeKind, event: EventKind) -> bool {
    use EventKind::*;
    use NodeKind::*;
    match event {
        Press | PressModifiers | PressDetail | PointerDown | PointerUp => matches!(
            kind,
            Button
                | Column
                | Radio
                | Select
                | Combobox
                | MenuItem
                | ListItem
                | Text
                | TableCell
                | TimelineItem
                | FileImage
                | BottomTab
                | SwipeAction
        ),
        PointerEnter | PointerLeave => kind != Root,
        // Mirrors `context_menu_host_kind` in `src/lui_protocol.ml`.
        ContextMenuPress => matches!(
            kind,
            Button
                | ToggleButton
                | Toggle
                | Radio
                | Slider
                | NumberStepper
                | TextField
                | SecureField
                | Input
                | SearchField
                | Textarea
                | Checkbox
                | SwitchControl
                | Select
                | Combobox
                | MenuItem
                | ListItem
                | Accordion
                | Text
                | TableCell
        ),
        LongPress => matches!(kind, Button | ToggleButton | ListItem),
        TextChanged => matches!(
            kind,
            TextField | SecureField | Input | SearchField | Textarea | Combobox
        ),
        Submit => matches!(
            kind,
            TextField | SecureField | Input | SearchField | Textarea | Combobox | ListItem
        ),
        ToggleChanged => matches!(
            kind,
            ToggleButton
                | Checkbox
                | SwitchControl
                | Toggle
                | Radio
                | Accordion
                | Drawer
                | ListItem
        ),
        Change => kind == Radio,
        ValueChanged => matches!(kind, Slider | NumberStepper | Split),
        Dismiss => matches!(
            kind,
            Select
                | Combobox
                | DropdownMenu
                | Toast
                | Dialog
                | Drawer
                | Sheet
                | FilePreview
                | FilePicker
        ),
        DoublePress => kind == ListItem,
        Appear => kind != Root,
        ScrollCompleted | VisibleRange => kind == ListContainer,
        Picked => kind == FilePicker,
        ExtensionEvent => false,
    }
}

/// Full gate: kind table + property overrides
/// (`src/lui_protocol.ml:event_supported_for_properties`). Extension nodes
/// admit only `ExtensionEvent` — routed by identifier, not kind.
pub fn event_allowed(node: &Node, event: EventKind) -> bool {
    let kind = match &node.identity {
        crate::store::NodeIdentity::Standard(kind) => *kind,
        crate::store::NodeIdentity::Extension { .. } => return event == EventKind::ExtensionEvent,
    };
    if event == EventKind::Appear && node.flag(Property::AppearEnabled) {
        return true;
    }
    if node.is_treeitem() {
        return match event {
            EventKind::Press | EventKind::PressModifiers => node.flag(Property::PressEnabled),
            EventKind::PressDetail
            | EventKind::PointerDown
            | EventKind::PointerUp
            | EventKind::PointerEnter
            | EventKind::PointerLeave
            | EventKind::ContextMenuPress => node.flag(Property::PointerEnabled),
            EventKind::Change => node.flag(Property::ChangeEnabled),
            EventKind::ToggleChanged => node.flag(Property::ToggleEnabled),
            _ => event_supported(kind, event),
        };
    }
    event_supported(kind, event)
}
