//! App-owned content capture, without reading or activating the desktop.
//!
//! On macOS this draws the application's own NSView hierarchy into a bitmap.
//! It does not use WindowServer capture, screen-recording permission, synthetic
//! input, application activation or display-power APIs. System menus, other
//! windows and separately composited video/shader surfaces are outside this
//! content capture; it is not a picture of the desktop compositor's result.

/// A PNG of one application window's content, in backing-store pixels.
pub struct Capture {
    pub png: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

/// Captures the app's existing content while leaving screen/lock state alone.
#[cfg(target_os = "macos")]
pub async fn screenshot() -> Result<Capture, String> {
    let (sender, receiver) = tokio::sync::oneshot::channel();
    dispatch2::DispatchQueue::main().exec_async(move || {
        let result = nsh_platform_macos::objc2::rc::autoreleasepool(|_| capture_on_main());
        let _ = sender.send(result);
    });
    receiver
        .await
        .map_err(|_| "native content capture did not reply".to_owned())?
}

#[cfg(target_os = "macos")]
fn capture_on_main() -> Result<Capture, String> {
    use nsh_platform_macos::{
        objc2::{MainThreadMarker, runtime::AnyObject},
        objc2_app_kit::{NSApplication, NSBitmapImageFileType, NSBitmapImageRepPropertyKey},
        objc2_foundation::NSDictionary,
    };
    let main =
        MainThreadMarker::new().ok_or("native content capture requires AppKit's main thread")?;
    let app = NSApplication::sharedApplication(main);
    let window = content_window(&app)?;
    let view = window
        .contentView()
        .ok_or("the application window has no content view")?;
    let bounds = view.bounds();
    if !bounds.size.width.is_finite()
        || !bounds.size.height.is_finite()
        || bounds.size.width <= 0.0
        || bounds.size.height <= 0.0
    {
        return Err("the application content has no drawable bounds".into());
    }
    let bitmap = view
        .bitmapImageRepForCachingDisplayInRect(bounds)
        .ok_or("AppKit could not allocate the content bitmap")?;
    view.cacheDisplayInRect_toBitmapImageRep(bounds, &bitmap);
    let width = u32::try_from(bitmap.pixelsWide()).map_err(|_| "invalid content bitmap width")?;
    let height = u32::try_from(bitmap.pixelsHigh()).map_err(|_| "invalid content bitmap height")?;
    if width == 0 || height == 0 {
        return Err("AppKit produced an empty content bitmap".into());
    }
    let properties = NSDictionary::<NSBitmapImageRepPropertyKey, AnyObject>::new();
    // SAFETY: AppKit accepts an empty PNG-property dictionary. The retained
    // bitmap and dictionary outlive encoding; bytes are copied before return.
    let png = unsafe {
        bitmap.representationUsingType_properties(NSBitmapImageFileType::PNG, &properties)
    }
    .ok_or("AppKit could not encode the content bitmap as PNG")?
    .to_vec();
    Ok(Capture { png, width, height })
}

/// Reads only this process's existing windows, on the capture's main queue.
/// Titles, user content, addresses and other applications are never inspected.
#[cfg(target_os = "macos")]
fn window_diagnostics(app: &nsh_platform_macos::objc2_app_kit::NSApplication) -> serde_json::Value {
    let windows = app.windows();
    let sample: Vec<_> = windows
        .iter()
        .take(8)
        .enumerate()
        .map(|(index, window)| {
            let content = window.contentView();
            let bounds = content.as_ref().map(|view| {
                let bounds = view.bounds();
                let finite = [
                    bounds.origin.x,
                    bounds.origin.y,
                    bounds.size.width,
                    bounds.size.height,
                ]
                .iter()
                .all(|value| value.is_finite());
                serde_json::json!({"x":bounds.origin.x,"y":bounds.origin.y,
                "width":bounds.size.width,"height":bounds.size.height,
                "finite":finite})
            });
            serde_json::json!({"index":index,"visible":window.isVisible(),
            "miniaturized":window.isMiniaturized(),"main":window.isMainWindow(),
            "key":window.isKeyWindow(),"hasContentView":content.is_some(),"contentBounds":bounds})
        })
        .collect();
    serde_json::json!({"windowCount":windows.len(),"sampleLimit":8,
        "truncated":windows.len()>8,"windows":sample,
        "applicationActive":app.isActive(),"applicationHidden":app.isHidden(),
        "activationPolicy":app.activationPolicy().0,
        "hasMainWindow":app.mainWindow().is_some(),"hasKeyWindow":app.keyWindow().is_some()})
}

/// Other native backends require their own app-content capture implementation.
#[cfg(not(target_os = "macos"))]
pub async fn screenshot() -> Result<Capture, String> {
    Err("in-process native content capture is currently supported only on macOS".into())
}

/// Bounded read-only inspection of one renderer-owned native view. This reports
/// AppKit coordinates, including a modal's native animation shift. It does not
/// assert painted pixels, animation completion, keyboard focus or visibility on
/// the desktop. No window is created, reordered, activated or modified.
#[cfg(target_os = "macos")]
pub async fn view_bounds(test_id: String) -> Result<serde_json::Value, String> {
    validate_test_id(&test_id)?;
    let (sender, receiver) = tokio::sync::oneshot::channel();
    dispatch2::DispatchQueue::main().exec_async(move || {
        let result = nsh_platform_macos::objc2::rc::autoreleasepool(|_| bounds_on_main(&test_id));
        let _ = sender.send(result);
    });
    receiver
        .await
        .map_err(|_| "native view inspection did not reply".to_owned())?
}

#[cfg(not(target_os = "macos"))]
pub async fn view_bounds(_test_id: String) -> Result<serde_json::Value, String> {
    Err("own-view native bounds inspection is currently supported only on macOS".into())
}

#[cfg(any(test, target_os = "macos"))]
fn validate_test_id(test_id: &str) -> Result<(), String> {
    let id = test_id
        .strip_prefix("lui-")
        .ok_or("native bounds requires a renderer test ID")?;
    let parsed = id
        .parse::<u64>()
        .map_err(|_| "native bounds requires a renderer test ID")?;
    if parsed == 0 || parsed.to_string() != id {
        return Err("native bounds requires a canonical positive renderer test ID".into());
    }
    Ok(())
}

#[cfg(any(test, target_os = "macos"))]
fn intersects(a: [f64; 4], b: [f64; 4]) -> bool {
    a.iter().chain(b.iter()).all(|n| n.is_finite())
        && a[2] > 0.0
        && a[3] > 0.0
        && b[2] > 0.0
        && b[3] > 0.0
        && a[0] < b[0] + b[2]
        && a[0] + a[2] > b[0]
        && a[1] < b[1] + b[3]
        && a[1] + a[3] > b[1]
}

#[cfg(target_os = "macos")]
fn content_window(
    app: &nsh_platform_macos::objc2_app_kit::NSApplication,
) -> Result<
    nsh_platform_macos::objc2::rc::Retained<nsh_platform_macos::objc2_app_kit::NSWindow>,
    String,
> {
    // Background/locked apps need not have a main/key window. The fallback
    // consults only this process's windows, never the screen or another app.
    // Prefer the largest visible content window over transient small panels.
    app.mainWindow()
        .filter(|window| window.isVisible() && window.contentView().is_some())
        .or_else(|| {
            app.windows()
                .iter()
                .filter(|window| window.isVisible() && !window.isMiniaturized())
                .filter_map(|window| {
                    let bounds = window.contentView()?.bounds();
                    let area = bounds.size.width * bounds.size.height;
                    (area.is_finite() && area > 0.0).then_some((window, area))
                })
                .max_by(|(_, a), (_, b)| a.total_cmp(b))
                .map(|(window, _)| window)
        })
        .ok_or_else(|| {
            format!(
                "the application has no visible content window to capture; own-window diagnostics={}",
                window_diagnostics(&app)
            )
        })
}

#[cfg(target_os = "macos")]
fn bounds_on_main(test_id: &str) -> Result<serde_json::Value, String> {
    use nsh_platform_macos::{
        objc2::{MainThreadMarker, rc::Retained},
        objc2_app_kit::{NSAccessibility, NSApplication, NSView},
        objc2_foundation::NSRect,
    };
    const SCAN_LIMIT: usize = 8192;
    const ANCESTOR_LIMIT: usize = 12;
    fn rect(bounds: NSRect) -> [f64; 4] {
        [
            bounds.origin.x,
            bounds.origin.y,
            bounds.size.width,
            bounds.size.height,
        ]
    }
    let main =
        MainThreadMarker::new().ok_or("native view inspection requires AppKit's main thread")?;
    let app = NSApplication::sharedApplication(main);
    let window = content_window(&app)?;
    let content = window
        .contentView()
        .ok_or("the application window has no content view")?;
    let viewport = rect(content.bounds());
    let mut pending = vec![content.clone()];
    let mut scanned = 0;
    let mut found = None;
    while let Some(view) = pending.pop() {
        scanned += 1;
        if view
            .accessibilityIdentifier()
            .is_some_and(|id| id.to_string() == test_id)
        {
            found = Some(view);
            break;
        }
        // Keep both traversal work and queued retained views bounded.
        let children = view.subviews();
        let budget = SCAN_LIMIT.saturating_sub(scanned + pending.len());
        pending.extend(children.iter().take(budget));
        if scanned == SCAN_LIMIT {
            break;
        }
    }
    let mut ancestors = Vec::new();
    let mut current: Option<Retained<NSView>> = found.clone();
    let mut ancestry_truncated = false;
    while let Some(view) = current {
        // SAFETY: the retained view and its parent are read on AppKit's main thread.
        let parent = unsafe { view.superview() };
        let sibling_index = parent.as_ref().and_then(|parent| {
            parent
                .subviews()
                .iter()
                .position(|sibling| std::ptr::eq(&*sibling, &*view))
        });
        let converted = rect(view.convertRect_toView(view.bounds(), Some(&content)));
        ancestors.push(
            serde_json::json!({"bounds":rect(view.bounds()),"frame":rect(view.frame()),
            "contentBounds":converted,"hidden":view.isHidden(),
            "hiddenByAncestor":view.isHiddenOrHasHiddenAncestor(),"alpha":view.alphaValue(),
            "layerOpacity":view.layer().map(|layer|layer.opacity()),
            "siblingIndex":sibling_index,"siblingCount":parent.as_ref().map(|p|p.subviews().len()),
            "isContentRoot":std::ptr::eq(&*view,&*content)}),
        );
        if std::ptr::eq(&*view, &*content) {
            break;
        }
        if ancestors.len() == ANCESTOR_LIMIT {
            ancestry_truncated = parent.is_some();
            break;
        }
        current = parent;
    }
    let bounds = found
        .as_ref()
        .map(|view| rect(view.convertRect_toView(view.bounds(), Some(&content))));
    Ok(
        serde_json::json!({"testId":test_id,"present":found.is_some(),"viewport":viewport,
        "contentBounds":bounds,"intersectsViewport":bounds.is_some_and(|bounds|intersects(bounds,viewport)),
        "scannedViews":scanned,"scanLimit":SCAN_LIMIT,"scanTruncated":found.is_none() && scanned==SCAN_LIMIT,
        "ancestors":ancestors,"ancestorLimit":ANCESTOR_LIMIT,"ancestryTruncated":ancestry_truncated,
        "applicationActive":app.isActive(),"applicationHidden":app.isHidden(),
        "windowVisible":window.isVisible(),"windowKey":window.isKeyWindow(),
        "coordinateSpace":"AppKit window content; not Core layout or desktop screen"}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_bounds_restricts_the_lookup_to_canonical_renderer_ids() {
        for id in ["lui-1", "lui-337", "lui-18446744073709551615"] {
            validate_test_id(id).unwrap();
        }
        for id in [
            "",
            "input",
            "lui-0",
            "lui-01",
            "lui--1",
            "lui-+1",
            "lui-18446744073709551616",
        ] {
            assert!(validate_test_id(id).is_err(), "{id}");
        }
    }

    #[test]
    fn an_initial_modal_below_the_window_is_not_native_visible_geometry() {
        let viewport = [0.0, 0.0, 1440.0, 900.0];
        assert!(!intersects([0.0, 900.0, 1440.0, 900.0], viewport));
        assert!(intersects([0.0, 899.0, 1440.0, 900.0], viewport));
        assert!(intersects([0.0, 0.0, 1440.0, 900.0], viewport));
        assert!(!intersects([0.0, 0.0, 0.0, 900.0], viewport));
        assert!(!intersects([f64::NAN, 0.0, 1440.0, 900.0], viewport));
        assert!(!intersects([0.0, f64::INFINITY, 1440.0, 900.0], viewport));
    }
}
