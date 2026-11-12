//! One Rust root shared by the desktop runner and real-engine tests.
use crate::{
    render::{Event as ViewEvent, Renderer},
    runtime::{
        ApplicationMessage, BridgeConfig, Event, PlatformEvent, PlatformRequest, Reply, Session,
    },
};
use nsh_core::{
    element::{Spawned, timer},
    prelude::*,
};
use std::{
    cell::{Cell, RefCell},
    collections::{BTreeMap, VecDeque},
    future::{Future, poll_fn},
    path::PathBuf,
    pin::{Pin, pin},
    rc::Rc,
    task::Poll,
    time::Duration,
};
use tokio::sync::{mpsc, oneshot};

/// Startup configuration. The library path is fixed for the root's lifetime.
#[derive(Debug, Clone, PartialEq, Props)]
#[non_exhaustive]
pub struct DesktopProps {
    /// Application library; empty uses LUI_OCAML_LIBRARY or packaged resources.
    #[prop(default)]
    pub library: Prop<String>,
    /// Optional numeric loopback listener; empty reads LUI_AGENT_LISTEN.
    #[prop(default)]
    pub agent_listen: Prop<String>,
}

/// Application-owned host services. The existing ordered desktop pump is the
/// sole consumer; callbacks never call OCaml or publish patches themselves.
pub type DeferredEvents = Pin<Box<dyn Future<Output = Result<Vec<PlatformEvent>, String>>>>;
/// Host operations that require layout run after the current response is published.
pub enum ServiceResponse {
    Events(Vec<PlatformEvent>),
    AfterCommit(DeferredEvents),
}
/// Waits for the owning engine answer/commit without requesting a display frame.
/// A disposed owner cancels the callback and returns an error. Public ElementRef
/// measurement then observes the Core layout of the commit carrying its request.
/// This does not acknowledge a platform MountBatch, native animation completion
/// or painted pixels; an AppKit surface may still defer a batch during motion.
pub async fn wait_for_commit() -> Result<(), String> {
    let (send, receive) = oneshot::channel();
    after_answer(move || {
        let _ = send.send(());
    });
    receive
        .await
        .map_err(|_| "native commit owner was disposed".to_owned())
}

pub type ServiceFuture = Pin<Box<dyn Future<Output = Result<ServiceResponse, String>>>>;
type ServiceHandler = dyn Fn(PlatformRequest, Renderer) -> ServiceFuture;

/// Supply this context above `Desktop` when selecting an application bridge
/// that emits platform requests. Generic applications do not allocate a handler.
#[derive(Clone)]
pub struct ApplicationServices(Rc<ServiceHandler>);
impl ApplicationServices {
    pub fn new(handler: impl Fn(PlatformRequest, Renderer) -> ServiceFuture + 'static) -> Self {
        Self(Rc::new(handler))
    }
}

/// Optional application-owned admission policy for new user and agent mutations.
/// Provide above `Desktop`; absent preserves the generic application's behavior.
/// Checks are synchronous and must not dispatch events or begin asynchronous work.
#[derive(Clone)]
pub struct ApplicationMutations {
    owner: Owner,
    check: Rc<dyn Fn() -> Result<(), String>>,
}
impl ApplicationMutations {
    /// Captures the current application owner and a live admission predicate.
    pub fn new(check: impl Fn() -> Result<(), String> + 'static) -> Self {
        Self {
            owner: Owner::current(),
            check: Rc::new(check),
        }
    }
    /// Refuses mutation after its owner retires or while the app is quiescent.
    pub fn check(&self) -> Result<(), String> {
        if !self.owner.is_live() {
            return Err("application mutation owner has retired".into());
        }
        (self.check)()
    }
}

fn agent_mutates(operation: Option<&str>) -> bool {
    !matches!(
        operation,
        Some(
            "hello"
                | "tree"
                | "dump"
                | "find"
                | "prop"
                | "screenshot"
                | "native-bounds"
                | "native-dialog"
                | "gc-stats"
        )
    )
}

/// Read-only queries are barriers on the application's existing input queue.
/// Factories capture this context before the runtime opens, then await queries
/// after earlier emitted edits have reached the authoritative OCaml model.
#[derive(Clone)]
pub struct ApplicationRuntime(mpsc::Sender<Request>);
impl ApplicationRuntime {
    pub async fn editor_snapshot(
        &self,
        block_id: String,
    ) -> Result<Option<crate::runtime::EditorSnapshot>, String> {
        let (reply, response) = oneshot::channel();
        self.0
            .send(Request::EditorSnapshot { block_id, reply })
            .await
            .map_err(|_| "application query queue is closed".to_owned())?;
        response
            .await
            .map_err(|_| "application query was disposed".to_owned())?
    }
}

/// Queues application platform events onto the same ordered OCaml pump.
/// Native menus and window callbacks retain this capability, never the worker.
#[derive(Clone)]
pub struct ApplicationEvents(mpsc::Sender<Request>);
impl ApplicationEvents {
    pub fn send(&self, event: PlatformEvent) -> Result<(), String> {
        self.0
            .try_send(Request::Platform(event))
            .map_err(|error| format!("application platform event queue: {error}"))
    }
}

enum Request {
    Event(GuardedEvent),
    Platform(PlatformEvent),
    EditorSnapshot {
        block_id: String,
        reply: oneshot::Sender<Result<Option<crate::runtime::EditorSnapshot>, String>>,
    },
    Tick,
    Pump,
    WindowWake,
    Agent {
        request: String,
        reply: oneshot::Sender<Result<String, String>>,
    },
}

struct GuardedEvent {
    event: ViewEvent,
    node: u64,
    incarnation: u64,
    generation: Option<u64>,
}
impl GuardedEvent {
    fn capture(event: ViewEvent, renderer: &Renderer) -> Option<Self> {
        let (node, incarnation, generation) = match &event {
            ViewEvent::Extension {
                node, incarnation, ..
            } => (*node, *incarnation, None),
            ViewEvent::VirtualWindow {
                node,
                incarnation,
                generation,
                ..
            } => (*node, *incarnation, Some(*generation)),
            ViewEvent::VisibleRange {
                node, incarnation, ..
            } => (
                *node,
                *incarnation,
                renderer
                    .node_snapshot(*node)?
                    .props
                    .get("virtual-generation")
                    .and_then(serde_json::Value::as_u64),
            ),
            ViewEvent::ScrollCompleted {
                node, incarnation, ..
            } => (*node, *incarnation, None),
            ViewEvent::NativePress(node, _)
            | ViewEvent::Pointer { node, .. }
            | ViewEvent::LongPress(node)
            | ViewEvent::DoublePress(node)
            | ViewEvent::PointerEnter(node)
            | ViewEvent::PointerLeave(node)
            | ViewEvent::Press(node)
            | ViewEvent::Text(node, _)
            | ViewEvent::Submit(node)
            | ViewEvent::NavigatePrevious(node)
            | ViewEvent::NavigateNext(node)
            | ViewEvent::Toggle(node, _)
            | ViewEvent::ToggleDetail(node, _, _)
            | ViewEvent::Value(node, _)
            | ViewEvent::Focus(node)
            | ViewEvent::Blur(node)
            | ViewEvent::Appear(node)
            | ViewEvent::Load(node)
            | ViewEvent::Change(node)
            | ViewEvent::Picked(node, _)
            | ViewEvent::Dismiss(node) => (*node, renderer.current_incarnation(*node)?, None),
        };
        Some(Self {
            event,
            node,
            incarnation,
            generation,
        })
    }
    fn current(&self, renderer: &Renderer) -> bool {
        renderer.is_current(self.node, self.incarnation, self.generation)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum FeedbackKind {
    Window,
    VisibleRange,
}

/// One latest window and range per list, independent of the user queue.
/// The pump also drains feedback after each queued request, so a full queue
/// cannot lose the wakeup. Scroll-token completions remain ordered requests.
#[derive(Clone, Default)]
struct Windows {
    pending: Rc<RefCell<BTreeMap<(u64, FeedbackKind), GuardedEvent>>>,
    order: Rc<RefCell<VecDeque<(u64, FeedbackKind)>>>,
    waking: Rc<Cell<bool>>,
}
impl Windows {
    fn insert(&self, kind: FeedbackKind, event: GuardedEvent) {
        let key = (event.node, kind);
        if self.pending.borrow_mut().insert(key, event).is_none() {
            self.order.borrow_mut().push_back(key);
        }
    }
    fn pop(&self) -> Option<GuardedEvent> {
        let node = self.order.borrow_mut().pop_front()?;
        self.pending.borrow_mut().remove(&node)
    }
    fn wake(&self, sender: &mpsc::Sender<Request>) {
        if !self.pending.borrow().is_empty()
            && !self.waking.get()
            && sender.try_send(Request::WindowWake).is_ok()
        {
            self.waking.set(true);
        }
    }
}
#[derive(Clone, Default)]
struct Clock {
    task: Rc<RefCell<Option<Spawned<()>>>>,
    queued: Rc<Cell<bool>>,
}
impl Clock {
    fn cancel(&self) {
        if let Some(task) = self.task.borrow_mut().take() {
            task.cancel();
        }
    }
    fn schedule(&self, delay: Option<Duration>, sender: &mpsc::Sender<Request>) {
        self.cancel();
        if self.queued.get() {
            return;
        }
        let Some(delay) = delay else {
            return;
        };
        let clock = self.clone();
        let sender = sender.clone();
        *self.task.borrow_mut() = Some(spawn(async move {
            timer(delay).await;
            clock.task.borrow_mut().take();
            // Tick is maintenance, superseded by a queued request's next-delay
            // query. A full queue will reschedule it when that request returns.
            if sender.try_send(Request::Tick).is_ok() {
                clock.queued.set(true);
            }
        }));
    }
}

/// Passive native feedback completes previously accepted render/service work.
/// Unknown app extension events remain input; their schemas do not declare an
/// origin that could prove they are completion-only.
fn renderer_event_mutates(event: &ViewEvent) -> bool {
    match event {
        ViewEvent::VirtualWindow { .. }
        | ViewEvent::VisibleRange { .. }
        | ViewEvent::ScrollCompleted { .. }
        | ViewEvent::Load(_)
        | ViewEvent::Appear(_)
        | ViewEvent::Picked(..) => false,
        ViewEvent::Extension { .. }
        | ViewEvent::Press(_)
        | ViewEvent::NativePress(..)
        | ViewEvent::LongPress(_)
        | ViewEvent::DoublePress(_)
        | ViewEvent::PointerEnter(_)
        | ViewEvent::PointerLeave(_)
        | ViewEvent::Pointer { .. }
        | ViewEvent::Text(..)
        | ViewEvent::Submit(_)
        | ViewEvent::NavigatePrevious(_)
        | ViewEvent::NavigateNext(_)
        | ViewEvent::Toggle(..)
        | ViewEvent::ToggleDetail(..)
        | ViewEvent::Value(..)
        | ViewEvent::Focus(_)
        | ViewEvent::Blur(_)
        | ViewEvent::Change(_)
        | ViewEvent::Dismiss(_) => true,
    }
}

fn enqueue_renderer_event(
    event: ViewEvent,
    renderer: Renderer,
    admission: Option<&ApplicationMutations>,
    windows: &Windows,
    sender: &mpsc::Sender<Request>,
) {
    // Previously accepted events keep their queue order. Maintenance/completion
    // feedback must also finish while new user input is fenced.
    if renderer_event_mutates(&event) && admission.is_some_and(|guard| guard.check().is_err()) {
        return;
    }
    let Some(event) = GuardedEvent::capture(event, &renderer) else {
        return;
    };
    if !event.current(&renderer) {
        return;
    }
    let feedback = match &event.event {
        ViewEvent::VirtualWindow { .. } => Some(FeedbackKind::Window),
        ViewEvent::VisibleRange { .. } => Some(FeedbackKind::VisibleRange),
        _ => None,
    };
    if let Some(kind) = feedback {
        windows.insert(kind, event);
        windows.wake(sender);
    } else if sender.try_send(Request::Event(event)).is_err() {
        renderer.fail("The application request queue is full or closed".into());
    }
}

/// Runs an OCaml LUI application without a JavaScript runtime.
#[component]
pub fn Desktop(props: DesktopProps) -> impl IntoElement {
    let (sender, mut receiver) = mpsc::channel(64);
    provide_context(ApplicationEvents(sender.clone()));
    provide_context(ApplicationRuntime(sender.clone()));
    let admission = use_context::<ApplicationMutations>();
    let input_admission = admission.clone();
    let for_events = sender.clone();
    let windows = Windows::default();
    let for_windows = windows.clone();
    let dispatch = move |event, renderer: Renderer| {
        enqueue_renderer_event(
            event,
            renderer,
            input_admission.as_ref(),
            &for_windows,
            &for_events,
        );
    };
    let renderer = if let Some(extensions) = use_context::<crate::extensions::Extensions>() {
        Renderer::with_extensions(extensions, dispatch)
    } else {
        Renderer::new(dispatch)
    };
    let configured_agent = props.agent_listen.get_untracked();
    let agent_address = if configured_agent.is_empty() {
        std::env::var("LUI_AGENT_LISTEN").unwrap_or_default()
    } else {
        configured_agent
    };
    if !agent_address.is_empty() {
        let for_agent = sender.clone();
        match crate::agent::Server::start(&agent_address, move |request| {
            let (reply, response) = oneshot::channel();
            for_agent
                .try_send(Request::Agent { request, reply })
                .map_err(|error| format!("application agent queue: {error}"))?;
            response
                .blocking_recv()
                .map_err(|_| "application agent session closed".to_owned())?
        }) {
            Ok(agent) => cleanup(move || drop(agent)),
            Err(error) => renderer.fail(error),
        }
    }
    let clock = Clock::default();
    let cleanup_clock = clock.clone();
    cleanup(move || cleanup_clock.cancel());
    let opening = renderer.clone();
    let bridge = use_context::<BridgeConfig>().unwrap_or_default();
    let services = use_context::<ApplicationServices>();
    let path = library_path(&props.library.get_untracked());
    spawn(async move {
        let result = match path {
            Ok(path) => Session::open_with_config(path, platform_code(), bridge).await,
            Err(error) => Err(error),
        };
        let (session, reply) = match result {
            Ok(opened) => opened,
            Err(error) => {
                opening.fail(error);
                return;
            }
        };
        publish(
            &opening,
            &clock,
            &sender,
            &session,
            services.as_ref(),
            Ok(reply),
        )
        .await;
        // One pump owns response publication. Independent per-event tasks could
        // observe a later ready reply before an earlier suspended task resumes.
        // The engine stays free while this task awaits the OCaml worker.
        let mut native_dialogs = crate::native_agent::Dialogs::default();
        loop {
            let wake = session.woken();
            let mut wake = pin!(wake);
            let request = poll_fn(|context| {
                if let Poll::Ready(request) = receiver.poll_recv(context) {
                    return Poll::Ready(request);
                }
                if wake.as_mut().poll(context).is_ready() {
                    return Poll::Ready(Some(Request::Pump));
                }
                Poll::Pending
            })
            .await;
            let Some(request) = request else { break };

            let reply = match request {
                Request::Event(event) if event.current(&opening) => {
                    Some(session.dispatch(semantic(event.event)).await)
                }
                Request::Event(_) => None,
                Request::Platform(event) => Some(session.platform_event(event).await),
                Request::EditorSnapshot { block_id, reply } => {
                    if !reply.is_closed() {
                        let _ = reply.send(session.editor_snapshot(block_id).await);
                    }
                    None
                }
                Request::Pump => Some(session.pump().await),
                Request::Tick => {
                    clock.queued.set(false);
                    Some(session.tick().await)
                }
                Request::WindowWake => {
                    windows.waking.set(false);
                    None
                }
                // Early agent replies still finish the shared feedback epilogue.
                Request::Agent { request, reply } => 'request: {
                    let operation = serde_json::from_str::<serde_json::Value>(&request)
                        .ok()
                        .and_then(|request| {
                            request
                                .get("op")
                                .and_then(|op| op.as_str())
                                .map(str::to_owned)
                        });
                    if let Err(error) = agent_ready(&opening, operation.as_deref()) {
                        let _ = reply.send(Err(error));
                        break 'request None;
                    }
                    if agent_mutates(operation.as_deref())
                        && let Some(guard) = admission.as_ref()
                        && let Err(error) = guard.check()
                    {
                        let _ = reply.send(Err(error));
                        break 'request None;
                    }
                    if operation.as_deref() == Some("screenshot") {
                        let captured = async {
                            wait_for_commit().await?;
                            crate::native_capture::screenshot().await
                        }.await.and_then(|capture| {
                            use base64::Engine;
                            if capture.png.len() > 16 * 1024 * 1024 {
                                return Err("native screenshot exceeds 16 MiB".to_owned());
                            }
                            Ok(serde_json::json!({"ok":true,"op":"screenshot","format":"png",
                                "width":capture.width,"height":capture.height,
                                "capture":"appkit-content",
                                "data":base64::engine::general_purpose::STANDARD.encode(capture.png)}).to_string())
                        });
                        let _ = reply.send(accept_agent_reply(
                            &opening,
                            operation.as_deref(),
                            true,
                            captured,
                        ));
                        break 'request None;
                    }
                    if operation.as_deref() == Some("native-dialog-answer") {
                        let answered = native_dialogs
                            .answer(&opening, &request, admission.as_ref())
                            .await;
                        let _ = reply.send(accept_agent_reply(
                            &opening,
                            operation.as_deref(),
                            true,
                            answered,
                        ));
                        break 'request None;
                    }
                    let native_press = operation.as_deref() == Some("native-press");
                    let native_bounds = operation.as_deref() == Some("native-bounds");
                    let native_dialog = operation.as_deref() == Some("native-dialog");
                    let request = if native_press || native_bounds || native_dialog {
                        let translated = serde_json::from_str(&request)
                            .map_err(|error| error.to_string())
                            .and_then(|request| crate::native_agent::find_request(&request));
                        match translated {
                            Ok(request) => request,
                            Err(error) => {
                                let _ = reply.send(Err(error));
                                break 'request None;
                            }
                        }
                    } else {
                        request
                    };
                    let mut result = session.agent(request).await;
                    let answer = match &mut result {
                        Ok(reply) => reply
                            .agent
                            .take()
                            .ok_or_else(|| "OCaml agent returned no response".to_owned()),
                        Err(error) => Err(error.clone()),
                    };
                    let published = publish(
                        &opening,
                        &clock,
                        &sender,
                        &session,
                        services.as_ref(),
                        result,
                    )
                    .await;
                    let answer =
                        accept_agent_reply(&opening, operation.as_deref(), published, answer);
                    let answer = match answer {
                        Ok(answer) if native_press => {
                            crate::native_agent::press(&opening, &answer, admission.as_ref()).await
                        }
                        Ok(answer) if native_bounds => {
                            crate::native_agent::bounds(&opening, &answer).await
                        }
                        Ok(answer) if native_dialog => {
                            native_dialogs.inspect(&opening, &answer).await
                        }
                        Ok(answer) if operation.as_deref() == Some("hello") => {
                            crate::native_agent::hello(answer)
                        }
                        answer => answer,
                    };
                    let _ = reply.send(answer);
                    None
                }
            };
            if let Some(reply) = reply {
                publish(
                    &opening,
                    &clock,
                    &sender,
                    &session,
                    services.as_ref(),
                    reply,
                )
                .await;
            }
            if let Some(window) = windows.pop()
                && window.current(&opening)
            {
                let reply = session.dispatch(semantic(window.event)).await;
                publish(
                    &opening,
                    &clock,
                    &sender,
                    &session,
                    services.as_ref(),
                    reply,
                )
                .await;
            }
            windows.wake(&sender);
        }
    });
    renderer.element()
}

async fn publish(
    renderer: &Renderer,
    clock: &Clock,
    sender: &mpsc::Sender<Request>,
    session: &Session,
    services: Option<&ApplicationServices>,
    reply: Result<Reply, String>,
) -> bool {
    let accepted = match reply {
        Ok(reply) => accept_ordered(renderer, session, services, reply).await,
        Err(error) => Err(error),
    };
    match accepted {
        Ok(delay) => {
            clock.schedule(delay, sender);
            true
        }
        Err(error) => {
            clock.cancel();
            renderer.fail(error.clone());
            // A local decode/validation failure has not changed the OCaml
            // application. Recover on this same ordered pump before accepting
            // another event, just as the worker recovers a refused C call.
            let recovery = match session.resync().await {
                Ok(reply) => accept_ordered(renderer, session, services, reply).await,
                Err(error) => Err(error),
            };
            match recovery {
                Ok(delay) => clock.schedule(delay, sender),
                Err(recovery) => renderer.fail(format!("{error}; resync failed: {recovery}")),
            }
            false
        }
    }
}

// Diagnostic operations stay available when retained semantic content is stale.
fn diagnostic_agent_operation(operation: Option<&str>) -> bool {
    matches!(operation, Some("hello" | "screenshot"))
}

fn agent_ready(renderer: &Renderer, operation: Option<&str>) -> Result<(), String> {
    if !diagnostic_agent_operation(operation)
        && let Some(error) = renderer.failure()
    {
        return Err(error);
    }
    Ok(())
}

fn accept_agent_reply(
    renderer: &Renderer,
    operation: Option<&str>,
    published: bool,
    answer: Result<String, String>,
) -> Result<String, String> {
    agent_ready(renderer, operation)?;
    if diagnostic_agent_operation(operation)
        && let Some(error) = renderer.failure()
    {
        let mut answer: serde_json::Value =
            serde_json::from_str(&answer?).map_err(|error| error.to_string())?;
        answer["backend_error"] = serde_json::Value::String(error);
        return Ok(answer.to_string());
    }
    if !published {
        return Err("agent patches could not be published; inspect the backend diagnostic".into());
    }
    answer
}

async fn accept_ordered(
    renderer: &Renderer,
    session: &Session,
    services: Option<&ApplicationServices>,
    reply: Reply,
) -> Result<Option<Duration>, String> {
    if reply.messages.is_none() {
        return accept(renderer, reply);
    }
    let mut replies = VecDeque::from([reply]);
    let mut deferred = Vec::new();
    let mut delay = None;
    while let Some(mut reply) = replies.pop_front() {
        for message in reply
            .messages
            .take()
            .ok_or("application reply changed bridge ABI")?
        {
            match message {
                ApplicationMessage::Batch(batch) => renderer.apply(batch)?,
                ApplicationMessage::Snapshot(batch) => renderer.replace(batch)?,
                ApplicationMessage::PlatformRequest(request) => {
                    let handler = services.ok_or_else(|| {
                        format!(
                            "application host service is not installed: {}",
                            request.operation
                        )
                    })?;
                    match (handler.0)(request, renderer.clone()).await? {
                        ServiceResponse::Events(events) => {
                            for event in events {
                                // Native callbacks produced by this event go behind
                                // messages already captured by the OCaml mailbox.
                                replies.push_back(session.platform_event(event).await?);
                            }
                        }
                        ServiceResponse::AfterCommit(future) => deferred.push(future),
                    }
                }
            }
            if u64::try_from(reply.root)
                .ok()
                .is_some_and(|id| renderer.node_snapshot(id).is_some())
            {
                renderer.set_root(reply.root)?;
            }
        }
        renderer.set_root(reply.root)?;
        if let Some(error) = reply.diagnostic {
            renderer.fail(error);
        }
        delay = reply.next_delay;
    }
    if !deferred.is_empty() {
        let events =
            use_context::<ApplicationEvents>().ok_or("application event pump is missing")?;
        for future in deferred {
            let events = events.clone();
            let renderer = renderer.clone();
            spawn(async move {
                let result = match wait_for_commit().await {
                    Ok(()) => future.await,
                    Err(error) => Err(error),
                };
                match result {
                    Ok(replies) => {
                        for reply in replies {
                            if let Err(error) = events.send(reply) {
                                renderer.fail(error);
                                break;
                            }
                        }
                    }
                    Err(error) => renderer.fail(error),
                }
            });
        }
    }
    Ok(delay)
}

fn accept(renderer: &Renderer, reply: Reply) -> Result<Option<Duration>, String> {
    if let Some(snapshot) = reply.snapshot {
        renderer.replace(snapshot)?;
    } else {
        for batch in reply.batches {
            renderer.apply(batch)?;
        }
    }
    renderer.set_root(reply.root)?;
    if let Some(error) = reply.diagnostic {
        renderer.fail(error);
    }
    Ok(reply.next_delay)
}

fn semantic(event: ViewEvent) -> Event {
    match event {
        ViewEvent::Extension {
            node,
            identifier,
            name,
            values,
            ..
        } => Event::Extension {
            node: node as i64,
            identifier,
            name,
            values,
        },
        ViewEvent::NativePress(node, modifiers) => Event::Press {
            node: node as i64,
            modifiers,
        },
        ViewEvent::LongPress(node) => Event::LongPress(node as i64),
        ViewEvent::DoublePress(node) => Event::DoublePress(node as i64),
        ViewEvent::PointerEnter(node) => Event::PointerEnter(node as i64),
        ViewEvent::PointerLeave(node) => Event::PointerLeave(node as i64),
        ViewEvent::Pointer { node, kind, detail } => Event::Pointer {
            node: node as i64,
            kind,
            detail,
        },
        ViewEvent::Press(node) => Event::Press {
            node: node as i64,
            modifiers: 0,
        },
        ViewEvent::Text(node, text) => Event::Text {
            node: node as i64,
            text,
        },
        ViewEvent::Submit(node) => Event::Submit(node as i64),
        ViewEvent::NavigatePrevious(node) => Event::NavigatePrevious(node as i64),
        ViewEvent::NavigateNext(node) => Event::NavigateNext(node as i64),
        ViewEvent::Toggle(node, checked) => Event::Toggle {
            node: node as i64,
            checked,
        },
        ViewEvent::ToggleDetail(node, checked, modifiers) => Event::ToggleDetail {
            node: node as i64,
            checked,
            modifiers,
        },
        ViewEvent::Value(node, value) => Event::Value {
            node: node as i64,
            value,
        },
        ViewEvent::Focus(node) => Event::FocusWithin {
            node: node as i64,
            within: true,
        },
        ViewEvent::Blur(node) => Event::FocusWithin {
            node: node as i64,
            within: false,
        },
        ViewEvent::Appear(node) => Event::Appear(node as i64),
        ViewEvent::Load(node) => Event::Load(node as i64),
        ViewEvent::Change(node) => Event::Change(node as i64),
        ViewEvent::Dismiss(node) => Event::Dismiss(node as i64),
        ViewEvent::Picked(node, payload) => Event::Picked {
            node: node as i64,
            payload,
        },
        ViewEvent::VisibleRange {
            node, first, last, ..
        } => Event::VisibleRange {
            node: node as i64,
            first,
            last,
        },
        ViewEvent::ScrollCompleted {
            node,
            token,
            outcome,
            ..
        } => Event::ScrollCompleted {
            node: node as i64,
            token: token as i64,
            outcome,
        },
        ViewEvent::VirtualWindow {
            node,
            generation,
            first,
            last,
            pins,
            ..
        } => Event::VirtualWindow {
            node: node as i64,
            generation: generation as i64,
            first: first as i64,
            last: last as i64,
            pins: pins.into_iter().map(|pin| pin as i64).collect(),
        },
    }
}

fn platform_code() -> i32 {
    if cfg!(target_os = "macos") {
        1
    } else if cfg!(target_os = "linux") {
        4
    } else if cfg!(windows) {
        5
    } else {
        0
    }
}

fn library_path(configured: &str) -> Result<PathBuf, String> {
    if !configured.is_empty() {
        return Ok(configured.into());
    }
    if let Some(path) = std::env::var_os("LUI_OCAML_LIBRARY") {
        return Ok(path.into());
    }
    let executable = std::env::current_exe().map_err(|e| format!("executable path: {e}"))?;
    let directory = executable
        .parent()
        .ok_or("executable has no parent directory")?;
    Ok(if cfg!(target_os = "macos") {
        directory.join("../Resources/lui/liblui_app.dylib")
    } else if cfg!(windows) {
        directory.join("lui/lui_app.dll")
    } else {
        directory.join("lui/liblui_app.so")
    })
}

#[cfg(test)]
#[path = "app/commit_tests.rs"]
mod commit_tests;

#[cfg(test)]
mod mutation_tests {
    use super::*;
    #[test]
    fn quiescence_admits_only_read_only_agent_operations() {
        for op in [
            "hello",
            "tree",
            "dump",
            "find",
            "prop",
            "screenshot",
            "native-bounds",
            "native-dialog",
            "gc-stats",
        ] {
            assert!(!agent_mutates(Some(op)), "{op}");
        }
        for op in [
            "native-press",
            "native-dialog-answer",
            "press",
            "key",
            "ext",
            "toggle",
            "text",
            "future-mutation",
        ] {
            assert!(agent_mutates(Some(op)), "{op}");
        }
        assert!(agent_mutates(None));
    }
}

#[cfg(test)]
#[path = "app/feedback_tests.rs"]
mod feedback_tests;

#[cfg(test)]
#[path = "app/agent_failure_tests.rs"]
mod agent_failure_tests;
