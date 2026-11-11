//! Explicit startup ABIs. A symbol name alone cannot distinguish their types.
use super::{Callback, UnitFn, length};
use libloading::Library;
use std::sync::atomic::{AtomicBool, Ordering};
use std::{
    ffi::c_char,
    sync::{Arc, Mutex, OnceLock, Weak},
};
use tokio::sync::Notify;

/// Selects the ABI actually exported by the application library.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum BridgeConfig {
    /// The standard three-argument LUI bridge, with its host-driven clock.
    #[default]
    Generic,
    /// Logseq's seven-argument bridge. Payload bytes are passed verbatim.
    Logseq { payload: String },
}

/// A copied `operation\npayload` message from Logseq's host channel.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlatformRequest {
    pub operation: String,
    pub payload: String,
}

/// A reply/event sent back through Logseq's length-carrying platform channel.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlatformEvent {
    pub operation: String,
    pub payload: String,
}
impl PlatformEvent {
    pub(super) fn encode(&self) -> Result<String, String> {
        if self.operation.is_empty() || self.operation.contains(['\n', '\0']) {
            return Err("platform event operation must be nonempty without newline or NUL".into());
        }
        Ok(format!("{}\n{}", self.operation, self.payload))
    }
}

#[derive(Default)]
pub(super) struct Callbacks {
    pub notify: Notify,
    ordered: Mutex<Ordered>,
    error: Mutex<Option<String>>,
}
#[derive(Default)]
struct Ordered {
    messages: Vec<MessageOrder>,
    patches: usize,
}
pub(super) enum MessageOrder {
    Patch(usize),
    Request(PlatformRequest),
}
static ACTIVE: AtomicBool = AtomicBool::new(false);
static CALLBACKS: OnceLock<Mutex<Weak<Callbacks>>> = OnceLock::new();
impl Callbacks {
    pub fn install(this: &Arc<Self>) {
        *CALLBACKS
            .get_or_init(Mutex::default)
            .lock()
            .expect("callback scope") = Arc::downgrade(this);
        ACTIVE.store(true, Ordering::Release);
    }
    pub fn clear() {
        ACTIVE.store(false, Ordering::Release);
        if let Some(scope) = CALLBACKS.get() {
            *scope.lock().expect("callback scope") = Weak::new();
        }
    }
    pub fn take(&self) -> Result<Vec<MessageOrder>, String> {
        if let Some(error) = self.error.lock().expect("callback error").take() {
            return Err(error);
        }
        Ok(std::mem::take(&mut *self.ordered.lock().expect("platform messages")).messages)
    }
}
fn scope() -> Option<Arc<Callbacks>> {
    if !ACTIVE.load(Ordering::Acquire) {
        return None;
    }
    CALLBACKS.get()?.lock().ok()?.upgrade()
}
pub(super) fn record_patch() {
    if let Some(scope) = scope() {
        let mut ordered = scope.ordered.lock().expect("platform messages");
        let index = ordered.patches;
        ordered.patches += 1;
        ordered.messages.push(MessageOrder::Patch(index));
    }
}
pub(super) fn take_messages() -> Option<Result<Vec<MessageOrder>, String>> {
    scope().map(|scope| scope.take())
}
extern "C" fn wakeup() {
    if let Some(scope) = scope() {
        scope.notify.notify_one();
    }
}
extern "C" fn platform_request(data: *const c_char, len: i32) {
    // Foreign callbacks never enter OCaml or block on its worker queue.
    let _ = std::panic::catch_unwind(|| {
        let Some(scope) = scope() else { return };
        let parsed = if data.is_null() || len < 0 {
            Err("invalid Logseq platform request slice".to_owned())
        } else {
            // SAFETY: the bridge borrows these exact bytes until callback return.
            let bytes = unsafe { std::slice::from_raw_parts(data.cast::<u8>(), len as usize) };
            std::str::from_utf8(bytes)
                .map_err(|_| "invalid UTF-8 in platform request".to_owned())
                .and_then(|text| {
                    let (operation, payload) = text
                        .split_once('\n')
                        .ok_or("platform request has no operation separator")?;
                    if operation.is_empty() {
                        return Err("empty platform request operation".into());
                    }
                    Ok(PlatformRequest {
                        operation: operation.into(),
                        payload: payload.into(),
                    })
                })
        };
        match parsed {
            Ok(request) => scope
                .ordered
                .lock()
                .expect("platform messages")
                .messages
                .push(MessageOrder::Request(request)),
            Err(error) => *scope.error.lock().expect("callback error") = Some(error),
        }
        // Synchronous requests are returned in this worker call's ordered reply.
        // Only the separate wakeup callback signals deferred OCaml mailbox work.
    });
}

type GenericStart = unsafe extern "C" fn(Callback, i32, i32) -> i32;
type LogseqStart = unsafe extern "C" fn(
    Callback,
    extern "C" fn(),
    extern "C" fn(*const c_char, i32),
    i32,
    i32,
    *const c_char,
    i32,
) -> i32;
type ClockFn = unsafe extern "C" fn(f64) -> i32;
type PlatformFn = unsafe extern "C" fn(*const c_char, i32) -> i32;
pub(super) enum Driver {
    Generic {
        start: GenericStart,
        error: unsafe extern "C" fn(Callback) -> i32,
        tick: ClockFn,
        advance: ClockFn,
        pause: unsafe extern "C" fn(i32) -> i32,
        delay: unsafe extern "C" fn() -> f64,
    },
    Logseq {
        start: LogseqStart,
        pump: UnitFn,
        event: PlatformFn,
    },
}
impl Driver {
    /// The caller keeps the trusted library loaded for every invocation.
    pub unsafe fn load(library: &Library, config: &BridgeConfig) -> Result<Self, String> {
        macro_rules! symbol {
            ($name:literal) => {
                // SAFETY: explicit config selects the matching declared C ABI.
                unsafe {
                    *library
                        .get(concat!($name, "\0").as_bytes())
                        .map_err(|e| format!("OCaml ABI {}: {e}", $name))?
                }
            };
        }
        Ok(match config {
            BridgeConfig::Generic => Self::Generic {
                start: symbol!("lui_ocaml_start"),
                error: symbol!("lui_ocaml_last_error"),
                tick: symbol!("lui_ocaml_clock_tick"),
                advance: symbol!("lui_ocaml_clock_advance"),
                pause: symbol!("lui_ocaml_clock_set_paused"),
                delay: symbol!("lui_ocaml_clock_next_delay"),
            },
            BridgeConfig::Logseq { .. } => Self::Logseq {
                start: symbol!("lui_ocaml_start"),
                pump: symbol!("lui_ocaml_pump"),
                event: symbol!("lui_ocaml_platform_event"),
            },
        })
    }
    pub fn matches(&self, config: &BridgeConfig) -> bool {
        matches!(
            (self, config),
            (Self::Generic { .. }, BridgeConfig::Generic)
                | (Self::Logseq { .. }, BridgeConfig::Logseq { .. })
        )
    }
    pub unsafe fn start(
        &self,
        config: &BridgeConfig,
        callback: Callback,
        platform: i32,
        host: i32,
    ) -> Result<i32, String> {
        // SAFETY: all borrowed bytes and callbacks outlive the synchronous call.
        unsafe {
            match (self, config) {
                (Self::Generic { start, tick, .. }, BridgeConfig::Generic) => {
                    let accepted = start(callback, platform, host);
                    Ok(if accepted != 0 { tick(0.0) } else { accepted })
                }
                (Self::Logseq { start, .. }, BridgeConfig::Logseq { payload }) => Ok(start(
                    callback,
                    wakeup,
                    platform_request,
                    platform,
                    host,
                    payload.as_ptr().cast(),
                    length(payload.len())?,
                )),
                _ => Err("cannot change the initialized OCaml bridge ABI".into()),
            }
        }
    }
    pub unsafe fn synchronize(&self, ms: f64) -> i32 {
        // Logseq's Host mailbox owns its timers and wakes the app explicitly.
        unsafe {
            match self {
                Self::Generic { tick, .. } => tick(ms),
                Self::Logseq { .. } => 1,
            }
        }
    }
    pub unsafe fn tick(&self, ms: f64) -> Result<i32, String> {
        unsafe {
            match self {
                Self::Generic { tick, .. } => Ok(tick(ms)),
                _ => Err("Logseq bridge uses wakeup/pump, not host clock ticks".into()),
            }
        }
    }
    pub unsafe fn advance(&self, ms: f64) -> Result<i32, String> {
        unsafe {
            match self {
                Self::Generic { advance, .. } => Ok(advance(ms)),
                _ => Err("Logseq bridge has no controllable clock ABI".into()),
            }
        }
    }
    pub unsafe fn pause(&self, paused: bool, ms: f64) -> Result<i32, String> {
        unsafe {
            match self {
                Self::Generic { pause, tick, .. } => {
                    let accepted = pause(i32::from(paused));
                    Ok(if !paused && accepted != 0 {
                        tick(ms)
                    } else {
                        accepted
                    })
                }
                _ => Err("Logseq bridge has no controllable clock ABI".into()),
            }
        }
    }
    pub unsafe fn pump(&self) -> Result<i32, String> {
        unsafe {
            match self {
                Self::Logseq { pump, .. } => Ok(pump()),
                _ => Err("generic bridge has no Logseq pump ABI".into()),
            }
        }
    }
    pub unsafe fn platform_event(&self, encoded: &str) -> Result<i32, String> {
        unsafe {
            match self {
                Self::Logseq { event, pump, .. } => {
                    let accepted = event(encoded.as_ptr().cast(), length(encoded.len())?);
                    // platform_event enqueues OCaml work but does not emit patches.
                    Ok(if accepted != 0 { pump() } else { accepted })
                }
                _ => Err("generic bridge has no platform event ABI".into()),
            }
        }
    }
    pub unsafe fn diagnostic(&self, callback: Callback) {
        if let Self::Generic { error, .. } = self {
            unsafe {
                error(callback);
            }
        }
    }
    pub unsafe fn delay(&self) -> f64 {
        unsafe {
            match self {
                Self::Generic { delay, .. } => delay(),
                Self::Logseq { .. } => -1.0,
            }
        }
    }
}
