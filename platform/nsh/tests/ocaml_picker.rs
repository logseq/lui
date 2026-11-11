//! Real Picked/Dismiss C ABI dispatch, separate from native OS dialog UX.
use lui_nsh::runtime::{Event, Session};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{path::PathBuf, process::Command};

#[derive(Clone, PartialEq, Props)]
struct ProbeProps {
    path: Prop<String>,
}

#[component]
fn PickerAbiProbe(props: ProbeProps) -> impl IntoElement {
    let status = signal("pending".to_owned());
    let path = props.path.get_untracked();
    spawn(async move {
        status.set(match exercise(path).await {
            Ok(()) => "picker-abi-passed".into(),
            Err(error) => error,
        });
    });
    text(move || status.get())
}

async fn property(session: &Session, identifier: &str) -> Result<Value, String> {
    let answer = session
        .agent(json!({"op":"prop", "selector":format!("prop:accessibility-identifier={identifier}"), "name":"text"}).to_string())
        .await?;
    let value: Value = serde_json::from_str(answer.agent.as_deref().ok_or("missing property")?)
        .map_err(|error| error.to_string())?;
    if value["ok"] != true {
        return Err(format!("Cannot inspect {identifier}: {value}"));
    }
    Ok(value["value"].clone())
}

async fn exercise(path: String) -> Result<(), String> {
    let (session, _) = Session::open(path, 1).await?;
    let answer = session.agent(json!({"op":"tree"}).to_string()).await?;
    let tree: Value = serde_json::from_str(answer.agent.as_deref().ok_or("missing tree")?)
        .map_err(|error| error.to_string())?;
    fn picker(nodes: &Value) -> Option<i64> {
        nodes.as_array()?.iter().find_map(|node| {
            if node["kind"] == "file-picker" {
                node["id"].as_i64()
            } else {
                picker(&node["children"])
            }
        })
    }
    let node = picker(&tree["nodes"]).ok_or_else(|| format!("missing fixture picker: {tree}"))?;
    for result in [
        json!({"request":9_007_199_254_740_993_i64,"paths":["/tmp/资料/hello world.md","C:\\notes\\draft.md"]}),
        json!({"request":"request-错误","paths":[],"error":"Permission denied: 资料"}),
    ] {
        let payload = result.to_string();
        session
            .dispatch(Event::Picked {
                node,
                payload: payload.clone(),
            })
            .await?;
        let received = property(&session, "picker-payload").await?;
        if received != Value::String(payload) {
            return Err(format!(
                "Picked payload changed across the real ABI: {received}"
            ));
        }
    }
    session.dispatch(Event::Dismiss(node)).await?;
    if property(&session, "picker-dismissals").await? != "1" {
        return Err("Dismiss did not reach its OCaml callback".into());
    }
    Ok(())
}

#[test]
fn native_picked_paths_and_errors_reach_the_real_ocaml_callback_unchanged() -> Result<(), String> {
    let path = if let Some(path) = std::env::var_os("LUI_NSH_PICKER_LIBRARY") {
        PathBuf::from(path).to_string_lossy().into_owned()
    } else {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let build = Command::new(if cfg!(target_os = "windows") {
            "python"
        } else {
            "python3"
        })
        .args([
            "platform/nsh/tests/fixtures/build_virtual.py",
            "--fixture",
            "picker",
        ])
        .current_dir(root)
        .output()
        .map_err(|error| error.to_string())?;
        if !build.status.success() {
            return Err(String::from_utf8_lossy(&build.stderr).into_owned());
        }
        String::from_utf8(build.stdout)
            .map_err(|error| error.to_string())?
            .trim()
            .to_owned()
    };
    let mut app = Headless::start(EngineConfig::new(Root::new::<PickerAbiProbe>(move || {
        ProbeProps {
            path: Prop::new(path.clone()),
        }
    })))
    .map_err(|error| error.to_string())?;
    app.wait_for("text:picker-abi-passed")
}
