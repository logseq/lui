//! Explicit AppKit geometry qualification; creates no window or desktop input.
#[cfg(target_os = "macos")]
#[path = "../src/native_capture/geometry.rs"]
mod geometry;

#[cfg(target_os = "macos")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use nsh_platform_macos::{
        objc2::{MainThreadMarker, define_class, msg_send, rc::Retained},
        objc2_app_kit::{NSApplication, NSResponder, NSView},
        objc2_foundation::{NSObject, NSObjectProtocol, NSPoint, NSRect, NSSize},
    };
    define_class!(
        #[unsafe(super(NSView, NSResponder, NSObject))]
        #[thread_kind = MainThreadOnly]
        #[ivars = ()]
        #[name = "LuiNativeBoundsProbeFlippedView"]
        struct FlippedView;
        unsafe impl NSObjectProtocol for FlippedView {}
        impl FlippedView {
            #[unsafe(method(isFlipped))]
            fn is_flipped(&self) -> bool { true }
        }
    );
    fn rect(x: f64, y: f64, width: f64, height: f64) -> NSRect {
        NSRect::new(NSPoint::new(x, y), NSSize::new(width, height))
    }
    fn flipped(main: MainThreadMarker, frame: NSRect) -> Retained<FlippedView> {
        let view = main.alloc::<FlippedView>().set_ivars(());
        // SAFETY: NSView's designated initializer on AppKit's main thread.
        let view: Retained<FlippedView> = unsafe { msg_send![super(view), initWithFrame: frame] };
        view.setWantsLayer(true);
        let layer = view.layer().expect("authored layer-backed fixture");
        layer.setAnchorPoint(NSPoint::new(0.0, 0.0));
        layer.setPosition(frame.origin);
        view
    }
    fn expect(actual: [f64; 4], expected: [f64; 4]) -> Result<(), String> {
        if actual
            .iter()
            .zip(expected)
            .all(|(a, b)| (a - b).abs() < 0.01)
        {
            Ok(())
        } else {
            Err(format!(
                "native geometry {actual:?} differs from authored frame {expected:?}"
            ))
        }
    }
    let main = MainThreadMarker::new().ok_or("probe must run on AppKit's main thread")?;
    let _application = NSApplication::sharedApplication(main);
    let root = flipped(main, rect(0.0, 0.0, 800.0, 600.0));
    let scroll = flipped(main, rect(20.0, 100.0, 200.0, 180.0));
    let row = flipped(main, rect(0.0, 30_272.0, 180.0, 44.0));
    let child = NSView::initWithFrame(main.alloc(), rect(10.0, 4.0, 36.0, 36.0));
    root.addSubview(&scroll);
    scroll.addSubview(&row);
    row.addSubview(&child);
    let scroll_layer = scroll.layer().ok_or("scroll has no existing layer")?;
    let mut translation = scroll_layer.sublayerTransform();
    translation.m42 = -30_000.0;
    scroll_layer.setSublayerTransform(translation);
    let live = geometry::content_bounds(&child, &root)?;
    expect(live, [30.0, 376.0, 36.0, 36.0])?;
    let bare = child.convertRect_toView(child.bounds(), Some(&root));
    if (bare.origin.y - live[1]).abs() < 1.0 {
        return Err("fixture did not expose bare AppKit's omitted sublayer translation".into());
    }
    translation.m42 = 0.0;
    scroll_layer.setSublayerTransform(translation);
    scroll.setBoundsOrigin(NSPoint::new(0.0, 30_000.0));
    expect(geometry::content_bounds(&child, &root)?, live)?;
    let row_layer = row.layer().ok_or("row has no existing layer")?;
    let mut transform = row_layer.transform();
    transform.m41 = 12.0;
    transform.m42 = -20.0;
    row_layer.setTransform(transform);
    expect(
        geometry::content_bounds(&child, &root)?,
        [42.0, 356.0, 36.0, 36.0],
    )?;

    let plain = NSView::initWithFrame(main.alloc(), rect(0.0, 0.0, 200.0, 100.0));
    let plain_child = NSView::initWithFrame(main.alloc(), rect(7.0, 13.0, 20.0, 30.0));
    plain.addSubview(&plain_child);
    expect(
        geometry::content_bounds(&plain_child, &plain)?,
        [7.0, 13.0, 20.0, 30.0],
    )?;
    if geometry::content_bounds(&plain_child, &root).is_ok() {
        return Err("detached native hierarchy was accepted".into());
    }
    println!(
        "{}",
        serde_json::json!({"ok":true,"qualification":"AppKit-model-layer-geometry",
        "liveSublayerScroll":live,"committedBoundsOrigin":true,"transformedFlippedAncestor":true,
        "childLayerBacked":child.layer().is_some(),
        "plainFixtureHasLayers":plain.layer().is_some() || plain_child.layer().is_some(),
        "plainAppKit":true,"outsideContentRejected":true})
    );
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn main() -> std::process::ExitCode {
    eprintln!("The native bounds geometry probe requires macOS AppKit.");
    std::process::ExitCode::FAILURE
}
