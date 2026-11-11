//! Native Toast owns dismissal and ToastStack owns measured layout. Canonical
//! nodes supply content and remain closed after native completion until their
//! incarnation leaves the source. One deadline wakes the native manager.
use super::{ChildIdentity, Presentation};
use crate::{store::Node, ui};
use nsh_base::{ToastManager, ToastMotion, ToastOptions, ToastTransitionStatus as Phase};
use nsh_core::{
    geometry::Size,
    prelude::*,
    time::{Instant, now},
};
use std::{cell::RefCell, collections::BTreeSet, rc::Rc, sync::Arc, time::Duration};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Member {
    pub identity: ChildIdentity,
    pub attached: bool,
}
pub(crate) type Lookup = Rc<dyn Fn(ChildIdentity) -> Option<Signal<Arc<Node>>>>;
pub(crate) type Render = Rc<dyn Fn(ChildIdentity) -> AnyElement>;
pub(crate) type Notify = Rc<dyn Fn(ChildIdentity)>;

// The public manager exposes phases but not its next deadline. These are wake
// hints only; its advance() remains the sole authority for phase and removal.
struct Wake {
    remaining: Option<Duration>,
    deadline: Option<Instant>,
    cancelled: bool,
}
struct State {
    manager: ToastManager<ChildIdentity, Rc<RefCell<Wake>>>,
    motion: ToastMotion,
    closed: BTreeSet<ChildIdentity>,
    paused: bool,
    shown: Signal<Vec<(ChildIdentity, Phase)>>,
    armed: Option<Instant>,
    task: Option<Spawned<()>>,
    owner: Owner,
    notify: Notify,
}
#[derive(Clone)]
struct Controller(Rc<RefCell<State>>);

impl State {
    fn advance(&mut self, at: Instant) -> Vec<ChildIdentity> {
        let changed = self.manager.advance(at, self.paused);
        for id in changed.presented {
            if let Some(wake) = self.manager.get(&id) {
                let mut wake = wake.borrow_mut();
                wake.deadline = if self.paused {
                    None
                } else {
                    wake.remaining.map(|left| at + left)
                };
            }
        }
        for id in changed.ending {
            self.closed.insert(id);
            self.manager.get(&id).unwrap().borrow_mut().deadline =
                Some(at + self.motion.exit_duration);
        }
        changed
            .removed
            .into_iter()
            .filter_map(|(id, wake)| {
                if wake.borrow().cancelled {
                    None
                } else {
                    self.closed.insert(id);
                    Some(id)
                }
            })
            .collect()
    }
    fn close(&mut self, id: ChildIdentity, at: Instant, cancelled: bool) {
        if let Some(wake) = self.manager.get(&id) {
            let mut wake = wake.borrow_mut();
            wake.cancelled |= cancelled;
        }
        if self.manager.dismiss(&id, at) {
            self.manager.get(&id).unwrap().borrow_mut().deadline =
                Some(at + self.motion.exit_duration);
        }
        self.closed.insert(id);
    }
}
impl Controller {
    fn new(notify: Notify) -> Self {
        let motion = ToastMotion::sonner();
        let controller = Self(Rc::new(RefCell::new(State {
            manager: ToastManager::new(motion),
            motion,
            closed: BTreeSet::new(),
            paused: false,
            shown: signal(Vec::new()),
            armed: None,
            task: None,
            owner: Owner::current(),
            notify,
        })));
        let weak = Rc::downgrade(&controller.0);
        cleanup(move || {
            if let Some(state) = weak.upgrade()
                && let Some(task) = state.borrow_mut().task.take()
            {
                task.cancel();
            }
        });
        controller
    }
    fn update(&self, apply: impl FnOnce(&mut State, Instant)) {
        let at = now();
        let (events, notify, shown, visible) = {
            let mut state = self.0.borrow_mut();
            let events = state.advance(at);
            apply(&mut state, at);
            let visible = state
                .manager
                .iter()
                .filter_map(|(id, wake, phase)| (!wake.borrow().cancelled).then_some((*id, phase)))
                .collect::<Vec<_>>();
            (events, state.notify.clone(), state.shown, visible)
        };
        if shown.get_untracked() != visible {
            shown.set(visible);
        }
        self.arm();
        for id in events {
            notify(id);
        }
    }
    fn arm(&self) {
        let mut state = self.0.borrow_mut();
        let deadline = state
            .manager
            .iter()
            .filter_map(|(_, wake, _)| wake.borrow().deadline)
            .min();
        if deadline == state.armed {
            return;
        }
        if let Some(task) = state.task.take() {
            task.cancel();
        }
        state.armed = deadline;
        if let Some(deadline) = deadline {
            let weak = Rc::downgrade(&self.0);
            state.task = Some(state.owner.run(|| {
                set_timeout(deadline.saturating_duration_since(now()), move || {
                    if let Some(state) = weak.upgrade() {
                        {
                            let mut state = state.borrow_mut();
                            state.armed = None;
                            state.task = None;
                        }
                        Controller(state).update(|_, _| {});
                    }
                })
            }));
        }
    }
    fn reconcile(&self, members: Vec<Member>, lookup: &Lookup) {
        self.update(|state, at| {
            let retained = members
                .iter()
                .map(|member| member.identity)
                .collect::<BTreeSet<_>>();
            let attached = members
                .iter()
                .filter(|member| member.attached)
                .map(|member| member.identity)
                .collect::<BTreeSet<_>>();
            let cancelled = state
                .manager
                .iter()
                .filter_map(|(id, _, _)| (!attached.contains(id)).then_some(*id))
                .collect::<Vec<_>>();
            for id in cancelled {
                state.close(id, at, true);
            }
            state.closed.retain(|id| retained.contains(id));
            for id in attached {
                if state.closed.contains(&id) || state.manager.get(&id).is_some() {
                    continue;
                }
                let Some(node) = lookup(id) else {
                    continue;
                };
                // Preserve the former desktop default; zero means persistent.
                // Duration is captured once, so content/value patches never
                // restart or replace the native notification's timeout.
                let millis = node
                    .get_untracked()
                    .props
                    .get("duration")
                    .and_then(serde_json::Value::as_u64)
                    .unwrap_or(4000);
                let duration = (millis != 0).then_some(Duration::from_millis(millis));
                state.manager.push(
                    id,
                    Rc::new(RefCell::new(Wake {
                        remaining: duration,
                        deadline: Some(at + state.motion.duration),
                        cancelled: false,
                    })),
                    ToastOptions::timeout(duration),
                    at,
                );
            }
        });
    }
    fn pause(&self, paused: bool) {
        if self.0.borrow().paused == paused {
            return;
        }
        self.update(|state, at| {
            for (_, wake, phase) in state.manager.iter() {
                if phase != Phase::Present {
                    continue;
                }
                let mut wake = wake.borrow_mut();
                if paused {
                    wake.remaining = wake
                        .deadline
                        .take()
                        .map(|deadline| deadline.saturating_duration_since(at));
                } else {
                    wake.deadline = wake.remaining.map(|left| at + left);
                }
            }
            state.paused = paused;
        });
    }
    fn dismiss(&self, id: ChildIdentity) {
        self.update(|state, at| state.close(id, at, false));
    }
    fn newest(&self) {
        let newest = self
            .0
            .borrow()
            .manager
            .iter()
            .rev()
            .find_map(|(id, wake, phase)| {
                (phase != Phase::Ending && !wake.borrow().cancelled).then_some(*id)
            });
        if let Some(id) = newest {
            self.dismiss(id);
        }
    }
}

#[derive(Clone)]
struct ToastContext {
    phase: Memo<Phase>,
    dismiss: Rc<dyn Fn()>,
}

pub(crate) fn host(
    members: Signal<Vec<Member>>,
    viewport: Signal<Size<Points>>,
    lookup: Lookup,
    render: Render,
    notify: Notify,
) -> AnyElement {
    let controller = Controller::new(notify);
    let shown = controller.0.borrow().shown;
    let reconcile = controller.clone();
    effect(move || {
        let members = members.get();
        untracked(|| reconcile.reconcile(members, &lookup));
    });
    let stack = nsh_base::ToastStackState::new();
    let reference = element_ref();
    let focused = signal(false);
    reference.on_focus_in(move || focused.set(true));
    reference.on_focus_out(move || focused.set(false));
    let pausing = controller.clone();
    effect(move || {
        let paused = stack.is_expanded() || focused.get();
        untracked(|| pausing.pause(paused));
    });
    let cancelling = controller.clone();
    overlay()
        .absolute()
        .bottom(px(16.0))
        .right(px(16.0))
        .w(move || px((viewport.get().width.0 - 32.0).clamp(0.0, 384.0)))
        .pointer_events(PointerEvents::BoxNone)
        .child(
            nsh_base::toast_stack()
                .placement(nsh_base::Anchor::BottomRight)
                .element_ref(&reference)
                .state(stack)
                .on_cancel(move || cancelling.newest())
                .child(each(
                    shown,
                    |(id, _)| *id,
                    move |item, _| {
                        let id = item.get_untracked().0;
                        let controller = controller.clone();
                        provide_context(ToastContext {
                            phase: computed(move || item.get().1),
                            dismiss: Rc::new(move || controller.dismiss(id)),
                        });
                        render(id)
                    },
                )),
        )
        .into_element()
}

pub(super) fn element(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    presentation: Presentation,
) -> AnyElement {
    let context =
        use_context::<ToastContext>().expect("Toast belongs to the native notification stack");
    let theme = presentation.theme;
    let dismiss = context.dismiss;
    let body = presentation.component(
        nsh_base::Toast::element(nsh_base::ToastProps {
            transition_status: Prop::bind(move || context.phase.get()),
            accessibility_label: Prop::bind(move || {
                let current = node.get();
                let name = current.string("accessibility-label");
                Some(if name.is_empty() {
                    "Notification".into()
                } else {
                    name.to_owned().into()
                })
            }),
            starting_class: Some("opacity-0 translate-y-4".into()).into(),
            ending_class: Some("opacity-0 scale-95".into()).into(),
            ..Default::default()
        })
        .on_event(move |event: &nsh_base::ToastEvent| match event {
            nsh_base::ToastEvent::DismissRequest => dismiss(),
        })
        .w_full()
        .flex_row()
        .items_center()
        .gap(px(12.0))
        .p(px(12.0))
        .rounded(move || ui::radius(theme))
        .border_1()
        .border_color(move || ui::color(theme, "border"))
        .bg(move || ui::color(theme, "card"))
        .text_color(move || ui::color(theme, "card-foreground"))
        .shadow_lg()
        .transition_all()
        .duration(200.0)
        .child(children),
    );
    // Toast's typed props own its swipe. This one observation-only host routes
    // the canonical pointer enter/leave events without a second gesture owner.
    let host = view().min_w_0();
    match presentation.events {
        Some(events) => events.attach(host),
        None => host,
    }
    .child(body)
    .into_element()
}

#[cfg(test)]
mod tests;
