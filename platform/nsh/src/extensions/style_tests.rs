use super::*;
use crate::{application_theme::ThemeRegistry, render::Renderer, wire::Batch};
use nsh_core::{StyleDecl, StyleKey, StyleValue, element::Style};
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{
    cell::Cell,
    sync::atomic::{AtomicUsize, Ordering},
};

fn schema() -> Schema {
    serde_json::from_value(
        serde_json::from_str::<Value>(include_str!("../../tests/fixtures/contract_oracle.json"))
            .unwrap()["extensions"]["schema"]
            .clone(),
    )
    .unwrap()
}
fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}
fn width(node: &Node, resolve: impl Fn(&str) -> Result<String, String>) -> Result<Style, String> {
    let authored = node
        .extension
        .as_ref()
        .unwrap()
        .properties
        .get("title")
        .and_then(Value::as_str)
        .ok_or("missing width expression")?;
    let resolved = resolve(authored)?;
    let number = resolved
        .strip_suffix("px")
        .ok_or("invalid extension width")?
        .parse::<f32>()
        .map_err(|_| "invalid extension width")?;
    let value = StyleKey::Width
        .parse_value(StyleValue::Number(number))
        .map_err(|_| "invalid extension width")?;
    Ok(Style::from_decls([StyleDecl::Set(StyleKey::Width, value)]))
}
#[derive(Clone)]
struct Evidence {
    checks: Arc<AtomicUsize>,
    mounts: Arc<AtomicUsize>,
}
#[component]
fn ThemedFixture() -> impl IntoElement {
    let evidence = engine_context::<Evidence>().unwrap();
    let themes = ThemeRegistry::new();
    provide_context(themes);
    themes
        .install_snapshot_json(r#"{"mode":"light","vars":{"--extent":"120px"}}"#)
        .unwrap();
    themes.set_mode("light").unwrap();
    let mounts = evidence.mounts.clone();
    let checks = evidence.checks.clone();
    let registry = Extensions::builder()
        .register(schema(), move |context| {
            mounts.fetch_add(1, Ordering::SeqCst);
            view()
                .h(px(40.0))
                .state_inline_style(move || {
                    width(&context.node.get(), |value| context.resolve_text(value))
                        .expect("themed preflight admitted width")
                })
                .test_id("themed-body")
                .into_element()
        })
        .unwrap()
        .validate_themed("app-oracle", move |node, theme| {
            checks.fetch_add(1, Ordering::SeqCst);
            width(node, |value| theme.resolve_text(value)).map(|_| ())
        })
        .unwrap()
        .freeze(Profile {
            os: "macos".into(),
            host: "nsh".into(),
        })
        .unwrap();
    let renderer = Renderer::with_extensions(registry, |_, _| {});
    // Initialize from the installed snapshot before the first application patch;
    // the deferred theme effect has not run at this point.
    let content = renderer.element();
    renderer
        .apply(patch(
            1,
            json!([
        {"op":"create-node","id":1,"kind":"column"},
        {"op":"create-extension","id":2,"identifier":"app-oracle","fingerprint":""},
        {"op":"set-extension-prop","id":2,"property":"count","value":1},
        {"op":"set-extension-prop","id":2,"property":"title","value":"var(--extent)"},
        {"op":"create-node","id":3,"kind":"text"},
        {"op":"set-prop","id":3,"property":"text","value":"Sibling"},
        {"op":"insert-child","parent":1,"child":2,"index":0},
        {"op":"insert-child","parent":1,"child":3,"index":1}]),
        ))
        .unwrap();
    renderer.set_root(1).unwrap();
    let reject_property = renderer.clone();
    let reject_scope = renderer.clone();
    let sibling = renderer.clone();
    let accepted = renderer.clone();
    let generation = Rc::new(Cell::new(1));
    let sibling_generation = generation.clone();
    view().child(content)
        .child(nsh_base::button().child(text("Reject property")).on_press(move||{
            let before=reject_property.node_snapshot(2).unwrap();
            assert!(reject_property.apply(patch(2,json!([{"op":"set-extension-prop","id":2,"property":"title","value":"var(--missing)"}]))).is_err());
            assert!(Arc::ptr_eq(&before,&reject_property.node_snapshot(2).unwrap()));
        }))
        .child(nsh_base::button().child(text("Reject scope")).on_press(move||{
            let before=reject_scope.node_snapshot(1).unwrap();
            assert!(reject_scope.apply(patch(2,json!([{"op":"set-prop","id":1,"property":"theme","value":"{\"--extent\":\"invalid\"}"}]))).is_err());
            assert!(Arc::ptr_eq(&before,&reject_scope.node_snapshot(1).unwrap()));
        }))
        .child(nsh_base::button().child(text("Edit sibling")).on_press(move||{
            let before=evidence.checks.load(Ordering::SeqCst);let next=sibling_generation.get()+1;
            sibling.apply(patch(next,json!([{"op":"set-prop","id":3,"property":"text","value":"Sibling updated"}]))).unwrap();sibling_generation.set(next);
            assert_eq!(evidence.checks.load(Ordering::SeqCst),before,"unrelated sibling edit revalidated the extension");
        }))
        .child(nsh_base::button().child(text("Accept property")).on_press(move||{
            let next=generation.get()+1;accepted.apply(patch(next,json!([{"op":"set-extension-prop","id":2,"property":"count","value":2}]))).unwrap();generation.set(next);
        }))
        .child(nsh_base::button().child(text("Reject theme refresh")).on_press(move||{
            themes.install_snapshot_json(r#"{"mode":"light","vars":{"--extent":"invalid"}}"#).unwrap();
        }))
}
#[test]
fn themed_preflight_rolls_back_properties_ancestry_and_refresh_without_extra_sibling_work() {
    let evidence = Evidence {
        checks: Arc::new(AtomicUsize::new(0)),
        mounts: Arc::new(AtomicUsize::new(0)),
    };
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(evidence.clone()),
        ..EngineConfig::new(Root::of::<ThemedFixture>())
    })
    .unwrap();
    app.wait_for("id:themed-body").unwrap();
    let before = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("themed-body"))
        .unwrap();
    assert_eq!(before.bounds.size.width, px(120.0));
    for action in [
        "Reject property",
        "Reject scope",
        "Edit sibling",
        "Accept property",
        "Reject theme refresh",
    ] {
        app.press(action).unwrap();
    }
    app.wait_for("invalid extension width").unwrap();
    let after = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("themed-body"))
        .unwrap();
    assert_eq!(after.id, before.id);
    assert_eq!(after.bounds.size.width, px(120.0));
    assert_eq!(evidence.mounts.load(Ordering::SeqCst), 1);
}
