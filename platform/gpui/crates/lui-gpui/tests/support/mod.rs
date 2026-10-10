//! `lui_ocaml_*` stubs for integration-test binaries: in production these
//! symbols come from the OCaml runtime; here each stub records the call so
//! scenario steps can assert the exact event stream OCaml would observe.
//! This mirrors `src/ocaml_stubs.rs`, which only exists under `cfg(test)`
//! inside the lib and is not visible to `tests/` targets.
#![allow(dead_code)]

use std::ffi::{c_char, c_double, c_int, CStr};
use std::sync::Mutex;

/// One call the OCaml runtime would have received, in wire order.
#[derive(Debug, Clone, PartialEq)]
pub enum RecordedEvent {
    Press(i64),
    PressModifiers {
        node: i64,
        modifiers: i32,
    },
    Appear(i64),
    LongPress(i64),
    DoublePress(i64),
    PointerDown(i64),
    PointerUp(i64),
    PointerEnter(i64),
    PointerLeave(i64),
    TextChanged { node: i64, text: String },
    Submit(i64),
    Dismiss(i64),
    Picked { node: i64, payload: String },
    ToggleChanged { node: i64, checked: bool },
    RadioChanged(i64),
    SliderChanged { node: i64, fraction: f64 },
    PointerDetail {
        node: i64,
        x: f64,
        y: f64,
        modifiers: i32,
        button: i32,
        target_class: String,
    },
    ContextMenuPress {
        node: i64,
        x: f64,
        y: f64,
        modifiers: i32,
        button: i32,
        target_class: String,
    },
    ExtensionEvent {
        node: i64,
        identifier: String,
        name: String,
        json: String,
    },
    Load(i64),
    VisibleRange { node: i64, first: i64, last: i64 },
    ScrollCompleted { node: i64, token: i64, outcome: String },
}

static EVENTS: Mutex<Vec<RecordedEvent>> = Mutex::new(Vec::new());

fn record(event: RecordedEvent) {
    if let Ok(mut events) = EVENTS.lock() {
        events.push(event);
    }
}

/// Drain the recorded event queue (FIFO).
#[must_use]
pub fn take_events() -> Vec<RecordedEvent> {
    EVENTS
        .lock()
        .map(|mut events| std::mem::take(&mut *events))
        .unwrap_or_default()
}

/// # Safety
/// `ptr` must be a valid NUL-terminated UTF-8 string or null.
unsafe fn cstr(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    // SAFETY: contract documented above; callers are the lui bridge, which
    // always hands NUL-terminated CString buffers.
    unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned()
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_press(node: i64) -> c_int {
    record(RecordedEvent::Press(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_text_changed(node: i64, text: *const c_char) -> c_int {
    record(RecordedEvent::TextChanged {
        node,
        text: unsafe { cstr(text) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_submit(node: i64) -> c_int {
    record(RecordedEvent::Submit(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_dismiss(node: i64) -> c_int {
    record(RecordedEvent::Dismiss(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_picked(node: i64, payload: *const c_char) -> c_int {
    record(RecordedEvent::Picked {
        node,
        payload: unsafe { cstr(payload) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_toggle_changed(node: i64, checked: c_int) -> c_int {
    record(RecordedEvent::ToggleChanged {
        node,
        checked: checked != 0,
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_radio_changed(node: i64) -> c_int {
    record(RecordedEvent::RadioChanged(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_slider_changed(node: i64, fraction: c_double) -> c_int {
    record(RecordedEvent::SliderChanged { node, fraction });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_press_detail(
    node: i64,
    x: c_double,
    y: c_double,
    modifiers: c_int,
    button: c_int,
    target_class: *const c_char,
) -> c_int {
    record(RecordedEvent::PointerDetail {
        node,
        x,
        y,
        modifiers,
        button,
        target_class: unsafe { cstr(target_class) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_context_menu_press(
    node: i64,
    x: c_double,
    y: c_double,
    modifiers: c_int,
    button: c_int,
    target_class: *const c_char,
) -> c_int {
    record(RecordedEvent::ContextMenuPress {
        node,
        x,
        y,
        modifiers,
        button,
        target_class: unsafe { cstr(target_class) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_extension_event(
    node: i64,
    identifier: *const c_char,
    name: *const c_char,
    json_values: *const c_char,
) -> c_int {
    record(RecordedEvent::ExtensionEvent {
        node,
        identifier: unsafe { cstr(identifier) },
        name: unsafe { cstr(name) },
        json: unsafe { cstr(json_values) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_press_ex(node: i64, modifiers: c_int) -> c_int {
    record(RecordedEvent::PressModifiers { node, modifiers });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_appear(node: i64) -> c_int {
    record(RecordedEvent::Appear(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_long_press(node: i64) -> c_int {
    record(RecordedEvent::LongPress(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_double_press(node: i64) -> c_int {
    record(RecordedEvent::DoublePress(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_pointer_enter(node: i64) -> c_int {
    record(RecordedEvent::PointerEnter(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_pointer_leave(node: i64) -> c_int {
    record(RecordedEvent::PointerLeave(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_pointer_down(
    node: i64,
    _x: c_double,
    _y: c_double,
    _modifiers: c_int,
    _button: c_int,
    _target_class: *const c_char,
) -> c_int {
    record(RecordedEvent::PointerDown(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_pointer_up(
    node: i64,
    _x: c_double,
    _y: c_double,
    _modifiers: c_int,
    _button: c_int,
    _target_class: *const c_char,
) -> c_int {
    record(RecordedEvent::PointerUp(node));
    0
}

unsafe fn bytes(ptr: *const c_char, len: c_int) -> String {
    if ptr.is_null() || len <= 0 {
        return String::new();
    }
    let slice = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    String::from_utf8_lossy(slice).into_owned()
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_text_changed_utf8(
    node: i64,
    text: *const c_char,
    text_len: c_int,
) -> c_int {
    record(RecordedEvent::TextChanged {
        node,
        text: unsafe { bytes(text, text_len) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_picked_utf8(
    node: i64,
    payload: *const c_char,
    len: c_int,
) -> c_int {
    record(RecordedEvent::Picked {
        node,
        payload: unsafe { bytes(payload, len) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_extension_event_utf8(
    node: i64,
    identifier: *const c_char,
    identifier_len: c_int,
    name: *const c_char,
    name_len: c_int,
    json_values: *const c_char,
    json_len: c_int,
) -> c_int {
    record(RecordedEvent::ExtensionEvent {
        node,
        identifier: unsafe { bytes(identifier, identifier_len) },
        name: unsafe { bytes(name, name_len) },
        json: unsafe { bytes(json_values, json_len) },
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_resync() -> c_int {
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_load(node: i64) -> c_int {
    record(RecordedEvent::Load(node));
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_visible_range(node: i64, first: i64, last: i64) -> c_int {
    record(RecordedEvent::VisibleRange { node, first, last });
    0
}

#[no_mangle]
pub unsafe extern "C" fn lui_ocaml_scroll_completed(
    node: i64,
    token: i64,
    outcome: *const c_char,
) -> c_int {
    record(RecordedEvent::ScrollCompleted {
        node,
        token,
        outcome: unsafe { cstr(outcome) },
    });
    0
}
