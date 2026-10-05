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
    ExtensionEvent,
}

/// Kind-level support table — keep in sync with
/// `src/lui_protocol.ml:event_supported`.
pub fn event_supported(kind: NodeKind, event: EventKind) -> bool {
    use EventKind::*;
    use NodeKind::*;
    match event {
        Press | PressModifiers => matches!(
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
            EventKind::Change => node.flag(Property::ChangeEnabled),
            EventKind::ToggleChanged => node.flag(Property::ToggleEnabled),
            _ => event_supported(kind, event),
        };
    }
    event_supported(kind, event)
}
