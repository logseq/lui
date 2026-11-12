//! Policy/event-order tests; Headless does not synthesize input Escape.
//! Actual AppKit keyboard delivery is qualified by the application scalar test.
use super::*;
use crate::{events::Capabilities, store::Store, wire::Batch};
use serde_json::json;
use std::cell::RefCell;

fn node(kind: &str) -> Node {
    Node {
        id: 2,
        kind: kind.into(),
        props: serde_json::from_value(json!({"dismiss-enabled":true,"submit-on-blur":true}))
            .unwrap(),
        ..Default::default()
    }
}

#[test]
fn cancellation_arms_blur_suppression_before_dispatch_and_only_once_per_focus() {
    for kind in [
        "input",
        "text-field",
        "secure-field",
        "search-field",
        "textarea",
    ] {
        let node = node(kind);
        let state = Cell::new(BlurState::default());
        let events = RefCell::new(Vec::new());
        request_dismiss(&node, &state, &|event| {
            assert!(
                !submits_on_blur(&node, state.get()),
                "{kind}: a reentrant blur must not save"
            );
            events.borrow_mut().push(event);
        });
        request_dismiss(&node, &state, &|event| events.borrow_mut().push(event));
        assert_eq!(*events.borrow(), [Event::Dismiss(2)], "{kind}");
        let before = state.replace(BlurState::default());
        assert!(
            !submits_on_blur(&node, before),
            "{kind}: the following native blur is suppressed"
        );
        // A fresh focus interval has the ordinary save policy again.
        assert!(submits_on_blur(&node, state.get()), "{kind}");
    }
}

#[test]
fn removed_disabled_and_composing_dismissal_leave_the_policy_unclaimed() {
    for mode in ["removed", "false", "disabled", "composing"] {
        let mut node = node("text-field");
        let state = Cell::new(BlurState {
            composing: mode == "composing",
            ..Default::default()
        });
        match mode {
            "removed" => {
                node.props.remove("dismiss-enabled");
            }
            "false" => {
                node.props.insert("dismiss-enabled".into(), json!(false));
            }
            "disabled" => {
                node.props.insert("enabled".into(), json!(false));
            }
            _ => {}
        }
        request_dismiss(&node, &state, &|_| {
            panic!("{mode}: dismissal must not escape")
        });
        assert!(!state.get().suppress_native_blur, "{mode}");
    }
    let mut ordinary = node("input");
    ordinary.props.remove("dismiss-enabled");
    let state = Cell::new(BlurState::default());
    request_dismiss(&ordinary, &state, &|_| panic!("unhandled cancellation"));
    assert!(
        submits_on_blur(&ordinary, state.get()),
        "ordinary number/editor blur keeps saving"
    );
}

#[test]
fn cancellation_capability_retains_mount_capacity_without_reviving_removed_handlers() {
    let mut node = node("input");
    node.props.insert("dismiss-enabled".into(), json!(false));
    let installed = Capabilities::authored(&node);
    node.props.insert("dismiss-enabled".into(), json!(true));
    assert!(installed.contains(Capabilities::required(&node)));
    node.props.remove("dismiss-enabled");
    let absent = Capabilities::authored(&node);
    assert!(absent.contains(Capabilities::required(&node)));
    node.props.insert("dismiss-enabled".into(), json!(true));
    assert!(
        !absent.contains(Capabilities::required(&node)),
        "late observer requires a keyed remount"
    );
    assert!(
        installed.contains(Capabilities::required(&node)),
        "removing an installed flag retains capacity"
    );
}

#[test]
fn dismissal_wire_kind_and_scalar_validation_are_atomic() {
    for (kind, value) in [("button", json!(true)), ("input", json!("true"))] {
        let mut store = Store::default();
        let wire = json!({"generation":1,"ops":[
            {"op":"create-node","id":2,"kind":kind},
            {"op":"set-prop","id":2,"property":"dismiss-enabled","value":value}
        ]});
        let result = Batch::decode(&wire.to_string()).and_then(|batch| store.apply(batch));
        assert!(
            result.is_err(),
            "{kind}: invalid cancellation capability must fail"
        );
        assert!(
            store.nodes.is_empty(),
            "rejected input batch must not partially publish"
        );
        assert_eq!(store.generation, 0);
    }
}
