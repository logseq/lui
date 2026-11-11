//! Explicit native-controller activation; selectors remain owned by OCaml.
use crate::{render::Renderer, store::Node, style};
use nsh_core::{PointerEvents, PressEvent, element::ElementRef, prelude::*};
use serde_json::{Value, json};
use std::sync::Arc;

pub(crate) fn find_request(request: &Value) -> Result<String, String> {
    let selector = request
        .get("selector")
        .and_then(Value::as_str)
        .filter(|selector| !selector.is_empty())
        .ok_or("native-press requires a selector")?;
    Ok(json!({"op":"find","selector":selector}).to_string())
}

fn unique_target(answer: &str) -> Result<u64, String> {
    let answer: Value = serde_json::from_str(answer).map_err(|error| error.to_string())?;
    if answer.get("ok") != Some(&Value::Bool(true)) {
        return Err(answer
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("canonical find failed")
            .to_owned());
    }
    let nodes = answer
        .get("nodes")
        .and_then(Value::as_array)
        .ok_or("canonical find returned no node list")?;
    match nodes.as_slice() {
        [node] => node
            .as_u64()
            .ok_or("canonical find returned an invalid node id".into()),
        [] => Err("native-press selector matched no nodes".into()),
        _ => Err("native-press requires exactly one matching node".into()),
    }
}

fn admitted(id: u64, lookup: impl Fn(u64) -> Option<Arc<Node>>) -> Result<(), String> {
    let target = lookup(id).ok_or("native-press target is retired")?;
    if !target.boolean("enabled", true) {
        return Err("native-press target is disabled".into());
    }
    let mut current = Some(target);
    // Reuse the actual renderer policy, including presented surfaces opting
    // back in. BoxNone permits child controls; this is not a new CSS cascade.
    while let Some(node) = current {
        match style::pointer_policy(&node) {
            Some(PointerEvents::None) => {
                return Err("native-press target excludes pointer input".into());
            }
            Some(PointerEvents::Auto | PointerEvents::BoxOnly | PointerEvents::BoxNone) => break,
            None => current = node.parent.and_then(&lookup),
        }
    }
    Ok(())
}

async fn press_reference(
    reference: ElementRef,
    current: impl Fn() -> Result<(), String>,
) -> Result<bool, String> {
    current()?;
    let native = reference
        .node()
        .ok_or("native-press target has no native host")?;
    let measurement = reference
        .measure()
        .await
        .ok_or("native-press target is not laid out")?;
    let width = measurement.frame.size.width.0;
    let height = measurement.frame.size.height.0;
    let x = measurement.page.x.0 + width / 2.0;
    let y = measurement.page.y.0 + height / 2.0;
    if ![width, height, x, y].iter().all(|value| value.is_finite()) || width <= 0.0 || height <= 0.0
    {
        return Err("native-press target has no finite positive bounds".into());
    }
    current()?;
    if reference.node() != Some(native) {
        return Err("native-press native host changed while measuring".into());
    }
    let handled = reference
        .press_at(PressEvent {
            page_position: point(px(x), px(y)),
            clicks: 1,
            ..Default::default()
        })
        .await;
    crate::app::wait_for_commit().await?;
    Ok(handled)
}

pub(crate) async fn press(renderer: &Renderer, answer: &str) -> Result<String, String> {
    let id = unique_target(answer)?;
    let node = renderer
        .node_snapshot(id)
        .ok_or("native-press target is retired")?;
    let incarnation = node.incarnation;
    let reference = renderer
        .native_reference(id, incarnation)
        .ok_or("native-press target has no retained reference")?;
    let handled = press_reference(reference, || {
        if renderer.current_incarnation(id) != Some(incarnation) {
            return Err("native-press target incarnation changed".into());
        }
        admitted(id, |id| renderer.node_snapshot(id))
    })
    .await?;
    Ok(
        json!({"ok":true,"op":"native-press","node":id,"incarnation":incarnation,
        "handled":handled,"activation":"native-controller"})
        .to_string(),
    )
}

pub(crate) fn hello(answer: String) -> Result<String, String> {
    let mut answer: Value = serde_json::from_str(&answer).map_err(|error| error.to_string())?;
    if answer.get("ok") == Some(&Value::Bool(true)) {
        let mut operations = vec!["native-press"];
        if cfg!(target_os = "macos") {
            operations.push("screenshot");
        }
        answer["host_native_ops"] = json!(operations);
    }
    Ok(answer.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use std::{cell::Cell, collections::BTreeMap};

    #[test]
    fn canonical_find_must_resolve_exactly_one_valid_target() {
        assert_eq!(unique_target(r#"{"ok":true,"nodes":[9]}"#).unwrap(), 9);
        for reply in [
            r#"{"ok":true,"nodes":[]}"#,
            r#"{"ok":true,"nodes":[1,2]}"#,
            r#"{"ok":true,"nodes":[-1]}"#,
            r#"{"ok":false,"error":"bad selector"}"#,
        ] {
            assert!(unique_target(reply).is_err(), "{reply}");
        }
        assert_eq!(
            serde_json::from_str::<Value>(&find_request(&json!({"selector":"text:More"})).unwrap())
                .unwrap(),
            json!({"op":"find","selector":"text:More"})
        );
    }

    #[test]
    fn hello_advertises_host_operations_without_rewriting_semantic_operations() {
        let answer: Value = serde_json::from_str(
            &hello(json!({"ok":true,"ops":["find","press"]}).to_string()).unwrap(),
        )
        .unwrap();
        assert_eq!(answer["ops"], json!(["find", "press"]));
        assert!(
            answer["host_native_ops"]
                .as_array()
                .unwrap()
                .contains(&json!("native-press"))
        );
    }

    #[test]
    fn admission_reuses_presented_surface_and_explicit_pointer_policies() {
        let mut root = Node {
            id: 1,
            kind: "column".into(),
            ..Default::default()
        };
        root.props.insert("pointer-enabled".into(), json!(false));
        let surface = Node {
            id: 2,
            parent: Some(1),
            kind: "dropdown-menu".into(),
            ..Default::default()
        };
        let mut button = Node {
            id: 3,
            parent: Some(2),
            kind: "button".into(),
            ..Default::default()
        };
        let mut nodes = BTreeMap::from([
            (1, Arc::new(root)),
            (2, Arc::new(surface)),
            (3, Arc::new(button.clone())),
        ]);
        assert!(admitted(3, |id| nodes.get(&id).cloned()).is_ok());
        button.parent = Some(1);
        nodes.insert(3, Arc::new(button.clone()));
        assert!(admitted(3, |id| nodes.get(&id).cloned()).is_err());
        button.props.insert("pointer-enabled".into(), json!(true));
        nodes.insert(3, Arc::new(button.clone()));
        assert!(admitted(3, |id| nodes.get(&id).cloned()).is_ok());
        button.props.insert("enabled".into(), json!(false));
        nodes.insert(3, Arc::new(button));
        assert!(admitted(3, |id| nodes.get(&id).cloned()).is_err());
    }

    #[derive(Clone)]
    struct RetireWhileMeasuring(bool);

    #[component]
    fn NativeOwnedButton() -> impl IntoElement {
        let reference = element_ref();
        let activated = signal(0_u32);
        let retire = engine_context::<RetireWhileMeasuring>().is_some_and(|mode| mode.0);
        let result = signal(String::new());
        spawn(async move {
            crate::app::wait_for_commit().await.unwrap();
            let checks = Cell::new(0);
            let outcome = press_reference(reference, || {
                checks.set(checks.get() + 1);
                if retire && checks.get() > 1 {
                    Err("retired during measurement".into())
                } else {
                    Ok(())
                }
            })
            .await;
            result.set(match outcome {
                Ok(handled) => format!("handled:{handled}"),
                Err(error) => error,
            });
        });
        view()
            .flex_col()
            .child(
                nsh_base::Button::element(nsh_base::ButtonProps::default())
                    .element_ref(&reference)
                    .on_event(move |event: &nsh_base::ButtonEvent| {
                        if matches!(event, nsh_base::ButtonEvent::Press) {
                            activated.set(activated.get() + 1);
                        }
                    })
                    .child(text(move || {
                        format!("Native activations:{}", activated.get())
                    })),
            )
            .child(text(result))
    }

    #[test]
    fn public_retained_reference_activates_actual_native_button_controller() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<NativeOwnedButton>())).unwrap();
        app.wait_for("text:Native activations:1").unwrap();
        app.wait_for("text:handled:true").unwrap();
    }

    #[test]
    fn target_retirement_during_measurement_prevents_native_activation() {
        let mut app = Headless::start(EngineConfig {
            context: EngineContext::default().with(RetireWhileMeasuring(true)),
            ..EngineConfig::new(Root::of::<NativeOwnedButton>())
        })
        .unwrap();
        app.wait_for("text:retired during measurement").unwrap();
        app.wait_for("text:Native activations:0").unwrap();
    }
}
