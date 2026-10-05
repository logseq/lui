//! GPUI demo: hosts the OCaml gallery (`examples/components`) through the
//! platform/native C bridge inside a gpui-kit window.
//!
//! Requires the gallery dylib built by dune (see platform/gpui/README.md);
//! build.rs links `liblui_components.dylib` into this binary.
//!
//!   cargo run -p lui-demo
//!
//! Env: LUI_DEMO_PLATFORM overrides the OS code passed to lui_ocaml_start
//! (defaults to the build host's OS), LUI_DEMO_HOST overrides the host code
//! (defaults to 6 = GPUIHost).

use gpui_kit::component::Root;
use gpui_kit::gpui::{point, px, size, Bounds, WindowBounds, WindowOptions};
use gpui_kit::*;
use lui_core::bridge;
use lui_gpui::{drain_pending, LuiRootView, LuiShared};

fn main() {
    let platform = std::env::var("LUI_DEMO_PLATFORM")
        .ok()
        .and_then(|value| value.parse::<i32>().ok())
        .unwrap_or_else(bridge::current_os);
    let host = std::env::var("LUI_DEMO_HOST")
        .ok()
        .and_then(|value| value.parse::<i32>().ok())
        .unwrap_or(bridge::HOST_GPUI);

    // The thread calling lui_ocaml_start registers with the OCaml runtime —
    // all event entry points must stay on it, so this must be main.
    unsafe {
        bridge::start(platform, host);
    }

    let app = gpui_kit::application().with_assets(gpui_kit::assets::Assets);
    app.run(move |cx| {
        gpui_kit::init(cx);
        let shared = LuiShared::new();

        cx.spawn({
            let shared = shared.clone();
            async move |cx| {
                let options = WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(Bounds::new(
                        point(px(80.), px(80.)),
                        size(px(1100.), px(760.)),
                    ))),
                    ..Default::default()
                };
                cx.open_window(options, |window, cx| {
                    // The initial batch from lui_ocaml_start is already
                    // queued; apply it before first paint.
                    drain_pending(&shared, cx);
                    let root_id = unsafe { bridge::lui_ocaml_root_node() };
                    if root_id > 0 {
                        shared.borrow_mut().store.root = Some(root_id);
                    }
                    let view = cx.new(|_| LuiRootView::new(shared.clone()));
                    cx.new(|cx| Root::new(view, window, cx))
                })
                .expect("Failed to open window");
            }
        })
        .detach();
    });
}
