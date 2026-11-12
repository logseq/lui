//! ABI-only native library qualification, separate from actual OCaml/Logseq gates.
#![cfg(unix)]
use lui_nsh::runtime::{ApplicationMessage, BridgeConfig, Event, PlatformEvent, Session};
use nsh_core::prelude::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use std::{path::PathBuf, process::Command};

#[derive(Clone, PartialEq, Props)]
struct ProbeProps {
    path: Prop<String>,
}
#[component]
fn LogseqProbe(props: ProbeProps) -> impl IntoElement {
    let status = signal("pending".to_owned());
    let path = props.path.get_untracked();
    spawn(async move {
        status.set(match exercise(path).await {
            Ok(()) => "passed".into(),
            Err(e) => e,
        });
    });
    text(move || status.get())
}
async fn exercise(path: String) -> Result<(), String> {
    let config = BridgeConfig::Logseq {
        payload: r#"{"paintsCaret":false}"#.into(),
    };
    let (session, initial) = Session::open_with_config(&path, 1, config.clone()).await?;
    assert_eq!(initial.root, 1);
    assert!(initial.batches.is_empty());
    assert!(initial.next_delay.is_none());
    let messages = initial.messages.ok_or("missing ordered startup messages")?;
    assert!(
        matches!(&messages[..], [ApplicationMessage::PlatformRequest(request), ApplicationMessage::Batch(batch)]
        if request.operation == "app-icons" && request.payload.contains("<svg/>") && batch.generation == 1)
    );
    // A foreign C thread signaled before START returned. Notify retains the wake.
    session.woken().await;
    let pumped = session.pump().await?;
    let messages = pumped.messages.ok_or("missing ordered pump messages")?;
    assert!(
        matches!(&messages[..], [ApplicationMessage::Batch(batch), ApplicationMessage::PlatformRequest(request)]
        if batch.generation == 2 && request.operation == "measure-node" && request.payload == r##"{"ref":"#sidebar"}"##)
    );
    let reply = session
        .platform_event(PlatformEvent {
            operation: "node-rect".into(),
            payload: "A\0中".into(),
        })
        .await?;
    assert!(
        matches!(reply.messages.as_deref(), Some([ApplicationMessage::Batch(batch)]) if batch.generation == 3)
    );
    let recovery = session
        .platform_event(PlatformEvent {
            operation: "invalid".into(),
            payload: "".into(),
        })
        .await?;
    assert!(
        matches!(recovery.messages.as_deref(), Some([ApplicationMessage::Snapshot(batch)]) if batch.generation == 3)
    );
    let snapshot = session
        .editor_snapshot("block\0id".into())
        .await?
        .ok_or("missing active editor")?;
    assert_eq!(snapshot.source, "A中");
    assert_eq!((snapshot.anchor, snapshot.caret), (1, 4));
    assert!(session.editor_snapshot("inactive".into()).await?.is_none());
    let agent = session
        .agent(r#"{"op":"hello","probe":"中"}"#.into())
        .await?;
    let answer: serde_json::Value =
        serde_json::from_str(agent.agent.as_deref().ok_or("missing agent reply")?)
            .map_err(|error| error.to_string())?;
    assert_eq!(answer["host"], "logseq-native");
    assert!(
        matches!(agent.messages.as_deref(), Some([ApplicationMessage::Batch(batch), ApplicationMessage::PlatformRequest(request)])
            if batch.generation == 4 && request.operation == "agent-probe")
    );
    // The existing native bridge must receive the exact checked value and all
    // four physical modifier bits, on its owning worker.
    session
        .dispatch(Event::ToggleDetail {
            node: 29,
            checked: true,
            modifiers: 15,
        })
        .await?;
    assert!(
        session
            .dispatch(Event::ToggleDetail {
                node: 29,
                checked: true,
                modifiers: 2
            })
            .await
            .is_err()
    );
    assert!(session.tick().await.is_err());
    assert!(session.pause(true).await.is_err());
    assert!(session.advance(1.0).await.is_err());
    assert!(
        session
            .dispatch(Event::FocusWithin {
                node: 1,
                within: true
            })
            .await
            .is_err()
    );
    session.close().await?;
    assert!(session.pump().await.is_err());
    assert!(Session::open(&path, 1).await.is_err());
    let (reopened, initial) = Session::open_with_config(path, 1, config).await?;
    assert!(
        matches!(initial.messages.as_deref(), Some([ApplicationMessage::PlatformRequest(_), ApplicationMessage::Batch(batch)]) if batch.generation == 1)
    );
    reopened.close().await?;
    Ok(())
}
#[test]
fn explicit_logseq_start_wakeup_services_and_same_worker() -> Result<(), String> {
    let directory = std::env::temp_dir().join(format!("lui-logseq-driver-{}", std::process::id()));
    std::fs::create_dir_all(&directory).map_err(|e| e.to_string())?;
    let library = directory.join(if cfg!(target_os = "macos") {
        "driver.dylib"
    } else {
        "driver.so"
    });
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/logseq_driver.c");
    let output = Command::new("cc")
        .args([
            "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC", "-pthread",
        ])
        .arg(source)
        .arg("-o")
        .arg(&library)
        .output()
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned());
    }
    let path = library.to_string_lossy().into_owned();
    let mut app = Headless::start(EngineConfig::new(Root::new::<LogseqProbe>(move || {
        ProbeProps {
            path: Prop::new(path.clone()),
        }
    })))
    .map_err(|e| e.to_string())?;
    let result = app.wait_for("text:passed");
    std::fs::remove_dir_all(directory).map_err(|e| e.to_string())?;
    result
}
