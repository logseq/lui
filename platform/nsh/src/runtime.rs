//! Serialized access to the process's OCaml runtime, off the NSH engine thread.
use crate::wire::Batch;
use libloading::Library;
use std::{
    cell::RefCell,
    ffi::{CStr, CString, c_char},
    mem::ManuallyDrop,
    path::{Path, PathBuf},
    sync::{
        Arc, OnceLock, Weak,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};
use tokio::sync::{mpsc, oneshot};

pub use crate::events::{PointerDetail, PointerKind};

const QUEUE_CAPACITY: usize = 64;
const NSH_HOST_CODE: i32 = 6;
static WORKER: OnceLock<mpsc::Sender<Request>> = OnceLock::new();
static NEXT_SESSION: AtomicU64 = AtomicU64::new(1);

/// A semantic request. IDs retain OCaml's signed integer precision.
#[derive(Debug, Clone)]
pub enum Event {
    Press {
        node: i64,
        modifiers: i32,
    },
    LongPress(i64),
    DoublePress(i64),
    PointerEnter(i64),
    PointerLeave(i64),
    Pointer {
        node: i64,
        kind: PointerKind,
        detail: PointerDetail,
    },
    Text {
        node: i64,
        text: String,
    },
    Submit(i64),
    Toggle {
        node: i64,
        checked: bool,
    },
    Value {
        node: i64,
        value: f64,
    },
    FocusWithin {
        node: i64,
        within: bool,
    },
    Appear(i64),
    Change(i64),
    Dismiss(i64),
    VisibleRange {
        node: i64,
        first: i64,
        last: i64,
    },
    ScrollCompleted {
        node: i64,
        token: i64,
        outcome: String,
    },
    VirtualWindow {
        node: i64,
        generation: i64,
        first: i64,
        last: i64,
        pins: Vec<i64>,
    },
}

/// One foreign call's ordered batches, or an authoritative recovery snapshot.
#[derive(Debug, Default)]
#[non_exhaustive]
pub struct Reply {
    pub batches: Vec<Batch>,
    pub snapshot: Option<Batch>,
    pub diagnostic: Option<String>,
    pub agent: Option<String>,
    pub next_delay: Option<Duration>,
    pub root: i64,
}

/// The active application. Clones share a lease; its last drop queues disposal.
#[derive(Clone)]
pub struct Session(Arc<Lease>);

struct Lease {
    id: u64,
    sender: mpsc::Sender<Request>,
}
impl Drop for Lease {
    fn drop(&mut self) {
        // A full queue already wakes the worker, which checks its weak lease
        // before each request. An idle worker is woken by this close request.
        let _ = self.sender.try_send(Request {
            session: self.id,
            lease: Weak::new(),
            operation: Operation::Close,
            reply: None,
        });
    }
}

enum Operation {
    Open { path: PathBuf, platform: i32 },
    Event(Event),
    Agent(String),
    Resync,
    Tick,
    Advance(f64),
    Pause(bool),
    Close,
}
struct Request {
    session: u64,
    lease: Weak<Lease>,
    operation: Operation,
    reply: Option<oneshot::Sender<Result<Reply, String>>>,
}

impl Session {
    /// Opens one application on the persistent runtime thread.
    pub async fn open(path: impl AsRef<Path>, platform: i32) -> Result<(Self, Reply), String> {
        let path = std::fs::canonicalize(path).map_err(|e| format!("OCaml library: {e}"))?;
        let sender = WORKER
            .get_or_init(|| {
                let (sender, receiver) = mpsc::channel(QUEUE_CAPACITY);
                std::thread::Builder::new()
                    .name("lui-ocaml".into())
                    .stack_size(8 * 1024 * 1024)
                    .spawn(move || Worker::default().run(receiver))
                    .expect("start OCaml runtime worker");
                sender
            })
            .clone();
        let session = Self(Arc::new(Lease {
            id: NEXT_SESSION.fetch_add(1, Ordering::Relaxed),
            sender,
        }));
        let reply = session.request(Operation::Open { path, platform }).await?;
        Ok((session, reply))
    }

    async fn request(&self, operation: Operation) -> Result<Reply, String> {
        let (reply, receiver) = oneshot::channel();
        self.0
            .sender
            .send(Request {
                session: self.0.id,
                lease: Arc::downgrade(&self.0),
                operation,
                reply: Some(reply),
            })
            .await
            .map_err(|_| "OCaml worker stopped".to_owned())?;
        receiver
            .await
            .map_err(|_| "OCaml worker did not reply".to_owned())?
    }

    /// Delivers one semantic event and returns its patches.
    pub async fn dispatch(&self, event: Event) -> Result<Reply, String> {
        self.request(Operation::Event(event)).await
    }
    /// Uses the existing LUI agent protocol and its canonical selectors.
    pub async fn agent(&self, json: String) -> Result<Reply, String> {
        self.request(Operation::Agent(json)).await
    }
    /// Requests a complete snapshot, independent of delta generation.
    pub async fn resync(&self) -> Result<Reply, String> {
        self.request(Operation::Resync).await
    }
    /// Ticks at the worker's monotonic time, after the last reported delay.
    pub async fn tick(&self) -> Result<Reply, String> {
        self.request(Operation::Tick).await
    }
    /// Advances a paused application clock for deterministic drivers.
    pub async fn advance(&self, ms: f64) -> Result<Reply, String> {
        self.request(Operation::Advance(ms)).await
    }
    /// Pauses or resumes application time.
    pub async fn pause(&self, paused: bool) -> Result<Reply, String> {
        self.request(Operation::Pause(paused)).await
    }
    /// Disposes the application before opening another session.
    pub async fn close(&self) -> Result<Reply, String> {
        self.request(Operation::Close).await
    }
}

#[derive(Default)]
struct Worker {
    native: Option<Native>,
    active: Option<(u64, Weak<Lease>)>,
}
impl Worker {
    fn run(mut self, mut receiver: mpsc::Receiver<Request>) {
        while let Some(request) = receiver.blocking_recv() {
            if self
                .active
                .as_ref()
                .is_some_and(|(_, lease)| lease.strong_count() == 0)
            {
                if let Some(native) = &mut self.native {
                    let _ = native.invoke(&Operation::Close);
                }
                self.active = None;
            }
            let result = self.handle(&request);
            if let Some(reply) = request.reply {
                let _ = reply.send(result);
            }
        }
    }
    fn handle(&mut self, request: &Request) -> Result<Reply, String> {
        if let Operation::Open { path, .. } = &request.operation {
            if request.lease.strong_count() == 0 {
                return Err("application opening was cancelled".into());
            }
            if self.active.is_some() {
                return Err("only one active LUI OCaml session is supported".into());
            }
            match &self.native {
                Some(native) if native.path != *path => {
                    return Err("only one OCaml library may be initialized per process".into());
                }
                None => self.native = Some(Native::load(path)?),
                _ => (),
            }
            self.active = Some((request.session, request.lease.clone()));
            let native = self.native.as_mut().expect("loaded native runtime");
            let result = native.invoke(&request.operation);
            if result.is_err() {
                let _ = native.invoke(&Operation::Close);
                self.active = None;
            }
            return result;
        }
        if self.active.as_ref().map(|(id, _)| *id) != Some(request.session) {
            return if matches!(request.operation, Operation::Close) {
                Ok(Reply::default())
            } else {
                Err("OCaml application session is no longer active".into())
            };
        }
        let result = self
            .native
            .as_mut()
            .expect("active runtime")
            .invoke(&request.operation);
        if matches!(request.operation, Operation::Close) {
            self.active = None;
        }
        result
    }
}

type Callback = extern "C" fn(*const c_char);
type UnitFn = unsafe extern "C" fn() -> i32;
type NodeFn = unsafe extern "C" fn(i64) -> i32;
type NodeIntFn = unsafe extern "C" fn(i64, i32) -> i32;
type TextFn = unsafe extern "C" fn(i64, *const c_char, i32) -> i32;
type NumberFn = unsafe extern "C" fn(i64, f64) -> i32;
type PointerFn = unsafe extern "C" fn(i64, f64, f64, i32, i32, *const c_char, i32) -> i32;
type RangeFn = unsafe extern "C" fn(i64, i64, i64) -> i32;
type WindowFn = unsafe extern "C" fn(i64, i64, i64, i64, *const i64, i32) -> i32;
type ScrollCompletedFn = unsafe extern "C" fn(i64, i64, *const c_char) -> i32;

struct Exports {
    start: unsafe extern "C" fn(Callback, i32, i32) -> i32,
    stop: UnitFn,
    resync: UnitFn,
    last_error: unsafe extern "C" fn(Callback) -> i32,
    root: unsafe extern "C" fn() -> i64,
    press: NodeIntFn,
    long_press: Option<NodeFn>,
    double_press: Option<NodeFn>,
    pointer_enter: Option<NodeFn>,
    pointer_leave: Option<NodeFn>,
    pointer: [Option<PointerFn>; 6],
    text: TextFn,
    submit: NodeFn,
    toggle: NodeIntFn,
    value: NumberFn,
    focus_within: NodeIntFn,
    appear: NodeFn,
    change: NodeFn,
    dismiss: NodeFn,
    visible_range: RangeFn,
    scroll_completed: Option<ScrollCompletedFn>,
    virtual_window: Option<WindowFn>,
    agent: Option<unsafe extern "C" fn(*const c_char, i32, Callback) -> i32>,
    tick: unsafe extern "C" fn(f64) -> i32,
    advance: unsafe extern "C" fn(f64) -> i32,
    pause: unsafe extern "C" fn(i32) -> i32,
    next_delay: unsafe extern "C" fn() -> f64,
}
struct Native {
    path: PathBuf,
    // OCaml registers process-global runtime state at startup. Never dlclose it,
    // including a Rust unwind on the worker; process exit reclaims the mapping.
    _library: ManuallyDrop<Library>,
    exports: Exports,
    epoch: Instant,
}

impl Native {
    fn load(path: &Path) -> Result<Self, String> {
        // SAFETY: the user-selected application is trusted native code. All
        // symbols below are the fixed ABI in platform/bridge/lui_ocaml_bridge.c.
        // Loading occurs only on the persistent thread that will invoke them.
        unsafe {
            #[cfg(windows)]
            let library = {
                use libloading::os::windows::{
                    LOAD_LIBRARY_SEARCH_DEFAULT_DIRS, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR,
                };
                // The canonical absolute application path lets Windows resolve
                // its private dependent DLLs beside it, without changing the
                // process search path or current directory.
                libloading::os::windows::Library::load_with_flags(
                    path,
                    LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS,
                )
                .map(Library::from)
                .map_err(|e| format!("load OCaml library: {e}"))?
            };
            #[cfg(not(windows))]
            let library = Library::new(path).map_err(|e| format!("load OCaml library: {e}"))?;
            macro_rules! required {
                ($name:literal) => {
                    *library
                        .get(concat!($name, "\0").as_bytes())
                        .map_err(|e| format!("OCaml ABI {}: {e}", $name))?
                };
            }
            macro_rules! optional {
                ($name:literal) => {
                    library
                        .get(concat!($name, "\0").as_bytes())
                        .ok()
                        .map(|symbol| *symbol)
                };
            }
            let exports = Exports {
                start: required!("lui_ocaml_start"),
                stop: required!("lui_ocaml_stop"),
                resync: required!("lui_ocaml_resync"),
                last_error: required!("lui_ocaml_last_error"),
                root: required!("lui_ocaml_root_node"),
                press: required!("lui_ocaml_press_ex"),
                long_press: optional!("lui_ocaml_long_press"),
                double_press: optional!("lui_ocaml_double_press"),
                pointer_enter: optional!("lui_ocaml_pointer_enter"),
                pointer_leave: optional!("lui_ocaml_pointer_leave"),
                pointer: [
                    optional!("lui_ocaml_press_detail_utf8"),
                    optional!("lui_ocaml_pointer_down_utf8"),
                    optional!("lui_ocaml_pointer_up_utf8"),
                    optional!("lui_ocaml_pointer_move_utf8"),
                    optional!("lui_ocaml_pointer_cancel_utf8"),
                    optional!("lui_ocaml_context_menu_press_utf8"),
                ],
                text: required!("lui_ocaml_text_changed_utf8"),
                submit: required!("lui_ocaml_submit"),
                toggle: required!("lui_ocaml_toggle_changed"),
                value: required!("lui_ocaml_slider_changed"),
                focus_within: required!("lui_ocaml_focus_within_changed"),
                appear: required!("lui_ocaml_appear"),
                change: required!("lui_ocaml_radio_changed"),
                dismiss: required!("lui_ocaml_dismiss"),
                visible_range: required!("lui_ocaml_visible_range"),
                scroll_completed: optional!("lui_ocaml_scroll_completed"),
                virtual_window: optional!("lui_ocaml_virtual_window"),
                agent: optional!("lui_ocaml_agent_utf8"),
                tick: required!("lui_ocaml_clock_tick"),
                advance: required!("lui_ocaml_clock_advance"),
                pause: required!("lui_ocaml_clock_set_paused"),
                next_delay: required!("lui_ocaml_clock_next_delay"),
            };
            Ok(Self {
                path: path.into(),
                _library: ManuallyDrop::new(library),
                exports,
                epoch: Instant::now(),
            })
        }
    }

    fn invoke(&mut self, operation: &Operation) -> Result<Reply, String> {
        CAPTURE.with(|c| *c.borrow_mut() = Capture::default());
        let api = &self.exports;
        // SAFETY: these function pointers outlive the process. Only this worker
        // calls them. All slice pointers remain borrowed through the synchronous
        // call, their lengths are checked, and callbacks copy bytes before return.
        // Advance before ordinary requests so rearming their wakeup cannot defer
        // a pending timer, and handlers schedule against current application time.
        let synchronized =
            !matches!(
                operation,
                Operation::Event(_) | Operation::Agent(_) | Operation::Resync
            ) || unsafe { (api.tick)(self.epoch.elapsed().as_secs_f64() * 1000.0) != 0 };
        let accepted = unsafe {
            if !synchronized {
                0
            } else {
                match operation {
                    Operation::Open { platform, .. } => {
                        self.epoch = Instant::now();
                        let accepted = (api.start)(capture_patch, *platform, NSH_HOST_CODE);
                        // Anchor host time now; anchoring only at the first due timer
                        // would delay that timer by another complete interval.
                        if accepted != 0 {
                            (api.tick)(0.0)
                        } else {
                            accepted
                        }
                    }
                    Operation::Close => (api.stop)(),
                    Operation::Resync => {
                        // The snapshot includes timers fired by the preceding tick.
                        // Discard their deltas, retaining callback errors and diagnostics.
                        CAPTURE.with(|capture| capture.borrow_mut().patches.clear());
                        (api.resync)()
                    }
                    Operation::Tick => (api.tick)(self.epoch.elapsed().as_secs_f64() * 1000.0),
                    Operation::Advance(ms) => (api.advance)(*ms),
                    Operation::Pause(paused) => {
                        let accepted = (api.pause)(i32::from(*paused));
                        if !paused && accepted != 0 {
                            (api.tick)(self.epoch.elapsed().as_secs_f64() * 1000.0)
                        } else {
                            accepted
                        }
                    }
                    Operation::Agent(json) => {
                        let agent = api.agent.ok_or("OCaml library has no agent ABI")?;
                        agent(json.as_ptr().cast(), length(json.len())?, capture_agent)
                    }
                    Operation::Event(event) => match event {
                        Event::Press { node, modifiers } => (api.press)(*node, *modifiers),
                        Event::LongPress(node) => api
                            .long_press
                            .ok_or("OCaml library has no long-press ABI")?(
                            *node
                        ),
                        Event::DoublePress(node) => api
                            .double_press
                            .ok_or("OCaml library has no double-press ABI")?(
                            *node
                        ),
                        Event::PointerEnter(node) => api
                            .pointer_enter
                            .ok_or("OCaml library has no pointer-enter ABI")?(
                            *node
                        ),
                        Event::PointerLeave(node) => api
                            .pointer_leave
                            .ok_or("OCaml library has no pointer-leave ABI")?(
                            *node
                        ),
                        Event::Pointer { node, kind, detail } => {
                            if !detail.x.is_finite() || !detail.y.is_finite() {
                                return Err("pointer coordinates must be finite".into());
                            }
                            let pointer = api.pointer[*kind as usize]
                                .ok_or("OCaml library has no requested pointer ABI")?;
                            pointer(
                                *node,
                                detail.x,
                                detail.y,
                                detail.modifiers,
                                detail.button,
                                detail.target_class.as_ptr().cast(),
                                length(detail.target_class.len())?,
                            )
                        }
                        Event::Text { node, text } => {
                            (api.text)(*node, text.as_ptr().cast(), length(text.len())?)
                        }
                        Event::Submit(node) => (api.submit)(*node),
                        Event::Toggle { node, checked } => (api.toggle)(*node, i32::from(*checked)),
                        Event::Value { node, value } => (api.value)(*node, *value),
                        Event::FocusWithin { node, within } => {
                            (api.focus_within)(*node, i32::from(*within))
                        }
                        Event::Appear(node) => (api.appear)(*node),
                        Event::Change(node) => (api.change)(*node),
                        Event::Dismiss(node) => (api.dismiss)(*node),
                        Event::VisibleRange { node, first, last } => {
                            (api.visible_range)(*node, *first, *last)
                        }
                        Event::ScrollCompleted {
                            node,
                            token,
                            outcome,
                        } => {
                            let completed = api
                                .scroll_completed
                                .ok_or("OCaml library has no scroll-completion ABI")?;
                            let outcome = CString::new(outcome.as_str())
                                .map_err(|_| "scroll outcome contains a NUL byte")?;
                            completed(*node, *token, outcome.as_ptr())
                        }
                        Event::VirtualWindow {
                            node,
                            generation,
                            first,
                            last,
                            pins,
                        } => {
                            let window = api
                                .virtual_window
                                .ok_or("OCaml library has no virtual-window ABI")?;
                            window(
                                *node,
                                *generation,
                                *first,
                                *last,
                                pins.as_ptr(),
                                length(pins.len())?,
                            )
                        }
                    },
                }
            }
        };
        let mut captured = CAPTURE.with(|c| std::mem::take(&mut *c.borrow_mut()));
        let mut snapshot = None;
        if accepted == 0 {
            // SAFETY: same worker/thread and callback lifetime as above. A refused
            // dispatch leaves the mirror stale, even if it already delivered batches.
            unsafe {
                (api.last_error)(capture_diagnostic);
            }
            captured.diagnostic = CAPTURE.with(|c| c.borrow_mut().diagnostic.take());
            if matches!(
                operation,
                Operation::Open { .. } | Operation::Close | Operation::Resync
            ) {
                return Err(captured
                    .diagnostic
                    .unwrap_or_else(|| "OCaml lifecycle request was refused".into()));
            }
            if unsafe { (api.resync)() } == 0 {
                return Err("OCaml refused recovery snapshot".into());
            }
            let recovery = CAPTURE.with(|c| std::mem::take(&mut *c.borrow_mut()));
            if let Some(error) = recovery.error {
                return Err(error);
            }
            if recovery.patches.len() != 1 {
                return Err("OCaml resync must return one authoritative batch".into());
            }
            snapshot = Some(Batch::decode(&recovery.patches[0])?);
            captured.patches.clear();
        } else if matches!(operation, Operation::Resync) {
            if captured.patches.len() != 1 {
                return Err("OCaml resync must return one authoritative batch".into());
            }
            snapshot = Some(Batch::decode(&captured.patches.remove(0))?);
        }
        if let Some(error) = captured.error {
            return Err(error);
        }
        let batches = captured
            .patches
            .iter()
            .map(|json| Batch::decode(json))
            .collect::<Result<_, _>>()?;
        // SAFETY: the runtime is started on this thread; queries use the same
        // lock discipline. After close no query is needed.
        let (delay, root) = if matches!(operation, Operation::Close) {
            (-1.0, 0)
        } else {
            unsafe { ((api.next_delay)(), (api.root)()) }
        };
        Ok(Reply {
            batches,
            snapshot,
            diagnostic: captured.diagnostic,
            agent: captured.agent,
            next_delay: (delay.is_finite() && delay >= 0.0)
                .then(|| Duration::from_secs_f64((delay / 1000.0).min(86400.0))),
            root,
        })
    }
}

fn length(length: usize) -> Result<i32, String> {
    i32::try_from(length).map_err(|_| "OCaml ABI payload exceeds int32 length".into())
}

#[derive(Default)]
struct Capture {
    patches: Vec<String>,
    diagnostic: Option<String>,
    agent: Option<String>,
    error: Option<String>,
}
thread_local! { static CAPTURE: RefCell<Capture> = RefCell::new(Capture::default()); }
fn capture(pointer: *const c_char, store: impl FnOnce(&mut Capture, String)) {
    // No Rust panic may unwind into C. The ABI promises a NUL-terminated string
    // valid only for the callback; copy it while the foreign call is active.
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        CAPTURE.with(|capture| {
            let mut capture = capture.borrow_mut();
            if pointer.is_null() {
                capture.error = Some("null OCaml callback payload".into());
                return;
            }
            // SAFETY: lui_ocaml_* delivers a borrowed NUL-terminated C string.
            match unsafe { CStr::from_ptr(pointer) }.to_str() {
                Ok(json) => store(&mut capture, json.to_owned()),
                Err(_) => capture.error = Some("invalid UTF-8 in OCaml callback payload".into()),
            }
        });
    }));
    if result.is_err() {
        CAPTURE.with(|capture| {
            if let Ok(mut capture) = capture.try_borrow_mut() {
                capture.error = Some("Rust callback panicked while receiving OCaml data".into());
            }
        });
    }
}
extern "C" fn capture_patch(pointer: *const c_char) {
    capture(pointer, |c, json| c.patches.push(json));
}
extern "C" fn capture_diagnostic(pointer: *const c_char) {
    capture(pointer, |c, json| c.diagnostic = Some(json));
}
extern "C" fn capture_agent(pointer: *const c_char) {
    capture(pointer, |c, json| c.agent = Some(json));
}
