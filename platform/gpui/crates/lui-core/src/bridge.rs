//! C ABI surface of `platform/native/lui_ocaml_bridge.c`.
//!
//! Lock discipline (mirrors the C header):
//! * `lui_ocaml_start` hands every patch batch to the registered callback
//!   *while the OCaml runtime lock is held* — the callback must only copy the
//!   string and return. `patch_sink` below does exactly that.
//! * Every `lui_ocaml_*` event entry point synchronously emits the next patch
//!   batch through the same callback before returning.
//! * Event callers must be on a thread the OCaml runtime knows — the thread
//!   that ran `lui_ocaml_start` qualifies. Call all of these from the GPUI
//!   main thread.

use std::ffi::{c_char, c_double, c_int, c_void, CStr};
use std::sync::Mutex;

pub type PatchCallback = unsafe extern "C" fn(*const c_char);

extern "C" {
    pub fn lui_ocaml_start(
        callback: PatchCallback,
        platform_code: c_int,
        host_code: c_int,
    ) -> c_int;
    pub fn lui_ocaml_appear(node: i64) -> c_int;
    pub fn lui_ocaml_press(node: i64) -> c_int;
    /// `modifiers`: host modifier bitmask at tap time (see bridge header).
    pub fn lui_ocaml_press_ex(node: i64, modifiers: c_int) -> c_int;
    pub fn lui_ocaml_long_press(node: i64) -> c_int;
    pub fn lui_ocaml_text_changed(node: i64, text: *const c_char) -> c_int;
    pub fn lui_ocaml_text_changed_utf8(node: i64, text: *const c_char, text_len: c_int) -> c_int;
    pub fn lui_ocaml_submit(node: i64) -> c_int;
    pub fn lui_ocaml_dismiss(node: i64) -> c_int;
    pub fn lui_ocaml_picked(node: i64, payload: *const c_char) -> c_int;
    pub fn lui_ocaml_picked_utf8(node: i64, payload: *const c_char, len: c_int) -> c_int;
    pub fn lui_ocaml_double_press(node: i64) -> c_int;
    pub fn lui_ocaml_toggle_changed(node: i64, checked: c_int) -> c_int;
    pub fn lui_ocaml_radio_changed(node: i64) -> c_int;
    pub fn lui_ocaml_slider_changed(node: i64, fraction: c_double) -> c_int;
    pub fn lui_ocaml_extension_event(
        node: i64,
        identifier: *const c_char,
        name: *const c_char,
        json_values: *const c_char,
    ) -> c_int;
    pub fn lui_ocaml_stop() -> c_int;
    pub fn lui_ocaml_root_node() -> i64;
}

/// Batches pushed by the patch callback, in arrival order. Drained by the
/// driver on the UI thread after each `lui_ocaml_*` call returns.
static PENDING: Mutex<Vec<String>> = Mutex::new(Vec::new());

/// Safe default callback: copies the JSON into [`PENDING`]. It performs no
/// allocation-heavy work and never re-enters OCaml.
/// # Safety
/// `json` must be the NUL-terminated string the bridge hands the callback.
pub unsafe extern "C" fn patch_sink(json: *const c_char) {
    if json.is_null() {
        return;
    }
    // SAFETY: the bridge hands a NUL-terminated UTF-8 string valid for the
    // duration of the callback; we copy it into owned memory immediately.
    let text = unsafe { CStr::from_ptr(json) }
        .to_string_lossy()
        .into_owned();
    if let Ok(mut queue) = PENDING.lock() {
        queue.push(text);
    }
}

/// Drain every queued batch (oldest first). Call after `lui_ocaml_start` and
/// after each event entry point returns.
pub fn take_patches() -> Vec<String> {
    match PENDING.lock() {
        Ok(mut queue) => std::mem::take(&mut *queue),
        Err(_) => Vec::new(),
    }
}

/// Map a GPUI `Keystroke`-style modifier state to the bridge's bitmask.
/// Mirrors `LUIEventModifiers` in the Apple backend (shift=1, ctrl=2,
/// alt/opt=4, cmd=8); kept here so host crates stay UI-free.
pub fn modifiers_mask(shift: bool, control: bool, alt: bool, command: bool) -> c_int {
    (shift as c_int) | ((control as c_int) << 1) | ((alt as c_int) << 2) | ((command as c_int) << 3)
}

/// Convenience: start the OCaml runtime with [`patch_sink`]. Returns the
/// bridge's `accepted` flag.
///
/// # Safety
/// Must be called on the thread that will later issue all `lui_ocaml_*`
/// event calls (the GPUI main thread), before any of them.
pub unsafe fn start(platform_code: c_int, host_code: c_int) -> c_int {
    lui_ocaml_start(patch_sink, platform_code, host_code)
}

/// Host code for the GPUI backend (`GPUIHost` in `src/lui_protocol.ml`).
pub const HOST_GPUI: c_int = 6;

/// `operating_system` codes from `src/lui_protocol.ml`.
pub const OS_MACOS: c_int = 1;
pub const OS_IOS: c_int = 2;
pub const OS_ANDROID: c_int = 3;
pub const OS_LINUX: c_int = 4;
pub const OS_WINDOWS: c_int = 5;

/// Detect the current OS code for `lui_ocaml_start`.
pub const fn current_os() -> c_int {
    #[cfg(target_os = "macos")]
    {
        OS_MACOS
    }
    #[cfg(target_os = "ios")]
    {
        OS_IOS
    }
    #[cfg(target_os = "android")]
    {
        OS_ANDROID
    }
    #[cfg(target_os = "linux")]
    {
        OS_LINUX
    }
    #[cfg(target_os = "windows")]
    {
        OS_WINDOWS
    }
    #[cfg(not(any(
        target_os = "macos",
        target_os = "ios",
        target_os = "android",
        target_os = "linux",
        target_os = "windows"
    )))]
    {
        0
    }
}

/// Avoid an unused-import style warning for FFI consumers that only need a
/// subset of the ABI: referencing this type keeps `c_void` linked for crates
/// building with `-C link-args` oddities. (No runtime effect.)
pub type _Opaque = c_void;
