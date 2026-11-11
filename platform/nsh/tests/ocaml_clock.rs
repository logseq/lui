//! Real OCaml timers through the runtime worker and native desktop pump.
use lui_nsh::{
    app::{Desktop, DesktopProps},
    runtime::{Reply, Session},
    wire::Operation,
};
use nsh_core::{
    geometry::{Points, Size},
    prelude::*,
};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{path::PathBuf, process::Command, time::Duration};

fn library() -> Result<String, String> {
    if let Some(path) = std::env::var_os("LUI_NSH_CLOCK_LIBRARY") {
        return Ok(PathBuf::from(path).to_string_lossy().into_owned());
    }
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let build = Command::new("python3")
        .args([
            "platform/nsh/tests/fixtures/build_virtual.py",
            "--fixture",
            "clock",
        ])
        .current_dir(root)
        .output()
        .map_err(|error| error.to_string())?;
    if !build.status.success() {
        return Err(String::from_utf8_lossy(&build.stderr).into_owned());
    }
    Ok(String::from_utf8(build.stdout)
        .map_err(|error| error.to_string())?
        .trim()
        .to_owned())
}

fn delay(reply: &Reply, expected_ms: Option<u64>) {
    assert_eq!(
        reply.next_delay,
        expected_ms.map(Duration::from_millis),
        "unexpected next clock wakeup"
    );
    assert_eq!(reply.diagnostic, None);
}

async fn press(session: &Session, identifier: &str) -> Result<Reply, String> {
    let reply = session
        .agent(
            json!({"op":"press", "selector":format!("prop:accessibility-identifier={identifier}")})
                .to_string(),
        )
        .await?;
    let answer: Value = serde_json::from_str(reply.agent.as_deref().ok_or("missing agent reply")?)
        .map_err(|error| error.to_string())?;
    if answer["ok"] != true {
        return Err(format!("agent refused clock control: {answer}"));
    }
    Ok(reply)
}

async fn wire_state(session: &Session) -> Result<String, String> {
    let reply = session
        .agent(
            json!({"op":"prop", "selector":"prop:accessibility-identifier=clock-status", "name":"text"})
                .to_string(),
        )
        .await?;
    let answer: Value = serde_json::from_str(reply.agent.as_deref().ok_or("missing state reply")?)
        .map_err(|error| error.to_string())?;
    answer["value"]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| format!("missing clock state: {answer}"))
}

async fn runtime_contract(path: String) -> Result<(), String> {
    let (session, initial) = Session::open(&path, 1).await?;
    delay(&initial, None);
    press(&session, "clock-delayed").await?;
    nsh_core::element::timer(Duration::from_millis(160)).await;
    let resynchronized = session.resync().await?;
    assert!(resynchronized.batches.is_empty());
    let snapshot = resynchronized.snapshot.ok_or("missing recovery snapshot")?;
    assert!(
        snapshot.ops.iter().any(|operation| matches!(
            operation,
            Operation::SetProp { property, value, .. }
                if property == "text"
                    && value.as_str().is_some_and(|text| text.contains("delayed=1"))
        )),
        "authoritative snapshot omitted the timer fired immediately before resync"
    );
    assert!(wire_state(&session).await?.contains("delayed=1"));
    press(&session, "clock-cancel").await?;
    press(&session, "clock-delayed").await?;
    for _ in 0..6 {
        nsh_core::element::timer(Duration::from_millis(30)).await;
        press(&session, "clock-sample").await?;
    }
    assert!(
        wire_state(&session).await?.contains("delayed=1"),
        "continuous ordinary requests starved the pending timer"
    );
    press(&session, "clock-cancel").await?;
    nsh_core::element::timer(Duration::from_millis(250)).await;
    press(&session, "clock-delayed").await?;
    nsh_core::element::timer(Duration::from_millis(35)).await;
    session.tick().await?;
    assert!(
        wire_state(&session).await?.contains("delayed=0 nested=0"),
        "a newly scheduled timer caught up across idle wall time"
    );
    press(&session, "clock-cancel").await?;
    session.close().await?;
    let (session, _) = Session::open(&path, 1).await?;
    delay(&press(&session, "clock-delayed").await?, Some(120));
    delay(&session.pause(true).await?, None);
    delay(&session.advance(119.0).await?, None);
    assert!(wire_state(&session).await?.contains("delayed=0 nested=0"));
    delay(&session.advance(1.0).await?, None);
    assert!(wire_state(&session).await?.contains("delayed=1 nested=0"));
    delay(&session.advance(80.0).await?, None);
    assert!(
        wire_state(&session)
            .await?
            .contains("delayed=1 nested=1 repeat=0 pending=0")
    );
    delay(&session.pause(false).await?, None);

    delay(&press(&session, "clock-repeat").await?, Some(100));
    delay(&session.pause(true).await?, None);
    delay(&session.advance(250.0).await?, None);
    assert!(wire_state(&session).await?.contains("repeat=2 pending=1"));
    delay(&session.pause(false).await?, Some(50));
    delay(&session.advance(50.0).await?, None);
    assert!(wire_state(&session).await?.contains("repeat=3 pending=0"));

    delay(&press(&session, "clock-repeat").await?, Some(100));
    delay(&session.pause(true).await?, None);
    delay(&session.advance(100.0).await?, None);
    assert!(wire_state(&session).await?.contains("repeat=1 pending=1"));
    delay(&press(&session, "clock-cancel").await?, None);
    delay(&session.advance(1000.0).await?, None);
    assert!(wire_state(&session).await?.contains("repeat=1 pending=0"));
    delay(&session.pause(false).await?, None);

    delay(&press(&session, "clock-long").await?, Some(60_000));
    delay(&press(&session, "clock-cancel").await?, None);
    delay(&session.advance(60_100.0).await?, None);
    assert!(
        wire_state(&session)
            .await?
            .contains("delayed=0 nested=0 repeat=0 pending=0")
    );
    session.close().await?;
    assert!(session.tick().await.is_err());
    for _ in 0..3 {
        let (reopened, reply) = Session::open(&path, 1).await?;
        delay(&reply, None);
        assert!(
            wire_state(&reopened)
                .await?
                .contains("delayed=0 nested=0 repeat=0 pending=0")
        );
        reopened.close().await?;
    }
    Ok(())
}

#[derive(Clone, PartialEq, Props)]
struct ProbeProps {
    path: Prop<String>,
}

#[component]
fn ClockProbe(props: ProbeProps) -> impl IntoElement {
    let status = signal("clock-runtime-pending".to_owned());
    let path = props.path.get_untracked();
    spawn(async move {
        status.set(match runtime_contract(path).await {
            Ok(()) => "clock-runtime-passed".into(),
            Err(error) => format!("clock-runtime-failed: {error}"),
        });
    });
    text(move || status.get())
}

fn desktop(path: String) -> Result<Headless, String> {
    Headless::start(EngineConfig {
        viewport: Size::new(Points(1000.0), Points(800.0)),
        ..EngineConfig::new(Root::new::<Desktop>(move || {
            let mut props = DesktopProps::default();
            props.library = Prop::new(path.clone());
            props
        }))
    })
    .map_err(|error| error.to_string())
}

fn state(app: &Headless) -> Result<String, String> {
    app.screen()
        .texts()
        .into_iter()
        .find(|text| text.starts_with("clock-state "))
        .map(str::to_owned)
        .ok_or_else(|| format!("missing clock state: {:?}", app.screen().texts()))
}

fn wait_state(app: &mut Headless, expected: &str) -> Result<(), String> {
    app.wait_until(expected, Duration::from_secs(4), |screen| {
        screen.texts().iter().any(|text| text.contains(expected))
    })
}

fn stationary(app: &mut Headless) -> Result<(), String> {
    app.press("id:clock-sample")?;
    let before = state(app)?.split(" clock=").next().unwrap().to_owned();
    app.wait(Duration::from_millis(350))?;
    app.press("id:clock-sample")?;
    assert_eq!(
        state(app)?.split(" clock=").next().unwrap(),
        before,
        "idle application produced unexpected timer callbacks"
    );
    assert!(state(app)?.contains("pending=0"));
    Ok(())
}

#[test]
fn real_clock_delays_repeats_pauses_cancels_and_stops_while_idle() -> Result<(), String> {
    let path = library()?;
    let probe_path = path.clone();
    {
        let mut probe = Headless::start(EngineConfig::new(Root::new::<ClockProbe>(move || {
            ProbeProps {
                path: Prop::new(probe_path.clone()),
            }
        })))
        .map_err(|error| error.to_string())?;
        probe.wait_for("text:clock-runtime-passed")?;
    }

    let mut app = desktop(path.clone())?;
    app.wait_for("text:Clock qualification")?;
    app.press("id:clock-delayed")?;
    wait_state(&mut app, "delayed=1 nested=1 repeat=0 pending=0")?;
    app.press("id:clock-repeat")?;
    wait_state(&mut app, "repeat=3 pending=0")?;
    stationary(&mut app)?;
    app.press("id:clock-long")?;
    app.press("id:clock-cancel")?;
    wait_state(&mut app, "delayed=0 nested=0 repeat=0 pending=0")?;
    stationary(&mut app)?;

    app.press("id:clock-pause")?;
    app.press("id:clock-repeat")?;
    app.wait(Duration::from_millis(350))?;
    assert!(state(&app)?.contains("repeat=0 pending=1 paused=true"));
    app.press("id:clock-advance-250")?;
    wait_state(&mut app, "repeat=2 pending=1 paused=true")?;
    app.press("id:clock-advance-50")?;
    wait_state(&mut app, "repeat=3 pending=0 paused=true")?;

    app.press("id:clock-long")?;
    app.press("id:clock-cancel")?;
    app.press("id:clock-advance-60000")?;
    assert!(state(&app)?.contains("delayed=0 nested=0 repeat=0 pending=0"));
    app.press("id:clock-repeat")?;
    app.press("id:clock-advance-50")?;
    app.press("id:clock-resume")?;
    wait_state(&mut app, "repeat=3 pending=0 paused=false")?;
    stationary(&mut app)?;
    assert_eq!(app.screen().count("id:lui-backend-error")?, 0);

    // Leave a genuine scheduled host wakeup and scoped OCaml timer at teardown.
    app.press("id:clock-long")?;
    wait_state(&mut app, "delayed=0 nested=0 repeat=0 pending=1")?;
    drop(app);
    for _ in 0..3 {
        let mut reopened = desktop(path.clone())?;
        wait_state(&mut reopened, "delayed=0 nested=0 repeat=0 pending=0")?;
        stationary(&mut reopened)?;
    }
    Ok(())
}
