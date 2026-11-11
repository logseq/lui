//! A separate executable isolates its OCaml runtime from other fixtures.
use lui_nsh::{
    runtime::{Event, Session},
    store::Store,
    wire::Operation,
};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use std::{path::PathBuf, process::Command};

#[derive(Clone, PartialEq, Props)]
struct ProbeProps {
    path: Prop<String>,
}

#[component]
fn ProtocolProbe(props: ProbeProps) -> impl IntoElement {
    let status = signal("pending".to_owned());
    let path = props.path.get_untracked();
    spawn(async move {
        status.set(match exercise(path).await {
            Ok(()) => "passed".into(),
            Err(error) => error,
        });
    });
    text(move || status.get())
}

async fn exercise(path: String) -> Result<(), String> {
    let (session, initial) = Session::open(&path, 1).await?;
    let mut store = Store::default();
    for batch in initial.batches {
        store.apply(batch)?;
    }
    store.set_root(initial.root as u64)?;
    let editor = store
        .nodes
        .values()
        .find(|node| {
            node.string("accessibility-label") == "New todo" || node.string("label") == "New todo"
        })
        .ok_or("missing editor")?
        .id;
    if Session::open(&path, 1).await.is_ok() {
        return Err("competing application was accepted".into());
    }

    let hello = session.agent(r#"{"op":"hello"}"#.into()).await?;
    let hello: serde_json::Value =
        serde_json::from_str(hello.agent.as_deref().ok_or("missing agent reply")?)
            .map_err(|e| e.to_string())?;
    if hello["host"] != "Todos" || hello["protocol"] != "lui-agent" {
        return Err(format!("wrong host: {hello}"));
    }

    let text = "A\0中文";
    let changed = session
        .dispatch(Event::Text {
            node: editor as i64,
            text: text.into(),
        })
        .await?;
    let echoed = changed.batches.iter().flat_map(|batch| &batch.ops).any(|operation| matches!(operation,
        Operation::SetProp { id, property, value } if *id == editor && property == "text" && value == text));
    if !echoed {
        return Err("length-carrying edit did not preserve embedded NUL / Unicode".into());
    }
    for batch in changed.batches {
        store.apply(batch)?;
    }

    let generation = store.generation;
    let refused = session
        .dispatch(Event::Value {
            node: editor as i64,
            value: 0.5,
        })
        .await?;
    if refused.diagnostic.is_none() || !refused.batches.is_empty() {
        return Err("refusal did not return isolated recovery".into());
    }
    let snapshot = refused.snapshot.ok_or("refusal did not resync")?;
    if snapshot.generation != generation {
        return Err("refusal changed the committed generation".into());
    }
    store.apply_snapshot(snapshot)?;
    store.set_root(refused.root as u64)?;
    if store.nodes[&editor].string("text") != text {
        return Err("recovery changed accepted editing state".into());
    }

    let snapshot = session
        .resync()
        .await?
        .snapshot
        .ok_or("explicit resync missing")?;
    store.apply_snapshot(snapshot)?;
    let paused = session.pause(true).await?;
    if paused.next_delay.is_some() {
        return Err("paused clock still armed".into());
    }
    session.advance(1000.0).await?;
    session.pause(false).await?;
    session.close().await?;
    if session.dispatch(Event::Submit(editor as i64)).await.is_ok() {
        return Err("closed session dispatched an event".into());
    }
    for _ in 0..3 {
        let (reopened, first) = Session::open(&path, 1).await?;
        if first.batches.first().map(|batch| batch.generation) != Some(1) {
            return Err("reopened app did not reset its generation".into());
        }
        reopened.close().await?;
    }
    Ok(())
}

#[test]
fn runtime_recovery_lengths_agent_and_repeated_start_stop() -> Result<(), String> {
    let path = if let Some(path) = std::env::var_os("LUI_NSH_TEST_LIBRARY") {
        PathBuf::from(path).to_string_lossy().into_owned()
    } else {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let build = Command::new("bash")
            .arg("tooling/build_nsh_todos.sh")
            .current_dir(root)
            .output()
            .map_err(|e| e.to_string())?;
        if !build.status.success() {
            return Err(String::from_utf8_lossy(&build.stderr).into_owned());
        }
        String::from_utf8(build.stdout)
            .map_err(|e| e.to_string())?
            .trim()
            .to_owned()
    };
    let mut app = Headless::start(EngineConfig::new(Root::new::<ProtocolProbe>(move || {
        ProbeProps {
            path: Prop::new(path.clone()),
        }
    })))
    .map_err(|e| e.to_string())?;
    app.wait_for("text:passed")
}
