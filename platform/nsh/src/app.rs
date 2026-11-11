//! One Rust root shared by the desktop runner and real-engine tests.
use crate::{
    render::{Event as ViewEvent, Renderer},
    runtime::{Event, Reply, Session},
};
use nsh_core::{
    element::{Spawned, timer},
    prelude::*,
};
use std::{
    cell::{Cell, RefCell},
    collections::{BTreeMap, VecDeque},
    path::PathBuf,
    rc::Rc,
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

enum Request {
    Event(GuardedEvent),
    Tick,
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
            ViewEvent::VirtualWindow {
                node,
                incarnation,
                generation,
                ..
            } => (*node, *incarnation, Some(*generation)),
            ViewEvent::VisibleRange {
                node, incarnation, ..
            }
            | ViewEvent::ScrollCompleted {
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
            | ViewEvent::Toggle(node, _)
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

/// One latest window per live list. A full user queue cannot lose the wakeup:
/// the pump drains one pending window after each queued request too.
#[derive(Clone, Default)]
struct Windows {
    pending: Rc<RefCell<BTreeMap<u64, GuardedEvent>>>,
    order: Rc<RefCell<VecDeque<u64>>>,
    waking: Rc<Cell<bool>>,
}
impl Windows {
    fn insert(&self, event: GuardedEvent) {
        let node = event.node;
        if self.pending.borrow_mut().insert(node, event).is_none() {
            self.order.borrow_mut().push_back(node);
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

/// Runs an OCaml LUI application without a JavaScript runtime.
#[component]
pub fn Desktop(props: DesktopProps) -> impl IntoElement {
    let (sender, mut receiver) = mpsc::channel(64);
    let for_events = sender.clone();
    let windows = Windows::default();
    let for_windows = windows.clone();
    let renderer = Renderer::new(move |event, renderer| {
        let Some(event) = GuardedEvent::capture(event, &renderer) else {
            return;
        };
        if !event.current(&renderer) {
            return;
        }
        if matches!(&event.event, ViewEvent::VirtualWindow { .. }) {
            for_windows.insert(event);
            for_windows.wake(&for_events);
        } else if for_events.try_send(Request::Event(event)).is_err() {
            renderer.fail("The application request queue is full or closed".into());
        }
    });
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
    let path = library_path(&props.library.get_untracked());
    spawn(async move {
        let result = match path {
            Ok(path) => Session::open(path, platform_code()).await,
            Err(error) => Err(error),
        };
        let (session, reply) = match result {
            Ok(opened) => opened,
            Err(error) => {
                opening.fail(error);
                return;
            }
        };
        publish(&opening, &clock, &sender, &session, Ok(reply)).await;
        // One pump owns response publication. Independent per-event tasks could
        // observe a later ready reply before an earlier suspended task resumes.
        // The engine stays free while this task awaits the OCaml worker.
        while let Some(request) = receiver.recv().await {
            let reply = match request {
                Request::Event(event) if event.current(&opening) => {
                    Some(session.dispatch(semantic(event.event)).await)
                }
                Request::Event(_) => None,
                Request::Tick => {
                    clock.queued.set(false);
                    Some(session.tick().await)
                }
                Request::WindowWake => {
                    windows.waking.set(false);
                    None
                }
                Request::Agent { request, reply } => {
                    let mut result = session.agent(request).await;
                    let answer = match &mut result {
                        Ok(reply) => reply
                            .agent
                            .take()
                            .ok_or_else(|| "OCaml agent returned no response".to_owned()),
                        Err(error) => Err(error.clone()),
                    };
                    let published = publish(&opening, &clock, &sender, &session, result).await;
                    let answer = if published {
                        answer
                    } else {
                        Err(
                            "agent patches could not be published; inspect the backend diagnostic"
                                .into(),
                        )
                    };
                    let _ = reply.send(answer);
                    None
                }
            };
            if let Some(reply) = reply {
                publish(&opening, &clock, &sender, &session, reply).await;
            }
            if let Some(window) = windows.pop()
                && window.current(&opening)
            {
                let reply = session.dispatch(semantic(window.event)).await;
                publish(&opening, &clock, &sender, &session, reply).await;
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
    reply: Result<Reply, String>,
) -> bool {
    match reply.and_then(|reply| accept(renderer, reply)) {
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
            match session
                .resync()
                .await
                .and_then(|reply| accept(renderer, reply))
            {
                Ok(delay) => clock.schedule(delay, sender),
                Err(recovery) => renderer.fail(format!("{error}; resync failed: {recovery}")),
            }
            false
        }
    }
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
        ViewEvent::Toggle(node, checked) => Event::Toggle {
            node: node as i64,
            checked,
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
