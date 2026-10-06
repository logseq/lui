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
    Load,
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
                | Row
                | Box
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
        Load => kind == Image,
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::NodeIdentity;
    use crate::wire::Value;
    use std::collections::BTreeMap;

    fn node_of_kind(kind: NodeKind) -> Node {
        Node {
            id: 1,
            identity: NodeIdentity::Standard(kind),
            props: BTreeMap::new(),
            extension_props: BTreeMap::new(),
            children: Vec::new(),
            parent: None,
        }
    }

    fn extension_node() -> Node {
        Node {
            id: 2,
            identity: NodeIdentity::Extension {
                identifier: "logseq-button".to_string(),
                fingerprint: "fp".to_string(),
            },
            props: BTreeMap::new(),
            extension_props: BTreeMap::new(),
            children: Vec::new(),
            parent: None,
        }
    }

    #[test]
    fn kind_table_matches_the_schema_support() {
        use EventKind::*;
        use NodeKind::*;
        for (kind, event) in [
            (Button, Press),
            (Button, PressModifiers),
            (ListItem, DoublePress),
            (TextField, TextChanged),
            (Textarea, Submit),
            (Toggle, ToggleChanged),
            (Radio, Change),
            (Slider, ValueChanged),
            (Dialog, Dismiss),
            (ListContainer, ScrollCompleted),
            (ListContainer, VisibleRange),
            (FilePicker, Picked),
            (Text, Appear),
        ] {
            assert!(
                event_supported(kind, event),
                "{kind:?} must support {event:?}"
            );
        }
        for (kind, event) in [
            (Button, TextChanged),
            (TextField, Press),
            (Root, Appear),
            (Slider, DoublePress),
            (Dialog, ToggleChanged),
        ] {
            assert!(
                !event_supported(kind, event),
                "{kind:?} must not support {event:?}"
            );
        }
    }

    #[test]
    fn extension_nodes_only_admit_extension_events() {
        let node = extension_node();
        assert!(event_allowed(&node, EventKind::ExtensionEvent));
        for event in [
            EventKind::Press,
            EventKind::TextChanged,
            EventKind::Submit,
            EventKind::Appear,
            EventKind::Dismiss,
        ] {
            assert!(!event_allowed(&node, event), "{event:?} must be gated");
        }
        // The kind table itself never admits ExtensionEvent — only
        // extension identities route there.
        assert!(!event_supported(NodeKind::Button, EventKind::ExtensionEvent));
    }

    #[test]
    fn flag_props_override_the_kind_table() {
        let mut node = node_of_kind(NodeKind::Text);
        // treeitem role switches press/change/toggle to opt-in flags.
        node.props.insert(
            Property::RoleValue,
            Value::Str("treeitem".to_string()),
        );
        assert!(!event_allowed(&node, EventKind::Press));
        node.props
            .insert(Property::PressEnabled, Value::Bool(true));
        assert!(event_allowed(&node, EventKind::Press));
        assert!(event_allowed(&node, EventKind::PressModifiers));
        assert!(!event_allowed(&node, EventKind::ToggleChanged));
        node.props
            .insert(Property::ToggleEnabled, Value::Bool(true));
        assert!(event_allowed(&node, EventKind::ToggleChanged));
    }

    #[test]
    fn appear_enabled_flag_unlocks_appear() {
        let mut node = node_of_kind(NodeKind::Root);
        // Root never supports Appear in the kind table, but the flag wins.
        assert!(!event_supported(NodeKind::Root, EventKind::Appear));
        node.props
            .insert(Property::AppearEnabled, Value::Bool(true));
        assert!(event_allowed(&node, EventKind::Appear));
    }
}

