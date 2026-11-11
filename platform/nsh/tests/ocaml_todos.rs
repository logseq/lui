//! Exercises the real OCaml runtime, C ABI, Rust adapter and NSH engine.
use lui_nsh::app::{Desktop, DesktopProps};
use nsh_core::{
    element::Prop,
    geometry::{Points, Size},
};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use std::{
    io::{BufRead, BufReader, Write},
    net::{TcpListener, TcpStream},
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn library() -> String {
    if let Some(path) = std::env::var_os("LUI_NSH_TEST_LIBRARY") {
        return PathBuf::from(path).to_string_lossy().into_owned();
    }
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let result = Command::new("bash")
        .arg("tooling/build_nsh_todos.sh")
        .current_dir(root)
        .output()
        .expect("build real OCaml Todos");
    assert!(
        result.status.success(),
        "OCaml build failed: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    String::from_utf8(result.stdout)
        .expect("build artifact path")
        .trim()
        .to_owned()
}

fn start(library: String, agent_listen: String) -> Headless {
    Headless::start(EngineConfig {
        viewport: Size::new(Points(1000.0), Points(800.0)),
        ..EngineConfig::new(Root::new::<Desktop>(move || {
            let mut props = DesktopProps::default();
            props.library = Prop::new(library.clone());
            props.agent_listen = Prop::new(agent_listen.clone());
            props
        }))
    })
    .expect("start the real NSH engine")
}

#[test]
fn real_ocaml_edits_and_keyed_moves_keep_the_editor() -> Result<(), String> {
    let library = library();
    let reservation = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let agent_address = reservation.local_addr().map_err(|e| e.to_string())?;
    drop(reservation);
    let mut app = start(library.clone(), agent_address.to_string());
    if let Err(error) = app.wait_for("text:Todos") {
        eprintln!("nodes: {:?}", app.screen().layout_nodes());
        return Err(error);
    }
    let editor = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.kind == nsh_core::ViewKind::Input)
        .ok_or("missing native editor")?
        .id;
    app.type_text("label:New todo", "Native 中文")?;
    app.press("text:Add")?;
    app.wait_for("text:[ ] Native 中文")?;
    app.wait_for("text:1 remaining / 1 total")?;
    assert!(
        app.screen()
            .layout_nodes()
            .iter()
            .any(|node| node.id == editor),
        "property and structural patches recreated the editor"
    );
    app.type_text("label:New todo", "Second")?;
    app.submit("label:New todo")?;
    app.wait_for("text:2 remaining / 2 total")?;
    app.press("text:Up >> nth=1")?;
    app.wait_until("keyed row reorder", Duration::from_secs(3), |screen| {
        let texts = screen.texts();
        texts.iter().position(|text| *text == "[ ] Second")
            < texts.iter().position(|text| *text == "[ ] Native 中文")
    })?;
    app.press("text:Done >> nth=0")?;
    app.wait_for("text:1 remaining / 2 total")?;
    app.press("text:Delete >> nth=0")?;
    app.wait_for("text:1 remaining / 1 total")?;
    assert!(
        app.screen()
            .layout_nodes()
            .iter()
            .any(|node| node.id == editor),
        "row move/delete replaced an unrelated editor"
    );
    assert_eq!(app.screen().count("id:lui-backend-error")?, 0);
    let stream = TcpStream::connect(agent_address).map_err(|e| e.to_string())?;
    stream
        .set_read_timeout(Some(Duration::from_secs(3)))
        .map_err(|e| e.to_string())?;
    let mut agent = BufReader::new(stream);
    let mut request = |request: serde_json::Value| -> Result<serde_json::Value, String> {
        writeln!(agent.get_mut(), "{request}").map_err(|e| e.to_string())?;
        let mut response = String::new();
        agent.read_line(&mut response).map_err(|e| e.to_string())?;
        let response: serde_json::Value =
            serde_json::from_str(&response).map_err(|e| e.to_string())?;
        if response["ok"] != true {
            return Err(format!("agent request failed: {response}"));
        }
        Ok(response)
    };
    let hello = request(serde_json::json!({"op":"hello"}))?;
    assert_eq!(hello["protocol"], "lui-agent");
    request(serde_json::json!({"op":"type","selector":"kind:text-field","text":"Agent item"}))?;
    request(serde_json::json!({"op":"press","selector":"text:Add"}))?;
    app.wait_for("text:[ ] Agent item")?;
    app.wait_for("text:2 remaining / 2 total")?;
    assert_eq!(app.screen().count("id:lui-backend-error")?, 0);
    drop(app);
    let mut closed = String::new();
    match agent.read_line(&mut closed) {
        Ok(0) => {}
        Err(error)
            if matches!(
                error.kind(),
                std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionAborted
            ) => {}
        result => {
            return Err(format!(
                "closed surface retained its agent connection: {result:?}"
            ));
        }
    }
    let mut reopened = start(library, String::new());
    reopened.wait_for("text:0 remaining / 0 total")?;
    assert_eq!(reopened.screen().count("id:lui-backend-error")?, 0);
    Ok(())
}
