//! Agent acceptance must not mistake retained semantic nodes for a healthy render.
use super::{accept_agent_reply, agent_ready};
use crate::{render::Renderer, wire::Batch};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};

#[component]
fn AgentFailureScenario() -> impl IntoElement {
    let renderer = Renderer::new(|_, _| {});
    let patch = |generation, ops| {
        Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
    };
    renderer
        .apply(patch(
            1,
            json!([
                {"op":"create-node","id":1,"kind":"text"},
                {"op":"set-prop","id":1,"property":"text","value":"Nov 12th, 2026"}
            ]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let retained = renderer.node_snapshot(1).unwrap();
    let query = || Ok(json!({"ok":true,"op":"find","nodes":[1]}).to_string());
    assert!(agent_ready(&renderer, Some("find")).is_ok());
    assert!(accept_agent_reply(&renderer, Some("find"), true, query()).is_ok());
    // A runtime rejection can arrive with the same reply as a successful query.
    let rejected = renderer.apply(patch(2, json!([
        {"op":"set-prop","id":1,"property":"foreground","value":"var(--missing-agent-color)"}
    ]))).unwrap_err();
    renderer.fail(rejected.clone());
    renderer.fail("resync failed: authoritative snapshot rejected".into());
    let diagnostic = renderer.failure().unwrap();
    assert!(diagnostic.contains(&rejected));
    assert!(diagnostic.contains("resync failed"));
    assert!(std::sync::Arc::ptr_eq(
        &retained,
        &renderer.node_snapshot(1).unwrap()
    ));
    for operation in [
        "find",
        "tree",
        "prop",
        "native-bounds",
        "native-dialog",
        "native-dialog-answer",
        "native-press",
        "press",
        "gc-stats",
    ] {
        assert_eq!(
            agent_ready(&renderer, Some(operation)),
            Err(diagnostic.clone())
        );
        // Both a fresh rejection and later patch-free replies must expose the cause.
        for published in [false, true, true] {
            assert_eq!(
                accept_agent_reply(&renderer, Some(operation), published, query()),
                Err(diagnostic.clone())
            );
        }
    }
    for operation in ["hello", "screenshot"] {
        assert!(agent_ready(&renderer, Some(operation)).is_ok());
        let answer = json!({"ok":true,"op":operation,"data":"retained diagnostic capture"});
        let accepted =
            accept_agent_reply(&renderer, Some(operation), true, Ok(answer.to_string())).unwrap();
        let accepted: Value = serde_json::from_str(&accepted).unwrap();
        assert_eq!(accepted["ok"], true);
        assert_eq!(accepted["data"], answer["data"]);
        assert_eq!(accepted["backend_error"], diagnostic);
    }
    text("agent rejects stale semantic success").test_id("agent-failure-checked")
}

#[test]
fn renderer_failure_rejects_semantic_success_but_preserves_diagnostics() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<AgentFailureScenario>())).unwrap();
    app.wait_for("id:agent-failure-checked").unwrap();
}
