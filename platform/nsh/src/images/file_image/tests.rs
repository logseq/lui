use super::*;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::{collections::BTreeMap, rc::Rc, sync::Mutex};

fn node(path: &str, cap: u32) -> Node {
    Node {
        kind: "file-image".into(),
        props: serde_json::from_value(json!({"path":path, "max-pixel-size":cap})).unwrap(),
        ..Default::default()
    }
}

#[test]
fn local_paths_caps_and_file_fit_preserve_the_downstream_contract() {
    let image_node = node("/tmp/a b.png", 384);
    crate::contract::validate_node(&image_node).unwrap();
    validate(&image_node).unwrap();
    assert_eq!(Request::read(&image_node).cap, 384);
    #[cfg(unix)]
    assert_eq!(
        local_path("file:///tmp/a%20b.png").unwrap(),
        PathBuf::from("/tmp/a b.png")
    );
    #[cfg(windows)]
    assert_eq!(
        local_path("file:///C:/tmp/a%20b.png").unwrap(),
        PathBuf::from(r"C:\tmp\a b.png")
    );
    assert_eq!(
        local_path("Assets/a.png").unwrap(),
        PathBuf::from("Assets/a.png")
    );
    for remote in [
        "https://example.com/a.png",
        "data:image/png;base64,x",
        "asset:/a.png",
        "",
    ] {
        assert!(local_path(remote).is_err());
    }
    let mut default = image_node.clone();
    default.props.remove("max-pixel-size");
    assert_eq!(Request::read(&default).cap, 1024);
    assert_eq!(super::super::fit(&default), nsh_core::ResizeMode::Contain);
    default.props.insert("image-fit".into(), json!("fill"));
    assert_eq!(super::super::fit(&default), nsh_core::ResizeMode::Cover);
    for cap in [0, MAX_CAP + 1, u32::MAX] {
        assert!(validate(&node("Assets/a.png", cap)).is_err());
    }
    assert_eq!(scaled(u32::MAX, 1, 384).unwrap(), (384, 1));
    assert!(byte_len(u32::MAX, u32::MAX, MAX_CAP).is_err());
    assert!(
        Pixels {
            width: 2,
            height: 1,
            rgba: vec![0; 7]
        }
        .source(384)
        .is_err()
    );
}

/// A generated uncompressed 24-bit BMP needs no test decoder dependency.
fn bmp(width: u32, height: u32) -> Vec<u8> {
    let stride = (width as usize * 3 + 3) & !3;
    let mut bytes = vec![0; 54 + stride * height as usize];
    let size = bytes.len() as u32;
    bytes[0..2].copy_from_slice(b"BM");
    for (at, value) in [(2, size), (10, 54), (14, 40), (18, width), (22, height)] {
        bytes[at..at + 4].copy_from_slice(&value.to_le_bytes());
    }
    bytes[26..28].copy_from_slice(&1_u16.to_le_bytes());
    bytes[28..30].copy_from_slice(&24_u16.to_le_bytes());
    for row in bytes[54..].chunks_exact_mut(stride) {
        for pixel in row[..width as usize * 3].chunks_exact_mut(3) {
            pixel.copy_from_slice(&[0, 0, 255]);
        }
    }
    bytes
}

#[test]
fn native_thumbnail_is_bounded_preserves_aspect_and_does_not_upscale() {
    let pixels = native::decode(&bmp(2048, 1024), 384).unwrap();
    assert_eq!((pixels.width, pixels.height), (384, 192));
    assert_eq!(pixels.rgba.len(), 384 * 192 * 4);
    assert_eq!(&pixels.rgba[..4], &[255, 0, 0, 255]);
    let pixels = native::decode(&bmp(2, 1), 1024).unwrap();
    assert_eq!((pixels.width, pixels.height), (2, 1));
    assert!(native::decode(b"not an image", 384).is_err());
}

type Completion = tokio::sync::oneshot::Sender<Result<ImageSrc, String>>;
#[derive(Clone, Default)]
struct Probe {
    calls: Arc<Mutex<Vec<Request>>>,
    pending: Arc<Mutex<BTreeMap<String, Completion>>>,
}
impl Probe {
    fn complete(&self, path: &str, result: Result<ImageSrc, String>) -> bool {
        self.pending
            .lock()
            .unwrap()
            .remove(path)
            .unwrap()
            .send(result)
            .is_ok()
    }
}

#[component]
fn ResourceFixture() -> impl IntoElement {
    let probe = engine_context::<Probe>().unwrap();
    let state = signal(Arc::new(node("a.png", 384)));
    let child = signal(true);
    view()
        .child(when(child, move || {
            let probe = probe.clone();
            let source = Rc::new(source_with(state, move |request| {
                probe.calls.lock().unwrap().push(request.clone());
                let (send, receive) = tokio::sync::oneshot::channel();
                probe.pending.lock().unwrap().insert(request.path, send);
                async move { receive.await.map_err(|_| "cancelled".to_owned())? }
            }));
            let read = source.clone();
            view().child(image(move || source())).child(text(move || {
                let src = read();
                if src == ImageSrc::from("loaded-a") {
                    "loaded a"
                } else if src == ImageSrc::from("loaded-b") {
                    "loaded b"
                } else {
                    "empty image"
                }
            }))
        }))
        .child(
            nsh_base::button()
                .child(text("Change fit"))
                .on_press(move || {
                    let mut next = (*state.get_untracked()).clone();
                    next.props.insert("image-fit".into(), json!("fill"));
                    state.set(Arc::new(next));
                }),
        )
        .child(
            nsh_base::button()
                .child(text("Change path"))
                .on_press(move || state.set(Arc::new(node("b.png", 1024)))),
        )
        .child(
            nsh_base::button()
                .child(text("Remove image"))
                .on_press(move || child.set(false)),
        )
}

fn resource_app() -> (Headless, Probe) {
    let probe = Probe::default();
    let mut config = EngineConfig::new(Root::of::<ResourceFixture>());
    config.context = EngineContext::default().with(probe.clone());
    let mut app = Headless::start(config).unwrap();
    app.wait_for("text:empty image").unwrap();
    (app, probe)
}

#[test]
fn unchanged_request_does_not_reload_and_old_path_or_detached_completion_cannot_publish() {
    let (mut app, probe) = resource_app();
    assert_eq!(probe.calls.lock().unwrap().len(), 1);
    app.press("text:Change fit").unwrap();
    assert_eq!(probe.calls.lock().unwrap().len(), 1);
    app.press("text:Change path").unwrap();
    assert_eq!(probe.calls.lock().unwrap().len(), 2);
    assert!(!probe.complete("a.png", Ok(ImageSrc::from("loaded-a"))));
    assert!(probe.complete("b.png", Ok(ImageSrc::from("loaded-b"))));
    app.wait_for("text:loaded b").unwrap();
    app.press("text:Remove image").unwrap();
    assert_eq!(app.screen().count("text:loaded b").unwrap(), 0);
}

#[test]
fn failed_or_pending_replacement_clears_the_previous_file() {
    let (mut app, probe) = resource_app();
    assert!(probe.complete("a.png", Ok(ImageSrc::from("loaded-a"))));
    app.wait_for("text:loaded a").unwrap();
    app.press("text:Change path").unwrap();
    app.wait_for("text:empty image").unwrap();
    assert!(probe.complete("b.png", Err("missing file".into())));
    app.wait_for("text:empty image").unwrap();
    assert_eq!(app.screen().count("text:loaded a").unwrap(), 0);
}

#[test]
fn detached_owner_drops_its_pending_completion() {
    let (mut app, probe) = resource_app();
    app.press("text:Remove image").unwrap();
    assert!(!probe.complete("a.png", Ok(ImageSrc::from("loaded-a"))));
    assert_eq!(app.screen().count("text:loaded a").unwrap(), 0);
}
