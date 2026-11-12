//! Private native fixture transport; each integration binary owns one OCaml library.
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
    io::{BufRead, BufReader, Write},
    net::{SocketAddr, TcpListener, TcpStream},
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

pub(super) fn fixture_library(
    fixture_name: &str,
    prepared_variable: &str,
) -> Result<String, String> {
    if let Some(path) = std::env::var_os(prepared_variable) {
        return Ok(PathBuf::from(path).to_string_lossy().into_owned());
    }
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/build_virtual.py");
    let result = Command::new("python3")
        .arg(fixture)
        .arg("--fixture")
        .arg(fixture_name)
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

pub(super) struct Agent(BufReader<TcpStream>);
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
    pub(super) fn request(&mut self, request: Value) -> Result<Value, String> {
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
    pub(super) fn tree(&mut self) -> Result<Value, String> {
        self.request(json!({"op":"tree"}))
    }
}

pub(super) fn start(library: String) -> Result<(Headless, Agent), String> {
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

pub(super) fn nodes(tree: &Value) -> Vec<&Value> {
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
pub(super) fn identified<'a>(tree: &'a Value, identifier: &str) -> Option<&'a Value> {
    nodes(tree)
        .into_iter()
        .find(|node| node["props"]["accessibility-identifier"] == identifier)
}
pub(super) fn status(tree: &Value) -> &str {
    identified(tree, "status")
        .and_then(|node| node["props"]["text"].as_str())
        .unwrap_or("")
}
pub(super) fn indices(tree: &Value) -> Vec<usize> {
    identified(tree, "virtual-list")
        .and_then(|node| node["props"]["virtual-indices"].as_str())
        .map(|indices| serde_json::from_str(indices).expect("canonical sparse indices"))
        .unwrap_or_default()
}
pub(super) fn native_id(app: &Headless, identifier: &str) -> Option<nsh_core::NodeId> {
    app.screen()
        .layout_nodes()
        .iter()
        .find(|node| node.test_id.as_deref() == Some(identifier))
        .map(|node| node.id)
}
pub(super) fn wait_tree(
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
pub(super) fn bounded(app: &Headless, tree: &Value, count: usize) -> (usize, usize, usize) {
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
