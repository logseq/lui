//! Actual AppKit sheet/controller qualification in two private offscreen windows.
#[cfg(target_os = "macos")]
#[path = "../src/native_agent/dialogs/macos.rs"]
mod dialogs;

#[cfg(target_os = "macos")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use block2::RcBlock;
    use nsh_platform_macos::{
        objc2::{MainThreadMarker, MainThreadOnly, rc::Retained},
        objc2_app_kit::{
            NSAccessibility, NSAlert, NSAlertFirstButtonReturn, NSApplication, NSBackingStoreType,
            NSModalResponse, NSModalResponseCancel, NSView, NSWindow, NSWindowStyleMask,
        },
        objc2_foundation::{
            NSDate, NSDefaultRunLoopMode, NSPoint, NSRect, NSRunLoop, NSSize, NSString,
        },
    };
    use serde_json::Value;
    use std::{
        cell::Cell,
        rc::Rc,
        time::{Duration, Instant},
    };
    type Completion = Rc<Cell<Option<NSModalResponse>>>;

    struct Window(Retained<NSWindow>);
    impl Drop for Window {
        fn drop(&mut self) {
            self.0.close();
        }
    }
    fn window(main: MainThreadMarker, identifier: &str) -> (Window, Retained<NSView>) {
        let frame = NSRect::new(
            NSPoint::new(-10_000.0, -10_000.0),
            NSSize::new(420.0, 300.0),
        );
        // SAFETY: an owned private window created on AppKit's main thread. It is
        // retained and only ordered back offscreen, never activated or made key.
        let window = unsafe {
            let window = NSWindow::initWithContentRect_styleMask_backing_defer(
                main.alloc(),
                frame,
                NSWindowStyleMask::Borderless,
                NSBackingStoreType::Buffered,
                false,
            );
            window.setReleasedWhenClosed(false);
            window
        };
        let view = NSView::initWithFrame(
            main.alloc(),
            NSRect::new(NSPoint::new(0.0, 0.0), frame.size),
        );
        view.setAccessibilityIdentifier(Some(&NSString::from_str(identifier)));
        window.setContentView(Some(&view));
        window.orderBack(None);
        (Window(window), view)
    }
    fn until(mut completed: impl FnMut() -> bool) -> Result<(), String> {
        let deadline = Instant::now() + Duration::from_secs(5);
        let limit = NSDate::dateWithTimeIntervalSinceNow(5.0);
        while !completed() {
            if Instant::now() >= deadline {
                return Err("owned AppKit dialog completion timed out".into());
            }
            // SAFETY: Foundation's immutable standard run-loop mode. Pump only
            // this process until real completion, without sleeps or screen input.
            NSRunLoop::currentRunLoop().runMode_beforeDate(unsafe { NSDefaultRunLoopMode }, &limit);
        }
        Ok(())
    }
    fn show(
        main: MainThreadMarker,
        window: &NSWindow,
        duplicate: bool,
    ) -> Result<(Retained<NSAlert>, Completion), String> {
        let alert = NSAlert::new(main);
        alert.setMessageText(&NSString::from_str("Native update available"));
        alert.setInformativeText(&NSString::from_str(
            "An owned qualification update is ready.",
        ));
        alert.addButtonWithTitle(&NSString::from_str("Download"));
        alert.addButtonWithTitle(&NSString::from_str("Later"));
        if duplicate {
            alert.addButtonWithTitle(&NSString::from_str("Download"));
        }
        alert.layout();
        let completed = Rc::new(Cell::new(None));
        let answer = completed.clone();
        let handler = RcBlock::new(move |response: NSModalResponse| answer.set(Some(response)));
        alert.beginSheetModalForWindow_completionHandler(window, Some(&handler));
        until(|| window.attachedSheet().is_some() && alert.window().isVisible())?;
        Ok((alert, completed))
    }
    fn close(
        window: &NSWindow,
        alert: &NSAlert,
        completed: &Cell<Option<NSModalResponse>>,
    ) -> Result<(), String> {
        window.endSheet_returnCode(&alert.window(), NSModalResponseCancel);
        until(|| completed.get().is_some() && window.attachedSheet().is_none())
    }
    fn token(value: &Value) -> Result<&str, String> {
        value["token"]
            .as_str()
            .ok_or_else(|| format!("actual owned sheet was not inspected: {value}"))
    }
    fn refused(result: Result<(), String>, contains: &str) -> Result<(), String> {
        match result {
            Err(error) if error.contains(contains) => Ok(()),
            other => Err(format!("expected refusal {contains:?}, got {other:?}")),
        }
    }

    let main = MainThreadMarker::new().ok_or("probe must run on AppKit's main thread")?;
    let application = NSApplication::sharedApplication(main);
    let active_before = application.isActive();
    let (first, owner) = window(main, "dialog-probe-first");
    let (second, other_owner) = window(main, "dialog-probe-second");
    let mut state = dialogs::State::default();
    assert!(state.inspect("dialog-probe-first", main)?.is_null());

    let (alert, completed) = show(main, &first.0, false)?;
    let inspected = state.inspect("dialog-probe-first", main)?;
    assert!(
        inspected["texts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|text| text == "Native update available")
    );
    assert_eq!(inspected["buttons"].as_array().unwrap().len(), 2);
    let captured = token(&inspected)?.to_owned();
    refused(state.answer("stale-token", "Download"), "stale")?;
    refused(state.answer(&captured, "Missing"), "absent")?;
    assert!(completed.get().is_none());
    let download = alert.buttons().objectAtIndex(0);
    download.setEnabled(false);
    refused(state.answer(&captured, "Download"), "contents changed")?;
    let disabled = state.inspect("dialog-probe-first", main)?;
    refused(state.answer(token(&disabled)?, "Download"), "disabled")?;
    download.setEnabled(true);
    let enabled = state.inspect("dialog-probe-first", main)?;
    assert_ne!(token(&enabled)?, captured);
    refused(state.answer(&captured, "Download"), "stale")?;
    state.answer(token(&enabled)?, "Download")?;
    until(|| completed.get().is_some() && first.0.attachedSheet().is_none())?;
    assert_eq!(completed.get(), Some(NSAlertFirstButtonReturn));
    refused(state.answer(token(&enabled)?, "Download"), "consumed")?;

    let (duplicate, duplicate_done) = show(main, &first.0, true)?;
    let inspected = state.inspect("dialog-probe-first", main)?;
    refused(state.answer(token(&inspected)?, "Download"), "ambiguous")?;
    assert!(duplicate_done.get().is_none());
    close(&first.0, &duplicate, &duplicate_done)?;

    let (previous, previous_done) = show(main, &first.0, false)?;
    let previous_token = token(&state.inspect("dialog-probe-first", main)?)?.to_owned();
    close(&first.0, &previous, &previous_done)?;
    let (replacement, replacement_done) = show(main, &first.0, false)?;
    refused(
        state.answer(&previous_token, "Download"),
        "attachment changed",
    )?;
    let changed = state.inspect("dialog-probe-first", main)?;
    assert_ne!(token(&changed)?, previous_token);
    replacement.setInformativeText(&NSString::from_str("A different update offer."));
    replacement.layout();
    refused(
        state.answer(token(&changed)?, "Download"),
        "contents changed",
    )?;
    let current = state.inspect("dialog-probe-first", main)?;
    first.0.setContentView(None);
    refused(
        state.answer(token(&current)?, "Download"),
        "attachment changed",
    )?;
    first.0.setContentView(Some(&owner));
    close(&first.0, &replacement, &replacement_done)?;

    let (_other, other_done) = show(main, &second.0, false)?;
    assert!(
        state.inspect("dialog-probe-first", main)?.is_null(),
        "another own window cannot be adopted"
    );
    refused(state.answer(&previous_token, "Download"), "consumed")?;
    other_owner.setAccessibilityIdentifier(Some(&NSString::from_str("dialog-probe-first")));
    assert!(
        state
            .inspect("dialog-probe-first", main)
            .unwrap_err()
            .contains("ambiguous")
    );
    other_owner.setAccessibilityIdentifier(Some(&NSString::from_str("dialog-probe-second")));
    let actual_other = state.inspect("dialog-probe-second", main)?;
    state.answer(token(&actual_other)?, "Later")?;
    until(|| other_done.get().is_some() && second.0.attachedSheet().is_none())?;
    assert!(other_done.get().is_some());
    assert_eq!(
        application.isActive(),
        active_before,
        "probe never activates its application"
    );
    println!(
        "{}",
        serde_json::json!({"ok":true,"qualification":"actual-AppKit-owned-sheet-controller",
        "normalCompletion":true,"staleToken":true,"duplicateAnswer":true,"replacedSheet":true,
        "changedContents":true,"disabledButton":true,"ambiguousButton":true,"retiredNativeOwner":true,
        "wrongOwnWindow":true,"ambiguousOwner":true,"activation":"native-controller","hardwareInput":false})
    );
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn main() -> std::process::ExitCode {
    eprintln!("The native dialog probe requires macOS AppKit.");
    std::process::ExitCode::FAILURE
}
