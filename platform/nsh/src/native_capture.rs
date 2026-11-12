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
    // Background/locked apps need not have a main/key window. The fallback
    // consults only this process's windows, never the screen or another app.
    // Prefer the largest visible content window over transient small panels.
    let window = app
        .mainWindow()
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
        })?;
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
                serde_json::json!({"x":bounds.origin.x,"y":bounds.origin.y,
                "width":bounds.size.width,"height":bounds.size.height,
                "finite":[bounds.origin.x,bounds.origin.y,bounds.size.width,bounds.size.height]
                    .iter().all(|value|value.is_finite())})
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
