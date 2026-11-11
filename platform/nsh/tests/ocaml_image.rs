//! This checks the Load C ABI; actual native decode uses test_nsh_image_app.py.
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
fn ImageAbiProbe(props: ProbeProps) -> impl IntoElement {
    let status = signal("pending".to_owned());
    let path = props.path.get_untracked();
    spawn(async move {
        status.set(match exercise(path).await {
            Ok(()) => "image-abi-passed".into(),
            Err(error) => error,
        });
    });
    text(move || status.get())
}

async fn exercise(path: String) -> Result<(), String> {
    let (session, _) = Session::open(path, 1).await?;
    let answer = session.agent(json!({"op":"tree"}).to_string()).await?;
    let tree: Value = serde_json::from_str(answer.agent.as_deref().ok_or("missing tree")?)
        .map_err(|error| error.to_string())?;
    fn image(nodes: &Value) -> Option<i64> {
        nodes.as_array()?.iter().find_map(|node| {
            if node["kind"] == "image" {
                node["id"].as_i64()
            } else {
                image(&node["children"])
            }
        })
    }
    let id = image(&tree["nodes"]).ok_or_else(|| format!("missing fixture Image: {tree}"))?;
    session.dispatch(Event::Load(id)).await?;
    let answer = session
        .agent(
            json!({"op":"prop",
        "selector":"prop:accessibility-identifier=image-loads","name":"text"})
            .to_string(),
        )
        .await?;
    let value: Value = serde_json::from_str(answer.agent.as_deref().ok_or("missing Load result")?)
        .map_err(|error| error.to_string())?;
    if value["ok"] != true || value["value"] != "Image loads 1" {
        return Err(format!(
            "Load did not reach the real OCaml handler: {value}"
        ));
    }
    Ok(())
}

#[test]
fn canonical_image_load_reaches_the_existing_ocaml_callback() -> Result<(), String> {
    let path = if let Some(path) = std::env::var_os("LUI_NSH_IMAGE_LIBRARY") {
        PathBuf::from(path).to_string_lossy().into_owned()
    } else {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let python = if cfg!(target_os = "windows") {
            "python"
        } else {
            "python3"
        };
        let build = Command::new(python)
            .args([
                "platform/nsh/tests/fixtures/build_virtual.py",
                "--fixture",
                "image",
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
    let mut app = Headless::start(EngineConfig::new(Root::new::<ImageAbiProbe>(move || {
        ProbeProps {
            path: Prop::new(path.clone()),
        }
    })))
    .map_err(|error| error.to_string())?;
    app.wait_for("text:image-abi-passed")
}
