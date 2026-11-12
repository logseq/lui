//! Explicit AppKit geometry qualification; only orders its own offscreen window back.
#[cfg(target_os = "macos")]
#[path = "../src/native_capture/geometry.rs"]
mod geometry;

#[cfg(target_os = "macos")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use nsh_platform_macos::{
        objc2::{MainThreadMarker, MainThreadOnly, define_class, msg_send, rc::Retained},
        objc2_app_kit::{
            NSApplication, NSBackingStoreType, NSResponder, NSView, NSWindow, NSWindowStyleMask,
        },
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
    struct ProbeWindow(Retained<NSWindow>);
    impl Drop for ProbeWindow {
        fn drop(&mut self) {
            self.0.close();
        }
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
    fn describe(name: &str, view: &NSView, root: &NSView) -> serde_json::Value {
        fn rect(value: NSRect) -> [f64; 4] {
            [
                value.origin.x,
                value.origin.y,
                value.size.width,
                value.size.height,
            ]
        }
        let layer = view.layer().map(|layer| {
            let parent = layer.superlayer();
            let transform = layer.transform();
            let sublayer = layer.sublayerTransform();
            let origin = view.convertPointToLayer(view.bounds().origin);
            let in_root = root
                .layer()
                .map(|root| layer.convertPoint_toLayer(origin, Some(&root)));
            serde_json::json!({"bounds":rect(layer.bounds()),
                "position":[layer.position().x,layer.position().y],
                "anchor":[layer.anchorPoint().x,layer.anchorPoint().y],
                "flipped":layer.isGeometryFlipped(),"hasSuperlayer":parent.is_some(),
                "superlayerBounds":parent.as_ref().map(|layer|rect(layer.bounds())),
                "transformTranslation":[transform.m41,transform.m42],
                "sublayerTranslation":[sublayer.m41,sublayer.m42],
                "localOriginInLayer":[origin.x,origin.y],
                "localOriginInRootLayer":in_root.map(|point|[point.x,point.y])})
        });
        serde_json::json!({"name":name,"frame":rect(view.frame()),"bounds":rect(view.bounds()),
            "flipped":view.isFlipped(),"inWindow":view.window().is_some(),"layer":layer,
            "bareContentBounds":rect(view.convertRect_toView(view.bounds(),Some(root))),
            "mappedContentBounds":geometry::content_bounds(view,root)})
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
    // SAFETY: a private positive-size borderless AppKit window on its main
    // thread. It is retained, never made key/activated, and closes on scope exit.
    let window = ProbeWindow(unsafe {
        let window = NSWindow::initWithContentRect_styleMask_backing_defer(
            main.alloc(),
            rect(-10_000.0, -10_000.0, 800.0, 600.0),
            NSWindowStyleMask::Borderless,
            NSBackingStoreType::Buffered,
            false,
        );
        window.setReleasedWhenClosed(false);
        window
    });
    window.0.setContentView(Some(&root));
    // AppKit defers backing-layer attachment even after setContentView/layout
    // for a never-ordered window. Realize only this owned offscreen window;
    // neither activation nor a fabricated layer hierarchy can qualify mapping.
    window.0.orderBack(None);
    root.layoutSubtreeIfNeeded();
    window.0.displayIfNeeded();
    // AppKit can rewrite backing-layer geometry while attaching views. NSH
    // likewise reapplies its authored anchor/position after native attachment.
    for view in [&root, &scroll, &row] {
        let layer = view
            .layer()
            .ok_or("attached fixture lost its backing layer")?;
        layer.setAnchorPoint(NSPoint::new(0.0, 0.0));
        layer.setPosition(view.frame().origin);
    }
    eprintln!(
        "{}",
        serde_json::json!({"phase":"attached-before-scroll","views":[
        describe("root",&root,&root),describe("scroll",&scroll,&root),
        describe("row",&row,&root),describe("child",&child,&root)]})
    );
    let scroll_layer = scroll.layer().ok_or("scroll has no existing layer")?;
    let mut translation = scroll_layer.sublayerTransform();
    translation.m42 = -30_000.0;
    scroll_layer.setSublayerTransform(translation);
    eprintln!(
        "{}",
        serde_json::json!({"phase":"live-sublayer-scroll","views":[
        describe("root",&root,&root),describe("scroll",&scroll,&root),
        describe("row",&row,&root),describe("child",&child,&root)]})
    );
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
    let disconnected = flipped(main, rect(0.0, 0.0, 100.0, 100.0));
    let disconnected_child = flipped(main, rect(3.0, 4.0, 20.0, 20.0));
    disconnected.addSubview(&disconnected_child);
    if disconnected_child
        .layer()
        .is_none_or(|layer| layer.superlayer().is_some())
    {
        return Err("off-window fixture did not expose disconnected backing layers".into());
    }
    if geometry::content_bounds(&disconnected_child, &disconnected).is_ok() {
        return Err("disconnected backing layers produced misleading geometry".into());
    }
    println!(
        "{}",
        serde_json::json!({"ok":true,"qualification":"AppKit-model-layer-geometry",
        "liveSublayerScroll":live,"committedBoundsOrigin":true,"transformedFlippedAncestor":true,
        "childLayerBacked":child.layer().is_some(),
        "plainFixtureHasLayers":plain.layer().is_some() || plain_child.layer().is_some(),
        "plainAppKit":true,"outsideContentRejected":true,"disconnectedLayersRejected":true,
        "fixtureWindowVisible":window.0.isVisible()})
    );
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn main() -> std::process::ExitCode {
    eprintln!("The native bounds geometry probe requires macOS AppKit.");
    std::process::ExitCode::FAILURE
}
