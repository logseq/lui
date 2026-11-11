//! Real OCaml sparse rows through the public native ABI, NSH engine and agent.
use lui_nsh::app::{Desktop, DesktopProps};
use nsh_core::{
    element::Prop,
    geometry::{Points, Size},
    platform::{Idiom, Os},
};
use nsh_engine::{EngineConfig, Environment, Root};
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    io::{BufRead, BufReader, Write},
    net::{SocketAddr, TcpListener, TcpStream},
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

fn library() -> Result<String, String> {
    if let Some(path) = std::env::var_os("LUI_NSH_VIRTUAL_LIBRARY") {
        return Ok(PathBuf::from(path).to_string_lossy().into_owned());
    }
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/build_virtual.py");
    let result = Command::new("python3")
        .arg(fixture)
        .output()
        .map_err(|error| error.to_string())?;
    if !result.status.success() {
        return Err(format!(
            "OCaml virtual fixture build failed: {}",
            String::from_utf8_lossy(&result.stderr)
        ));
    }
    String::from_utf8(result.stdout)
        .map(|path| path.trim().to_owned())
        .map_err(|error| error.to_string())
}

struct Agent(BufReader<TcpStream>);
impl Agent {
    fn connect(address: SocketAddr) -> Result<Self, String> {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            match TcpStream::connect(address) {
                Ok(stream) => {
                    stream
                        .set_read_timeout(Some(Duration::from_secs(5)))
                        .map_err(|error| error.to_string())?;
                    stream
                        .set_write_timeout(Some(Duration::from_secs(5)))
                        .map_err(|error| error.to_string())?;
                    return Ok(Self(BufReader::new(stream)));
                }
                Err(error) if Instant::now() >= deadline => return Err(error.to_string()),
                Err(_) => std::thread::sleep(Duration::from_millis(10)),
            }
        }
    }
    fn request(&mut self, request: Value) -> Result<Value, String> {
        let stream = self.0.get_mut();
        stream
            .write_all(request.to_string().as_bytes())
            .and_then(|()| stream.write_all(b"\n"))
            .map_err(|error| error.to_string())?;
        let mut response = String::new();
        if self
            .0
            .read_line(&mut response)
            .map_err(|error| error.to_string())?
            == 0
        {
            return Err("lui-agent closed its connection".into());
        }
        let response: Value = serde_json::from_str(&response).map_err(|error| error.to_string())?;
        if response["ok"] != true {
            return Err(format!("lui-agent refused {request}: {response}"));
        }
        Ok(response)
    }
    fn press(&mut self, identifier: &str) -> Result<(), String> {
        self.request(
            json!({"op":"press", "selector":format!("prop:accessibility-identifier={identifier}")}),
        )?;
        Ok(())
    }
    fn tree(&mut self) -> Result<Value, String> {
        self.request(json!({"op":"tree"}))
    }
}

fn start(library: String) -> Result<(Headless, Agent), String> {
    let reservation = TcpListener::bind("127.0.0.1:0").map_err(|error| error.to_string())?;
    let address = reservation
        .local_addr()
        .map_err(|error| error.to_string())?;
    drop(reservation);
    let mut app = Headless::start(EngineConfig {
        environment: Environment {
            os: Os::Linux,
            idiom: Idiom::Desktop,
            ..Default::default()
        },
        viewport: Size::new(Points(1000.0), Points(800.0)),
        ..EngineConfig::new(Root::new::<Desktop>(move || {
            let mut props = DesktopProps::default();
            props.library = Prop::new(library.clone());
            props.agent_listen = Prop::new(address.to_string());
            props
        }))
    })
    .map_err(|error| error.to_string())?;
    app.wait_for("text:Sparse virtual qualification")?;
    let mut agent = Agent::connect(address)?;
    let hello = agent.request(json!({"op":"hello"}))?;
    assert_eq!(hello["protocol"], "lui-agent");
    Ok((app, agent))
}

fn nodes(tree: &Value) -> Vec<&Value> {
    let mut pending: Vec<_> = tree["nodes"].as_array().unwrap().iter().collect();
    let mut nodes = Vec::new();
    while let Some(node) = pending.pop() {
        nodes.push(node);
        if let Some(children) = node["children"].as_array() {
            pending.extend(children);
        }
    }
    nodes
}
fn identified<'a>(tree: &'a Value, identifier: &str) -> Option<&'a Value> {
    nodes(tree)
        .into_iter()
        .find(|node| node["props"]["accessibility-identifier"] == identifier)
}
fn status(tree: &Value) -> &str {
    identified(tree, "status")
        .and_then(|node| node["props"]["text"].as_str())
        .unwrap_or("")
}
fn indices(tree: &Value) -> Vec<usize> {
    identified(tree, "virtual-list")
        .and_then(|node| node["props"]["virtual-indices"].as_str())
        .map(|indices| serde_json::from_str(indices).expect("canonical sparse indices"))
        .unwrap_or_default()
}
fn completion(tree: &Value, token: usize) -> Option<(String, usize)> {
    status(tree)
        .split_once("completions=")?
        .1
        .split(',')
        .find_map(|entry| {
            let mut parts = entry.split(':');
            let found: usize = parts.next()?.parse().ok()?;
            let outcome = parts.next()?.to_owned();
            let count = parts.next()?.parse().ok()?;
            (found == token).then_some((outcome, count))
        })
}
fn native_id(app: &Headless, identifier: &str) -> Option<nsh_core::NodeId> {
    app.screen()
        .layout_nodes()
        .iter()
        .find(|node| node.test_id.as_deref() == Some(identifier))
        .map(|node| node.id)
}
fn wait_tree(
    app: &mut Headless,
    agent: &mut Agent,
    description: &str,
    predicate: impl Fn(&Value) -> bool,
) -> Result<Value, String> {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        app.wait(Duration::from_millis(16))?;
        let tree = agent.tree()?;
        if predicate(&tree) {
            return Ok(tree);
        }
        if Instant::now() >= deadline {
            return Err(format!(
                "{description} did not converge: {}; indices={:?}; native={:?}",
                status(&tree),
                indices(&tree),
                app.screen().texts()
            ));
        }
    }
}
fn wait_status(app: &mut Headless, agent: &mut Agent, expected: &str) -> Result<Value, String> {
    wait_tree(app, agent, expected, |tree| status(tree).contains(expected))
}
fn jump(
    app: &mut Headless,
    agent: &mut Agent,
    identifier: &str,
    token: &mut usize,
    outcome: &str,
) -> Result<Value, String> {
    *token += 1;
    agent.press(identifier)?;
    let tree = wait_tree(app, agent, "exactly one scroll completion", |tree| {
        completion(tree, *token).is_some()
    })?;
    assert_eq!(completion(&tree, *token), Some((outcome.to_owned(), 1)));
    app.wait(Duration::from_millis(40))?;
    let settled = agent.tree()?;
    assert_eq!(completion(&settled, *token), Some((outcome.to_owned(), 1)));
    Ok(settled)
}
fn bounded(app: &Headless, tree: &Value, count: usize) -> (usize, usize, usize) {
    let wire = nodes(tree).len();
    let native = app.screen().layout_nodes().len();
    let sparse = indices(tree);
    let list = identified(tree, "virtual-list").expect("mounted virtual list");
    assert_eq!(list["props"]["virtual-total-count"], count);
    assert_eq!(list["children"].as_array().unwrap().len(), sparse.len());
    assert!(
        sparse.len() <= 64,
        "source {count}: {} mounted rows",
        sparse.len()
    );
    assert!(wire <= 300, "source {count}: {wire} mounted LUI nodes");
    assert!(native <= 600, "source {count}: {native} native NSH nodes");
    assert_eq!(app.screen().count("id:lui-backend-error").unwrap(), 0);
    (wire, native, sparse.len())
}

#[test]
fn real_ocaml_sparse_rows_keep_focus_and_bound_both_trees_through_reorder() -> Result<(), String> {
    let library = library()?;
    let (mut app, mut agent) = start(library.clone())?;
    let baseline = wait_status(&mut app, &mut agent, "count=0 ")?;
    let baseline_wire = nodes(&baseline).len();
    let mut token = 0;
    let mut samples = BTreeMap::new();
    for count in [1_000, 100_000] {
        app.press(if count == 1_000 {
            "id:load-1k"
        } else {
            "id:load-100k"
        })?;
        wait_status(&mut app, &mut agent, &format!("count={count} "))?;
        app.wait_for("id:row-2-editor")?;
        app.type_text("id:row-2-editor", "!")?;
        let edited = wait_status(&mut app, &mut agent, "edited2=\"Row 2!\"")?;
        let wire_editor = identified(&edited, "row-2-editor").unwrap()["id"].clone();
        let native_editor = native_id(&app, "row-2-editor").ok_or("no native editor")?;
        let far = jump(&mut app, &mut agent, "jump-last", &mut token, "succeeded")?;
        assert!(
            indices(&far).contains(&2),
            "distant focused row was not pinned"
        );
        assert!(indices(&far).iter().any(|index| *index >= count - 10));
        app.wait_for(&format!("id:activate-{}", count - 1))?;
        let extent = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("virtual-list"))
            .and_then(|node| node.scroll)
            .and_then(|scroll| scroll.content_size)
            .ok_or("list did not expose its logical extent")?;
        assert!(
            extent.height.0 >= (count - 1) as f32 * 32.0,
            "source extent was truncated to sparse rows"
        );
        agent.press(&format!("activate-{}", count - 1))?;
        wait_status(&mut app, &mut agent, &format!("activated={}", count - 1))?;
        agent.press("reorder")?;
        let reordered = wait_status(&mut app, &mut agent, &format!("row2-index={}", count - 1))?;
        assert_eq!(
            identified(&reordered, "row-2-editor").unwrap()["id"],
            wire_editor
        );
        assert_eq!(native_id(&app, "row-2-editor"), Some(native_editor));
        // No selector refocuses the editor: this character proves native focus survived.
        app.press_key("z")?;
        wait_status(&mut app, &mut agent, "edited2=\"Row 2!z\"")?;
        jump(&mut app, &mut agent, "jump-top", &mut token, "succeeded")?;
        let pinned = wait_tree(
            &mut app,
            &mut agent,
            "distant reordered editor pin",
            |tree| indices(tree).contains(&(count - 1)),
        )?;
        samples.insert(count, bounded(&app, &pinned, count));
        // Focusing an input is a native keyboard step, not a pressable action.
        app.type_text("id:outside-editor", "")?;
        let released = wait_tree(
            &mut app,
            &mut agent,
            "stationary blur releases the distant editor",
            |tree| {
                identified(tree, "row-2-editor").is_none() && !indices(tree).contains(&(count - 1))
            },
        )?;
        bounded(&app, &released, count);
        jump(&mut app, &mut agent, "jump-last", &mut token, "succeeded")?;
        app.wait_for("id:row-2-editor")?;
        assert_eq!(app.screen().input_text("id:row-2-editor")?, Some("Row 2!z"));
        app.type_text("id:row-2-editor", "r")?;
        wait_status(&mut app, &mut agent, "edited2=\"Row 2!zr\"")?;
        agent.press("remove-row-2")?;
        let removed = wait_tree(&mut app, &mut agent, "focused row removal", |tree| {
            status(tree).contains(&format!("count={} ", count - 1))
                && identified(tree, "row-2-editor").is_none()
        })?;
        bounded(&app, &removed, count - 1);
        app.press_key("q")?;
        wait_status(&mut app, &mut agent, "edited2=\"Row 2!zr\"")?;
        agent.press("shrink")?;
        let shrunk = wait_status(&mut app, &mut agent, "count=20 ")?;
        bounded(&app, &shrunk, 20);
        jump(
            &mut app,
            &mut agent,
            "jump-missing",
            &mut token,
            "missing-target",
        )?;
        agent.press("clear")?;
        let cleared = wait_tree(
            &mut app,
            &mut agent,
            "Clear releases committed rows",
            |tree| {
                status(tree).contains("count=0 ")
                    && indices(tree).is_empty()
                    && nodes(tree).len() == baseline_wire
            },
        )?;
        bounded(&app, &cleared, 0);
    }
    let small = samples[&1_000];
    let large = samples[&100_000];
    assert!(
        large.0 <= small.0 + 12,
        "LUI nodes grew with source size: {samples:?}"
    );
    assert!(
        large.1 <= small.1 + 32,
        "NSH nodes grew with source size: {samples:?}"
    );
    for _cycle in 0..10 {
        agent.press("load-100k")?;
        wait_status(&mut app, &mut agent, "count=100000 ")?;
        let far = jump(&mut app, &mut agent, "jump-last", &mut token, "succeeded")?;
        bounded(&app, &far, 100_000);
        agent.press("clear")?;
        let cleared = wait_tree(
            &mut app,
            &mut agent,
            "repeat Clear returns LUI nodes to baseline",
            |tree| status(tree).contains("count=0 ") && nodes(tree).len() == baseline_wire,
        )?;
        bounded(&app, &cleared, 0);
    }
    eprintln!("real OCaml sparse source comparison (LUI, NSH, rows): {samples:?}");
    drop(agent);
    drop(app);
    let (mut reopened, mut agent) = start(library)?;
    let fresh = wait_status(&mut reopened, &mut agent, "count=0 ")?;
    assert_eq!(nodes(&fresh).len(), baseline_wire);
    assert!(status(&fresh).contains("edited2=\"Row 2\" token=0"));
    assert_eq!(bounded(&reopened, &fresh, 0).2, 0);
    Ok(())
}
