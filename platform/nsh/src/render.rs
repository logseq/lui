//! Retained LUI nodes rendered through public NSH elements and bindings.
use crate::{
    events::{Capabilities, NativeEvents},
    store::{Node, Store, Transaction},
    style::{self, ThemeView},
    ui, virtual_rows,
    wire::Batch,
};
use nsh_core::{
    element::create_root,
    geometry::{Bounds, Points, Size},
    prelude::*,
};
use serde_json::Value;
use std::{
    cell::{Cell, RefCell},
    collections::{BTreeMap, BTreeSet},
    rc::Rc,
    sync::Arc,
};

pub use crate::events::{PointerDetail, PointerKind};

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Press(u64),
    NativePress(u64, i32),
    LongPress(u64),
    DoublePress(u64),
    PointerEnter(u64),
    PointerLeave(u64),
    Pointer {
        node: u64,
        kind: PointerKind,
        detail: PointerDetail,
    },
    Text(u64, String),
    Submit(u64),
    Toggle(u64, bool),
    Value(u64, f64),
    Focus(u64),
    Blur(u64),
    Appear(u64),
    Load(u64),
    Change(u64),
    Dismiss(u64),
    Picked(u64, String),
    ScrollCompleted {
        node: u64,
        incarnation: u64,
        token: u64,
        outcome: String,
    },
    VisibleRange {
        node: u64,
        incarnation: u64,
        first: i64,
        last: i64,
    },
    VirtualWindow {
        node: u64,
        incarnation: u64,
        generation: u64,
        first: usize,
        last: usize,
        pins: Vec<u64>,
    },
}
struct Entry {
    owner: Owner,
    node: Signal<Arc<Node>>,
    children: Signal<Vec<(u64, u64)>>,
    reference: ElementRef,
    theme: Signal<Arc<ThemeView>>,
    popup: Signal<Option<(u64, u64)>>,
    capabilities: Rc<Cell<Option<Capabilities>>>,
}
struct State {
    store: Store,
    nodes: BTreeMap<u64, Entry>,
    root: Signal<Option<(u64, u64)>>,
    owner: Owner,
    dispatch: Rc<dyn Fn(Event, Renderer)>,
    error: Signal<Option<String>>,
    base_theme: Arc<ThemeView>,
    viewport: Signal<Size<Points>>,
    toast_ids: BTreeSet<u64>,
    toasts: Signal<Vec<crate::controls::toasts::Member>>,
}
#[derive(Clone)]
pub struct Renderer(Rc<RefCell<State>>);
impl Renderer {
    pub fn new(dispatch: impl Fn(Event, Renderer) + 'static) -> Self {
        Self(Rc::new(RefCell::new(State {
            store: Store::default(),
            nodes: BTreeMap::new(),
            root: signal(None),
            owner: Owner::current(),
            dispatch: Rc::new(dispatch),
            error: signal(None),
            base_theme: Arc::new(ThemeView::new(tokens(), dark(), reduce_motion())),
            viewport: signal(Size::default()),
            toast_ids: BTreeSet::new(),
            toasts: signal(Vec::new()),
        })))
    }
    pub fn apply(&self, patch: Batch) -> Result<(), String> {
        self.publish(patch, false)
    }
    pub fn replace(&self, patch: Batch) -> Result<(), String> {
        self.publish(patch, true)
    }
    pub fn set_root(&self, id: i64) -> Result<(), String> {
        let id = u64::try_from(id).map_err(|_| "invalid application root")?;
        let (root, signal, toasts, members) = {
            let mut state = self.0.borrow_mut();
            state.store.set_root(id)?;
            (
                (id, state.store.nodes[&id].incarnation),
                state.root,
                state.toasts,
                toast_members(&state),
            )
        };
        batch(|| {
            signal.set(Some(root));
            if toasts.get_untracked() != members {
                toasts.set(members);
            }
        });
        Ok(())
    }
    fn publish(&self, patch: Batch, snapshot: bool) -> Result<(), String> {
        let (updates, theme_updates, popup_updates, removed, root, root_signal, toasts) = {
            let mut state = self.0.borrow_mut();
            let previous_root = state.store.root();
            let viewport = state.viewport.get_untracked();
            let base = state.base_theme.clone();
            let State { store, nodes, .. } = &mut *state;
            let themes = RefCell::new(BTreeMap::new());
            let inspect = |transaction: &Transaction<'_>| {
                *themes.borrow_mut() = validate_themes(transaction, nodes, &base, viewport)?;
                Ok(())
            };
            let changes = if snapshot {
                store.apply_snapshot_inspected(patch, validate, inspect)?
            } else {
                store.apply_inspected(patch, validate, inspect)?
            };
            let themes = themes.into_inner();
            // Toast is source metadata outside ordinary flow. Only structural
            // edits update this sparse index; editor/content patches do not
            // scan the tree or restart the notification's lifecycle.
            let toast_structure = snapshot
                || previous_root != state.store.root()
                || !changes.removed.is_empty()
                || changes.updated.iter().any(|id| {
                    let next = &state.store.nodes[id];
                    state.nodes.get(id).is_none_or(|entry| {
                        let old = entry.node.get_untracked();
                        old.parent != next.parent || !Arc::ptr_eq(&old.children, &next.children)
                    })
                });
            for id in &changes.removed {
                state.toast_ids.remove(id);
            }
            for id in &changes.updated {
                if state.store.nodes[id].kind == "toast" {
                    state.toast_ids.insert(*id);
                } else {
                    state.toast_ids.remove(id);
                }
            }
            let mut updates = Vec::new();
            let mut removed = Vec::new();
            for id in changes.updated {
                let node = state.store.nodes[&id].clone();
                let child_identities = || {
                    displayed_children(&node, &state.store)
                        .into_iter()
                        .map(|id| (id, state.store.nodes[&id].incarnation))
                        .collect()
                };
                if let Some(entry) = state
                    .nodes
                    .get(&id)
                    .filter(|entry| entry.node.get_untracked().incarnation == node.incarnation)
                {
                    let children =
                        (!Arc::ptr_eq(&entry.node.get_untracked().children, &node.children))
                            .then(|| (entry.children, child_identities()));
                    updates.push((entry.node, node, children));
                } else {
                    let children = child_identities();
                    let theme = themes.get(&id).expect("validated theme").clone();
                    let popup = picker_popup(&node, &state.store);
                    let (owner, (node, children, reference, theme, popup)) =
                        state.owner.run(|| {
                            create_root(|| {
                                (
                                    signal(node),
                                    signal(children),
                                    element_ref(),
                                    signal(theme),
                                    signal(popup),
                                )
                            })
                        });
                    if let Some(entry) = state.nodes.insert(
                        id,
                        Entry {
                            owner,
                            node,
                            children,
                            reference,
                            theme,
                            popup,
                            capabilities: Rc::new(Cell::new(None)),
                        },
                    ) {
                        removed.push(entry);
                    }
                }
            }
            removed.extend(
                changes
                    .removed
                    .into_iter()
                    .filter_map(|id| state.nodes.remove(&id)),
            );
            let theme_updates = themes
                .into_iter()
                .filter_map(|(id, theme)| {
                    let entry = state.nodes.get(&id)?;
                    (entry.theme.get_untracked() != theme).then_some((entry.theme, theme))
                })
                .collect::<Vec<_>>();
            // Only structurally changed parent sequences can change a sibling
            // popup association. Ordinary value edits do not scan the tree.
            let mut popup_candidates = BTreeSet::new();
            for (signal, node, children) in &updates {
                if children.is_some() && matches!(node.kind.as_str(), "select" | "combobox") {
                    popup_candidates.insert(node.id);
                }
                if children.is_some() {
                    for id in node.children.iter() {
                        if state
                            .store
                            .nodes
                            .get(id)
                            .is_some_and(|n| matches!(n.kind.as_str(), "select" | "combobox"))
                        {
                            popup_candidates.insert(*id);
                        }
                    }
                }
                let _ = signal;
            }
            let popup_updates = popup_candidates
                .into_iter()
                .filter_map(|id| {
                    let entry = state.nodes.get(&id)?;
                    let popup = picker_popup(&state.store.nodes[&id], &state.store);
                    (entry.popup.get_untracked() != popup).then_some((entry.popup, popup))
                })
                .collect::<Vec<_>>();
            (
                updates,
                theme_updates,
                popup_updates,
                removed,
                state
                    .store
                    .root()
                    .map(|id| (id, state.store.nodes[&id].incarnation)),
                state.root,
                toast_structure.then(|| (state.toasts, toast_members(&state))),
            )
        };
        batch(|| {
            for (signal, popup) in popup_updates {
                signal.set(popup);
            }
            for (signal, theme) in theme_updates {
                signal.set(theme);
            }
            for (signal, node, children) in updates {
                signal.set(node);
                if let Some((child_signal, identities)) = children {
                    child_signal.set(identities);
                }
            }
            root_signal.set(root);
            if let Some((signal, members)) = toasts
                && signal.get_untracked() != members
            {
                signal.set(members);
            }
            for entry in removed {
                entry.owner.dispose();
            }
        });
        Ok(())
    }
    pub fn element(&self) -> impl IntoElement + use<> {
        let root = self.0.borrow().root;
        let renderer = self.clone();
        let error = self.0.borrow().error;
        let viewport = self.0.borrow().viewport;
        let theming = self.clone();
        let inherited_theme = signal(self.0.borrow().base_theme.clone());
        let members = self.0.borrow().toasts;
        let toast_lookup = self.clone();
        let toast_render = self.clone();
        let toast_events = self.clone();
        let toast_host = crate::controls::toasts::host(
            members,
            viewport,
            Rc::new(move |(id, incarnation)| {
                let state = toast_lookup.0.borrow();
                state.nodes.get(&id).and_then(|entry| {
                    (entry.node.get_untracked().incarnation == incarnation).then_some(entry.node)
                })
            }),
            Rc::new(move |(id, _)| toast_render.node(id)),
            Rc::new(move |(id, incarnation)| {
                if members
                    .get_untracked()
                    .iter()
                    .any(|member| member.identity == (id, incarnation) && member.attached)
                {
                    toast_events.emit(id, incarnation, Event::Dismiss(id));
                }
            }),
        );
        effect(move || {
            let theme = Arc::new(ThemeView::new(tokens(), dark(), reduce_motion()));
            if let Err(error) = theming.refresh_theme(theme.clone()) {
                theming.fail(error);
            } else {
                inherited_theme.set(theme);
            }
        });
        view()
            .flex_1()
            .text_color(move || ui::color(inherited_theme, "foreground"))
            .on_layout(move |bounds: &Bounds<Points>| {
                if viewport.get_untracked() != bounds.size {
                    viewport.set(bounds.size);
                }
            })
            .child(dynamic(move || {
                root.get().and_then(|(id, _)| {
                    let toast = renderer
                        .0
                        .borrow()
                        .store
                        .nodes
                        .get(&id)
                        .is_some_and(|node| node.kind == "toast");
                    (!toast).then(|| renderer.node(id))
                })
            }))
            .child(toast_host)
            .child(dynamic(move || {
                error
                    .get()
                    .map(|message| text(message).test_id("lui-backend-error"))
            }))
    }
    pub fn fail(&self, message: String) {
        self.0.borrow().error.set(Some(message));
    }
    fn refresh_theme(&self, base: Arc<ThemeView>) -> Result<(), String> {
        let updates = {
            let mut state = self.0.borrow_mut();
            if state.base_theme == base {
                return Ok(());
            }
            let mut resolved = BTreeMap::new();
            let viewport = state.viewport.get_untracked();
            for node in state.store.nodes.values() {
                let theme = resolve_theme(
                    node.id,
                    &|id| {
                        state
                            .store
                            .nodes
                            .get(&id)
                            .map(Arc::as_ref)
                            .ok_or_else(|| format!("unknown node {id}"))
                    },
                    &base,
                    &mut resolved,
                    |_| None,
                )?;
                style::compile(node, &theme, viewport)?;
            }
            let updates = resolved
                .into_iter()
                .filter_map(|(id, theme)| {
                    let entry = state.nodes.get(&id)?;
                    (entry.theme.get_untracked() != theme).then_some((entry.theme, theme))
                })
                .collect::<Vec<_>>();
            state.base_theme = base;
            updates
        };
        batch(|| {
            for (signal, theme) in updates {
                signal.set(theme);
            }
        });
        Ok(())
    }
    pub(crate) fn current_incarnation(&self, node: u64) -> Option<u64> {
        self.0
            .borrow()
            .store
            .nodes
            .get(&node)
            .map(|node| node.incarnation)
    }
    pub(crate) fn is_current(&self, node: u64, incarnation: u64, generation: Option<u64>) -> bool {
        self.0.borrow().store.nodes.get(&node).is_some_and(|node| {
            node.incarnation == incarnation
                && generation.is_none_or(|generation| {
                    node.props.get("virtual-generation").and_then(Value::as_u64) == Some(generation)
                })
        })
    }
    fn maintain(&self, id: u64, incarnation: u64, event: Event) {
        let generation = match &event {
            Event::VirtualWindow { generation, .. } => Some(*generation),
            _ => None,
        };
        if !self.is_current(id, incarnation, generation) {
            return;
        }
        let dispatch = self.0.borrow().dispatch.clone();
        dispatch(event, self.clone());
    }
    fn emit(&self, id: u64, incarnation: u64, event: Event) {
        let dispatch = {
            let state = self.0.borrow();
            let Some(node) = state.store.nodes.get(&id) else {
                return;
            };
            if node.incarnation != incarnation {
                return;
            }
            let flag = match &event {
                Event::Press(_) | Event::NativePress(..) => Some("press-enabled"),
                Event::LongPress(_) => Some("long-press-enabled"),
                Event::DoublePress(_) => Some("double-press-enabled"),
                Event::PointerEnter(_) | Event::PointerLeave(_) | Event::Pointer { .. } => {
                    Some("pointer-enabled")
                }
                Event::Text(..) | Event::Value(..) | Event::Change(_) => Some("change-enabled"),
                Event::Submit(_) => Some("submit-enabled"),
                Event::Toggle(..) => Some("toggle-enabled"),
                Event::Focus(_) | Event::Blur(_) => Some("focus-within-enabled"),
                Event::Appear(_) => Some("appear-enabled"),
                _ => None,
            };
            if (!matches!(
                event,
                Event::Appear(_) | Event::Load(_) | Event::Focus(_) | Event::Blur(_)
            ) && !node.boolean("enabled", true))
                || flag.is_some_and(|flag| !node.boolean(flag, false))
            {
                return;
            }
            state.dispatch.clone()
        };
        dispatch(event, self.clone());
    }
    fn popup_anchor(&self, node: &Node) -> Option<ElementRef> {
        let state = self.0.borrow();
        if !node.string("anchor-target").is_empty() {
            return state
                .store
                .nodes
                .values()
                .find(|target| {
                    target.string("accessibility-identifier") == node.string("anchor-target")
                })
                .and_then(|target| state.nodes.get(&target.id))
                .map(|entry| entry.reference);
        }
        let parent = state.store.nodes.get(&node.parent?)?;
        let index = parent.children.iter().position(|id| *id == node.id)?;
        let target = if index > 0 {
            parent.children[index - 1]
        } else {
            parent.id
        };
        state.nodes.get(&target).map(|entry| entry.reference)
    }
    fn tree_source(&self, (id, incarnation): (u64, u64)) -> Option<crate::controls::tree::Source> {
        let state = self.0.borrow();
        if state.store.nodes.get(&id)?.incarnation != incarnation {
            return None;
        }
        let entry = state.nodes.get(&id)?;
        Some(crate::controls::tree::Source {
            node: entry.node,
            children: entry.children,
        })
    }

    fn child_renderer(&self, id: u64, incarnation: u64) -> Option<crate::controls::ChildRenderer> {
        let identities = {
            let state = self.0.borrow();
            if state.store.nodes.get(&id)?.incarnation != incarnation {
                return None;
            }
            state.nodes.get(&id)?.children
        };
        let rendering = self.clone();
        let reading = self.clone();
        let pressing = self.clone();
        Some(crate::controls::ChildRenderer {
            identities,
            render: Rc::new(move |(id, incarnation)| {
                if rendering.is_current(id, incarnation, None) {
                    rendering.node(id)
                } else {
                    view().into_element()
                }
            }),
            lookup: Rc::new(move |(id, incarnation)| {
                let state = reading.0.borrow();
                (state.store.nodes.get(&id)?.incarnation == incarnation)
                    .then(|| state.nodes.get(&id).map(|entry| entry.node))
                    .flatten()
            }),
            press: Rc::new(move |(id, incarnation)| {
                pressing.emit(id, incarnation, Event::Press(id));
            }),
        })
    }

    fn node(&self, id: u64) -> AnyElement {
        let (state, children, reference, theme, viewport, popup) = {
            let renderer = self.0.borrow();
            let entry = &renderer.nodes[&id];
            (
                entry.node,
                entry.children,
                entry.reference,
                entry.theme,
                renderer.viewport,
                entry.popup,
            )
        };
        let node = state.get_untracked();
        let incarnation = node.incarnation;
        let child_renderer = matches!(
            node.kind.as_str(),
            "stack"
                | "overlay"
                | "edge-inset"
                | "view-that-fits"
                | "alert"
                | "bubble"
                | "drawer"
                | "split"
                | "resizable"
                | "tree"
                | "list-item"
                | "bottom-tabs"
                | "breadcrumb"
                | "stepper"
                | "context-menu"
        )
        .then(|| self.child_renderer(id, incarnation))
        .flatten();
        let installed = self.0.borrow().nodes[&id].capabilities.clone();
        let notifying = self.clone();
        let current = self.clone();
        let native_events = NativeEvents::new(
            state,
            Rc::new(move |event| notifying.emit(id, incarnation, event)),
            installed,
            Rc::new(move || current.is_current(id, incarnation, None)),
            use_context::<crate::events::VisibilityScope>(),
        );
        native_events.appear(reference);
        native_events.focus(reference);
        let key = format!("lui-{id}-{incarnation}");
        let identifier = if node.string("accessibility-identifier").is_empty() {
            format!("lui-{id}")
        } else {
            node.string("accessibility-identifier").to_owned()
        };
        let style = move || {
            let node = state.get();
            let size = if style::uses_viewport(&node) {
                viewport.get()
            } else {
                Size::default()
            };
            style::compile(&node, &theme.get(), size).expect("atomically validated NSH style")
        };
        let label = move || {
            let node = state.get();
            let label = node.string("accessibility-label");
            if label.is_empty() {
                node.string("label").to_owned()
            } else {
                label.to_owned()
            }
        };
        let renderer = self.clone();
        let body = each(
            children,
            |identity| *identity,
            move |identity, _| renderer.node(identity.get_untracked().0),
        );
        if matches!(node.kind.as_str(), "popover" | "tooltip") {
            let anchor = self.popup_anchor(&node);
            let events = self.clone();
            return crate::controls::anchored_popup(
                state,
                body.into_element(),
                anchor,
                Rc::new(move |event| events.emit(id, incarnation, event)),
                crate::controls::Presentation {
                    key: key.into(),
                    test_id: identifier.into(),
                    style: Rc::new(style),
                    reference,
                    theme,
                    events: Some(native_events.clone()),
                    children: child_renderer.clone(),
                },
            );
        }
        if matches!(node.kind.as_str(), "select" | "combobox" | "menu-trigger") {
            let rendering = self.clone();
            let events = native_events.clone();
            let popup_events = self.clone();
            let submenu = node
                .parent
                .and_then(|id| {
                    self.0
                        .borrow()
                        .store
                        .nodes
                        .get(&id)
                        .map(|p| p.kind == "dropdown-menu")
                })
                .unwrap_or(false);
            return crate::controls::picker(
                state,
                popup,
                body.into_element(),
                crate::controls::PopupCallbacks {
                    render: Rc::new(move |id| rendering.node(id)),
                    dismiss: Rc::new(move |popup| {
                        if let Some(incarnation) = popup_events.current_incarnation(popup) {
                            popup_events.emit(popup, incarnation, Event::Dismiss(popup));
                        }
                    }),
                },
                Rc::new(move |event| events.semantic(event)),
                submenu,
                crate::controls::Presentation {
                    key: key.into(),
                    test_id: identifier.into(),
                    style: Rc::new(style),
                    reference,
                    theme,
                    events: Some(native_events.clone()),
                    children: child_renderer.clone(),
                },
            );
        }
        if node.kind == "tree" {
            let lookup = self.clone();
            let dispatch = self.clone();
            return crate::controls::tree::element(
                state,
                children,
                crate::controls::tree::Callbacks {
                    lookup: Rc::new(move |identity| lookup.tree_source(identity)),
                    emit: Rc::new(move |(id, incarnation), event| {
                        dispatch.emit(id, incarnation, event)
                    }),
                },
                crate::controls::Presentation {
                    key: key.into(),
                    test_id: identifier.into(),
                    style: Rc::new(style),
                    reference,
                    theme,
                    events: Some(native_events),
                    children: None,
                },
            );
        }
        if crate::controls::supported(&node.kind) {
            let events = self.clone();
            return crate::controls::element(
                state,
                body.into_element(),
                Rc::new(move |event| events.emit(id, incarnation, event)),
                crate::controls::Presentation {
                    key: key.into(),
                    test_id: identifier.into(),
                    style: Rc::new(style),
                    reference,
                    theme,
                    events: Some(native_events.clone()),
                    children: child_renderer,
                },
            )
            .expect("supported NSH control");
        }
        let result = match node.kind.as_str() {
            "file-picker" => {
                let events = self.clone();
                native_events
                    .attach(crate::file_picker::element(
                        state,
                        body.into_element(),
                        Rc::new(move |event| events.emit(id, incarnation, event)),
                    ))
                    .state_inline_style(style)
                    .element_ref(&reference)
                    .key(key.clone())
                    .test_id(&identifier)
                    .into_element()
            }
            "media-surface" => {
                let failing = self.clone();
                native_events
                    .attach(crate::media::element(
                        state,
                        Rc::new(move |message| {
                            if failing.is_current(id, incarnation, None) {
                                failing.fail(message);
                            }
                        }),
                    ))
                    .label(label)
                    .state_inline_style(style)
                    .element_ref(&reference)
                    .key(key.clone())
                    .test_id(&identifier)
                    .into_element()
            }
            "heading" => native_events
                .attach(crate::headings::element(state))
                .state_inline_style(style)
                .selectable(move || state.get().string("user-select") != "none")
                .element_ref(&reference)
                .key(key.clone())
                .test_id(&identifier)
                .into_element(),
            "text" | "paragraph" | "label" | "kbd" => native_events
                .attach(text(move || {
                    SharedString::from(state.get().string("text").to_owned())
                }))
                .state_inline_style(style)
                .selectable(move || state.get().string("user-select") != "none")
                .element_ref(&reference)
                .key(key.clone())
                .test_id(&identifier)
                .into_element(),
            "text-field" | "secure-field" | "input" | "search-field" | "textarea" => {
                let change = self.clone();
                let submit = self.clone();
                native_events
                    .attach(crate::inputs::attach(
                        ui::input(theme),
                        state,
                        Rc::new(move |event| submit.emit(id, incarnation, event)),
                    ))
                    .value(move || state.get().string("text").to_owned())
                    .placeholder(move || state.get().string("placeholder").to_owned())
                    .masked(node.kind == "secure-field")
                    .multiline(node.kind == "textarea")
                    .readonly(move || state.get().boolean("read-only", false))
                    .disabled(move || !state.get().boolean("enabled", true))
                    .auto_focus(move || state.get().boolean("autofocus", false))
                    .label(label)
                    .state_inline_style(style)
                    .on_change(move |value: &str| {
                        change.emit(id, incarnation, Event::Text(id, value.into()))
                    })
                    .element_ref(&reference)
                    .key(key.clone())
                    .test_id(&identifier)
                    .into_element()
            }
            "checkbox" => {
                let events = self.clone();
                let props = nsh_base::CheckboxProps {
                    checked: Prop::bind(move || state.get().boolean("checked", false)),
                    indeterminate: Prop::bind(move || state.get().boolean("indeterminate", false)),
                    disabled: Prop::bind(move || !state.get().boolean("enabled", true)),
                    accessibility_label: Prop::bind(move || Some(label().into())),
                    ..Default::default()
                };
                ui::checkbox(props, theme)
                    .state_inline_style(style)
                    .on_event(move |event: &nsh_base::CheckboxEvent| {
                        let nsh_base::CheckboxEvent::Change(checked) = event;
                        events.emit(id, incarnation, Event::Toggle(id, *checked));
                    })
                    .child(text(move || {
                        SharedString::from(state.get().string("text").to_owned())
                    }))
                    .child(body)
                    .element_ref(&reference)
                    .key(key.clone())
                    .test_id(&identifier)
                    .into_element()
            }
            "virtual-list" => {
                let rendering = self.clone();
                let maintaining = self.clone();
                let failing = self.clone();
                let resolving = self.clone();
                let referring = self.clone();
                native_events
                    .attach(virtual_rows::element(
                        state,
                        children,
                        reference,
                        virtual_rows::Callbacks {
                            render: Rc::new(move |(id, incarnation)| {
                                if rendering.is_current(id, incarnation, None) {
                                    rendering.node(id)
                                } else {
                                    view().into_element()
                                }
                            }),
                            resolve_target: Rc::new(move |target| {
                                let state = resolving.0.borrow();
                                let parent = state.store.nodes.get(&id)?;
                                if parent.incarnation != incarnation {
                                    return None;
                                }
                                parent.children.iter().position(|child| {
                                    state
                                        .store
                                        .nodes
                                        .get(child)
                                        .is_some_and(|node| node.string("key") == target)
                                })
                            }),
                            row_ref: Rc::new(move |(id, incarnation)| {
                                let state = referring.0.borrow();
                                let entry = state.nodes.get(&id)?;
                                (entry.node.get_untracked().incarnation == incarnation
                                    && entry.reference.node().is_some())
                                .then_some(entry.reference)
                            }),
                            notify: Rc::new(move |feedback| {
                                let event = match feedback {
                                    virtual_rows::Feedback::Window(window) => {
                                        Event::VirtualWindow {
                                            node: id,
                                            incarnation,
                                            generation: window.generation,
                                            first: window.first,
                                            last: window.last,
                                            pins: window.pins,
                                        }
                                    }
                                    virtual_rows::Feedback::Scroll { token, outcome } => {
                                        Event::ScrollCompleted {
                                            node: id,
                                            incarnation,
                                            token,
                                            outcome: outcome.into(),
                                        }
                                    }
                                    virtual_rows::Feedback::Visible(range) => Event::VisibleRange {
                                        node: id,
                                        incarnation,
                                        first: range.map_or(0, |(first, _)| first as i64),
                                        last: range.map_or(-1, |(_, last)| last as i64),
                                    },
                                };
                                maintaining.maintain(id, incarnation, event);
                            }),
                            failed: Rc::new(move |error| failing.fail(error)),
                        },
                    ))
                    .state_inline_style(style)
                    .key(key.clone())
                    .test_id(&identifier)
                    .into_element()
            }
            "scroll" => native_events
                .attach(scroll())
                .state_inline_style(style)
                .child(body)
                .element_ref(&reference)
                .key(key.clone())
                .test_id(&identifier)
                .into_element(),
            "image" => {
                let loading = self.clone();
                native_events
                    .attach(
                        image(move || crate::images::source(&state.get()))
                            .object_fit(move || crate::images::fit(&state.get()))
                            .label(move || crate::images::label(&state.get()))
                            .on_load(move |_: &Size<nsh_core::geometry::DevicePixels>| {
                                loading.emit(id, incarnation, Event::Load(id));
                            }),
                    )
                    .state_inline_style(style)
                    .element_ref(&reference)
                    .key(key.clone())
                    .test_id(&identifier)
                    .into_element()
            }
            "root" | "row" | "column" | "box" | "panel" | "card" | "spacer" | "dropdown-menu" => {
                native_events
                    .attach(view())
                    .state_inline_style(style)
                    .child(body)
                    .element_ref(&reference)
                    .key(key.clone())
                    .test_id(&identifier)
                    .into_element()
            }
            kind => unreachable!("unvalidated NSH component {kind}"),
        };
        // Identity belongs to the actual layout participant.
        result
    }
}

fn validate(node: &Node) -> Result<(), String> {
    if !supported(&node.kind) {
        return Err(format!(
            "NSH component {} is not implemented yet",
            node.kind
        ));
    }
    if node.kind == "box" && node.string("display") == "contents" {
        return Err("NSH box display=contents is not implemented yet".into());
    }
    crate::images::validate(node)?;
    crate::media::validate(node)?;
    crate::inputs::validate(node)?;
    crate::file_picker::validate(node)?;
    crate::virtual_rows::validate(node)?;
    crate::controls::validate(node)
}

fn supported(kind: &str) -> bool {
    crate::controls::supported(kind)
        || matches!(
            kind,
            "root"
                | "file-picker"
                | "media-surface"
                | "select"
                | "combobox"
                | "menu-trigger"
                | "dropdown-menu"
                | "popover"
                | "tooltip"
                | "row"
                | "column"
                | "box"
                | "panel"
                | "card"
                | "spacer"
                | "text"
                | "heading"
                | "paragraph"
                | "label"
                | "kbd"
                | "button"
                | "checkbox"
                | "text-field"
                | "secure-field"
                | "input"
                | "search-field"
                | "textarea"
                | "scroll"
                | "virtual-list"
                | "image"
                | "tree"
        )
}

fn picker_popup(node: &Node, store: &Store) -> Option<(u64, u64)> {
    if !matches!(node.kind.as_str(), "select" | "combobox") {
        return None;
    }
    let own = node
        .children
        .iter()
        .find(|id| {
            store
                .nodes
                .get(id)
                .is_some_and(|node| node.kind == "dropdown-menu")
        })
        .copied();
    let sibling = node
        .parent
        .and_then(|id| store.nodes.get(&id))
        .and_then(|parent| {
            let at = parent.children.iter().position(|id| *id == node.id)?;
            parent.children.get(at + 1).copied().filter(|id| {
                store
                    .nodes
                    .get(id)
                    .is_some_and(|node| node.kind == "dropdown-menu")
            })
        });
    let id = own.or(sibling)?;
    Some((id, store.nodes.get(&id)?.incarnation))
}
fn toast_members(state: &State) -> Vec<crate::controls::toasts::Member> {
    state
        .toast_ids
        .iter()
        .filter_map(|id| {
            let node = state.store.nodes.get(id)?;
            let mut ancestor = Some(*id);
            let mut attached = false;
            while let Some(id) = ancestor {
                if Some(id) == state.store.root() {
                    attached = true;
                    break;
                }
                ancestor = state.store.nodes.get(&id).and_then(|node| node.parent);
            }
            Some(crate::controls::toasts::Member {
                identity: (*id, node.incarnation),
                attached,
            })
        })
        .collect()
}

fn displayed_children(node: &Node, store: &Store) -> Vec<u64> {
    node.children
        .iter()
        .enumerate()
        .filter_map(|(index, id)| {
            let child = store.nodes.get(id)?;
            if child.kind == "toast" {
                return None;
            }
            if child.kind == "dropdown-menu" {
                if matches!(node.kind.as_str(), "select" | "combobox") {
                    return None;
                }
                if index > 0
                    && store
                        .nodes
                        .get(&node.children[index - 1])
                        .is_some_and(|previous| {
                            matches!(previous.kind.as_str(), "select" | "combobox")
                        })
                {
                    return None;
                }
            }
            Some(*id)
        })
        .collect()
}

/// Resolve only the requested ancestor path. An unchanged retained ancestor
/// supplies its stable theme directly; theme changes invalidate its descendants.
fn resolve_theme<'a>(
    id: u64,
    get: &impl Fn(u64) -> Result<&'a Node, String>,
    base: &Arc<ThemeView>,
    cache: &mut BTreeMap<u64, Arc<ThemeView>>,
    retained: impl Fn(u64) -> Option<Arc<ThemeView>>,
) -> Result<Arc<ThemeView>, String> {
    let mut path = Vec::new();
    let mut next = Some(id);
    let mut theme = base.clone();
    while let Some(id) = next {
        if let Some(found) = cache.get(&id).cloned().or_else(|| retained(id)) {
            theme = found;
            break;
        }
        let node = get(id)?;
        path.push(node);
        next = node.parent;
    }
    for node in path.into_iter().rev() {
        if node.props.contains_key("theme") || node.props.contains_key("theme-mode") {
            theme = Arc::new(theme.overlay(node)?);
        }
        cache.insert(node.id, theme.clone());
    }
    // A retained first node needs no path but is still an affected candidate.
    cache.insert(id, theme.clone());
    Ok(theme)
}

fn validate_themes(
    transaction: &Transaction<'_>,
    entries: &BTreeMap<u64, Entry>,
    base: &Arc<ThemeView>,
    viewport: Size<Points>,
) -> Result<BTreeMap<u64, Arc<ThemeView>>, String> {
    let mut invalid = BTreeSet::new();
    let mut pending = Vec::new();
    let mut candidates = BTreeSet::new();
    let mut tree_owners = BTreeMap::new();
    let mut trees = BTreeSet::new();
    for node in transaction.updated() {
        candidates.insert(node.id);
        let tree = native_tree_owner(transaction, node.id, &mut tree_owners)?;
        if let Some(tree) = tree {
            trees.insert(tree);
        }
        if node.string("role") == "treeitem" && tree.is_none() {
            return Err("NSH treeitem metadata must be contained by a native Tree".into());
        }
        let previous = transaction.previous(node.id);
        if let Some(previous) = previous.filter(|previous| previous.incarnation == node.incarnation)
        {
            if tree.is_none() {
                crate::controls::validate_transition(previous, node)?;
            }
        }
        if let Some(entry) = entries.get(&node.id)
            && entry.reference.node().is_some()
            && entry.node.get_untracked().incarnation == node.incarnation
            && let Some(installed) = entry.capabilities.get()
            && !installed.contains(Capabilities::authored(node))
        {
            return Err(
                "NSH enabling an uninstalled native event capability requires remounting the node"
                    .into(),
            );
        }
        if node.kind == "toolbar"
            && previous.is_some_and(|old| {
                old.incarnation == node.incarnation
                    && (old.string("orientation") == "vertical")
                        != (node.string("orientation") == "vertical")
            })
        {
            return Err("NSH changing toolbar orientation requires remounting the toolbar".into());
        }
        if previous.is_none_or(|old| !Arc::ptr_eq(&old.children, &node.children)) {
            validate_dropdown_owners(transaction, node)?;
        }
        let changed = transaction.previous(node.id).is_none_or(|old| {
            old.incarnation != node.incarnation
                || old.parent != node.parent
                || old.props.get("theme") != node.props.get("theme")
                || old.props.get("theme-mode") != node.props.get("theme-mode")
        });
        if changed {
            pending.push(node.id);
        }
    }
    while let Some(id) = pending.pop() {
        if invalid.insert(id) {
            let node = transaction.get(id)?;
            pending.extend(node.children.iter().copied());
            candidates.insert(id);
        }
    }
    for tree in trees {
        let root = transaction.get(tree)?;
        crate::controls::tree::validate_root(root)?;
        crate::controls::tree::validate_source(root, &|id| transaction.get(id))?;
    }
    let mut themes = BTreeMap::new();
    for id in candidates {
        let node = transaction.get(id)?;
        if node.string("role") == "treeitem"
            && native_tree_owner(transaction, id, &mut tree_owners)?.is_none()
        {
            return Err("NSH treeitem metadata must be contained by a native Tree".into());
        }
        validate_popup_shape(transaction, transaction.get(id)?)?;
        let theme = resolve_theme(id, &|id| transaction.get(id), base, &mut themes, |id| {
            let entry = entries.get(&id)?;
            let node = transaction.get(id).ok()?;
            (!invalid.contains(&id) && node.incarnation == entry.node.get_untracked().incarnation)
                .then(|| entry.theme.get_untracked())
        })?;
        style::compile(transaction.get(id)?, &theme, viewport)?;
    }
    Ok(themes)
}

/// Memoize only affected ancestry paths; no store-wide component scan.
fn native_tree_owner(
    transaction: &Transaction<'_>,
    id: u64,
    cache: &mut BTreeMap<u64, Option<u64>>,
) -> Result<Option<u64>, String> {
    let mut pending = Vec::new();
    let mut next = Some(id);
    let found = loop {
        let Some(id) = next else {
            break None;
        };
        if let Some(found) = cache.get(&id) {
            break *found;
        }
        let node = transaction.get(id)?;
        if node.kind == "tree" {
            cache.insert(id, Some(id));
            break Some(id);
        }
        pending.push(id);
        next = node.parent;
    };
    for id in pending {
        cache.insert(id, found);
    }
    Ok(found)
}

/// Ownership depends on adjacency, so structural edits check the final sibling
/// sequence once. Property-only edits keep the already validated relationship.
fn validate_dropdown_owners(transaction: &Transaction<'_>, parent: &Node) -> Result<(), String> {
    let owns_menus = matches!(parent.kind.as_str(), "select" | "combobox" | "menu-trigger");
    let mut previous_is_picker = false;
    for id in parent.children.iter() {
        let child = transaction.get(*id)?;
        if child.kind == "dropdown-menu" && !owns_menus && !previous_is_picker {
            return Err(
                "NSH dropdown-menu requires a select, combobox or menu-trigger owner".into(),
            );
        }
        previous_is_picker = matches!(child.kind.as_str(), "select" | "combobox");
    }
    Ok(())
}

fn validate_popup_shape(transaction: &Transaction<'_>, node: &Node) -> Result<(), String> {
    if matches!(node.kind.as_str(), "popover" | "tooltip") {
        if node.kind == "tooltip" && node.string("anchor").is_empty() {
            return Err("NSH unanchored tooltip status semantics are not implemented yet".into());
        }
        if node.kind == "popover" && node.string("role") == "menu" {
            return Err("NSH externally anchored menu popovers are not implemented yet".into());
        }
        if node.number("anchor-alignment-offset", 0.0) != 0.0 {
            return Err("NSH popup anchor-alignment-offset is not implemented yet".into());
        }
        for property in [
            "x",
            "y",
            "anchor-offset",
            "collision-padding",
            "available-height",
        ] {
            if node
                .props
                .get(property)
                .and_then(Value::as_f64)
                .is_some_and(|number| number.abs() > f32::MAX as f64)
            {
                return Err(format!("NSH popup {property} exceeds native coordinates"));
            }
        }
        if !node.string("anchor-rect").is_empty() {
            crate::controls::popup_rectangle(node.string("anchor-rect"))?;
        }
        if let Some(old) = transaction
            .previous(node.id)
            .filter(|old| old.incarnation == node.incarnation)
            && ["anchor-target", "anchor-rect", "x"].iter().any(|key| {
                if *key == "anchor-target" {
                    old.props.get(*key) != node.props.get(*key)
                } else {
                    old.props.contains_key(*key) != node.props.contains_key(*key)
                }
            })
        {
            return Err("NSH changing popup anchor source requires remounting the popup".into());
        }
    }
    if node.kind == "menu-trigger" {
        if node.children.len() > 1 {
            return Err("NSH menu-trigger supports one dropdown-menu child".into());
        }
        if !node.string("icon").is_empty() {
            return Err("NSH menu-trigger icons are not implemented yet".into());
        }
    }
    if node.kind == "combobox"
        && node.children.iter().any(|id| {
            transaction
                .get(*id)
                .is_ok_and(|child| child.kind != "dropdown-menu")
        })
    {
        return Err("NSH combobox supports retained dropdown-menu children only".into());
    }
    if node.kind != "dropdown-menu" {
        return Ok(());
    }
    if node.parent.is_none() {
        return Err("NSH standalone dropdown-menu requires a picker or menu-trigger owner".into());
    }
    for property in [
        "anchor",
        "anchor-alignment",
        "anchor-offset",
        "x",
        "y",
        "collision-padding",
    ] {
        if node.props.contains_key(property) {
            return Err(format!(
                "NSH dropdown-menu {property} is not implemented yet"
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod theme_tests {
    use super::*;
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::json;
    use std::{cell::Cell, sync::Mutex};

    fn patch(generation: u64, ops: Value) -> Batch {
        Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
    }

    struct ValidationFixture {
        toolbar: bool,
        checked: Arc<Mutex<bool>>,
        presses: Arc<Mutex<Vec<u64>>>,
    }
    #[component]
    fn RetainedValidation() -> impl IntoElement {
        let fixture = engine_context::<ValidationFixture>().unwrap();
        let presses = fixture.presses.clone();
        let renderer = Renderer::new(move |event, renderer| match event {
            Event::Text(id, text) => {
                let generation = renderer.0.borrow().store.generation + 1;
                renderer
                    .apply(patch(
                        generation,
                        json!([
                            {"op":"set-prop","id":id,"property":"text","value":text}
                        ]),
                    ))
                    .unwrap();
            }
            Event::Press(id) => presses.lock().unwrap().push(id),
            _ => {}
        });
        renderer
            .apply(patch(
                1,
                json!([
                    {"op":"create-node","id":1,"kind":"column"},
                    {"op":"create-node","id":2,"kind":"column"},
                    {"op":"create-node","id":10,"kind":"select"},
                    {"op":"set-prop","id":10,"property":"text","value":"Retained picker"},
                    {"op":"create-node","id":20,"kind":"dropdown-menu"},
                    {"op":"insert-child","parent":2,"child":10,"index":0},
                    {"op":"insert-child","parent":2,"child":20,"index":1},
                    {"op":"create-node","id":40,"kind":"text-field"},
                    {"op":"set-prop","id":40,"property":"text","value":"retained"},
                    {"op":"set-prop","id":40,"property":"accessibility-label","value":"Retained editor"},
                    {"op":"set-prop","id":40,"property":"change-enabled","value":true},
                    {"op":"insert-child","parent":1,"child":40,"index":0},
                    {"op":"create-node","id":50,"kind":"toolbar"},
            {"op":"set-prop","id":50,"property":"accessibility-label","value":"Retained actions"},
                    {"op":"set-prop","id":50,"property":"orientation","value":"horizontal"},
                    {"op":"create-node","id":51,"kind":"button"},
                    {"op":"set-prop","id":51,"property":"text","value":"First action"},
                    {"op":"set-prop","id":51,"property":"press-enabled","value":true},
                    {"op":"create-node","id":52,"kind":"button"},
                    {"op":"set-prop","id":52,"property":"text","value":"Second action"},
                    {"op":"set-prop","id":52,"property":"press-enabled","value":true},
                    {"op":"insert-child","parent":50,"child":51,"index":0},
                    {"op":"insert-child","parent":50,"child":52,"index":1},
                    {"op":"insert-child","parent":1,"child":50,"index":1}
                ]),
            ))
            .unwrap();
        renderer.set_root(1).unwrap();
        let checking = renderer.clone();
        on_key_with(
            "f7",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let (generation, before, editor, popup) = {
                    let state = checking.0.borrow();
                    (
                        state.store.generation,
                        state.store.nodes.clone(),
                        state.nodes[&40].reference.node(),
                        state.nodes[&10].popup.get_untracked(),
                    )
                };
                let mut ops = vec![
                    json!({"op":"set-prop","id":40,"property":"text","value":"must not publish"}),
                ];
                if fixture.toolbar {
                    ops.push(json!({"op":"set-prop","id":50,"property":"orientation","value":"vertical"}));
                } else {
                    ops.extend([
                        json!({"op":"create-node","id":30,"kind":"button"}),
                        json!({"op":"set-prop","id":30,"property":"text","value":"Interloper"}),
                        json!({"op":"insert-child","parent":2,"child":30,"index":1}),
                    ]);
                }
                let error = checking
                    .apply(patch(generation + 1, Value::Array(ops)))
                    .unwrap_err();
                assert!(error.contains(if fixture.toolbar {
                    "requires remounting"
                } else {
                    "requires a select"
                }));
                {
                    let state = checking.0.borrow();
                    assert_eq!(state.store.generation, generation);
                    assert_eq!(state.store.nodes.len(), before.len());
                    for (id, node) in &before {
                        assert!(Arc::ptr_eq(node, &state.store.nodes[id]));
                        assert!(Arc::ptr_eq(&node.children, &state.store.nodes[id].children));
                        assert!(Arc::ptr_eq(node, &state.nodes[id].node.get_untracked()));
                    }
                    assert_eq!(state.nodes[&40].reference.node(), editor);
                    assert_eq!(state.nodes[&10].popup.get_untracked(), popup);
                    assert_eq!(state.store.nodes[&2].children.as_slice(), &[10, 20]);
                }
                // A rejected operation consumes no generation; ordinary menu or
                // toolbar presentation edits remain valid without remounting.
                let id = if fixture.toolbar { 50 } else { 20 };
                checking
                    .apply(patch(
                        generation + 1,
                        json!([
                            {"op":"set-prop","id":id,"property":"padding","value":3}
                        ]),
                    ))
                    .unwrap();
                *fixture.checked.lock().unwrap() = true;
            },
        );
        renderer.element()
    }
    type ValidationApp = (Headless, Arc<Mutex<bool>>, Arc<Mutex<Vec<u64>>>);
    fn start_validation(toolbar: bool) -> ValidationApp {
        let checked = Arc::new(Mutex::new(false));
        let presses = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(ValidationFixture {
                toolbar,
                checked: checked.clone(),
                presses: presses.clone(),
            }),
            ..EngineConfig::new(Root::of::<RetainedValidation>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        (Headless::start(config).unwrap(), checked, presses)
    }
    fn editor_id(app: &Headless) -> nsh_core::NodeId {
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("lui-40"))
            .unwrap()
            .id
    }
    #[test]
    fn structural_sibling_insertion_revalidates_existing_menu_ownership_atomically() {
        let (mut app, checked, _) = start_validation(false);
        app.wait_for("id:lui-40").unwrap();
        app.type_text("id:lui-40", " accepted").unwrap();
        let before = editor_id(&app);
        let value = app
            .screen()
            .input_text("id:lui-40")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("f7").unwrap();
        assert!(*checked.lock().unwrap());
        assert_eq!(editor_id(&app), before);
        assert_eq!(
            app.screen().input_text("id:lui-40").unwrap(),
            Some(value.as_str())
        );
        app.type_text("id:lui-40", " after").unwrap();
        assert_eq!(editor_id(&app), before);
    }
    #[test]
    fn toolbar_axis_mutation_is_rejected_without_losing_horizontal_keyboard_state() {
        let (mut app, checked, presses) = start_validation(true);
        app.wait_for("First action").unwrap();
        let before = editor_id(&app);
        app.type_text("id:lui-40", "").unwrap();
        app.press_key("tab").unwrap();
        presses.lock().unwrap().clear();
        app.press_key("f7").unwrap();
        assert!(*checked.lock().unwrap());
        app.press_key("right").unwrap();
        app.press_key("space").unwrap();
        assert_eq!(*presses.lock().unwrap(), [52]);
        assert_eq!(editor_id(&app), before);
        assert_eq!(
            app.screen().input_text("id:lui-40").unwrap(),
            Some("retained")
        );
    }

    #[component]
    fn ScopedTheme() -> impl IntoElement {
        let renderer = Renderer::new(|_, _| {});
        renderer.apply(patch(1, json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":"box"},
            {"op":"set-prop","id":2,"property":"theme","value":r##"{"brand":{"light":"#123456","dark":"#abcdef"}}"##},
            {"op":"set-prop","id":2,"property":"foreground","value":"brand"},
            {"op":"create-node","id":3,"kind":"text"},
            {"op":"set-prop","id":3,"property":"text","value":"Inside"},
            {"op":"create-node","id":4,"kind":"text"},
            {"op":"set-prop","id":4,"property":"text","value":"Outside"},
            {"op":"create-node","id":5,"kind":"box"},
            {"op":"set-prop","id":5,"property":"width-viewport","value":0.5},
            {"op":"set-prop","id":5,"property":"height","value":10},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":1,"child":4,"index":1},
            {"op":"insert-child","parent":1,"child":5,"index":2}
        ]))).unwrap();
        renderer.set_root(1).unwrap();
        let change = renderer.clone();
        let ordinary = renderer.clone();
        let reject = renderer.clone();
        view().flex_1().child(renderer.element())
            .child(text("Theme reference").text_color(move || nsh_base::theme().foreground))
            .child(nsh_base::button().on_press(move || {
                let before = change.0.borrow().nodes[&3].node.get_untracked();
                let sibling = change.0.borrow().nodes[&4].theme.get_untracked();
                change.apply(patch(2, json!([
                    {"op":"set-prop","id":2,"property":"theme-mode","value":"dark"}
                ]))).unwrap();
                assert!(Arc::ptr_eq(&before, &change.0.borrow().nodes[&3].node.get_untracked()));
                assert!(Arc::ptr_eq(&sibling, &change.0.borrow().nodes[&4].theme.get_untracked()));
            }).child(text("Change scope")))
            .child(nsh_base::button().on_press(move || {
                let theme = ordinary.0.borrow().nodes[&3].theme.get_untracked();
                let sibling = ordinary.0.borrow().nodes[&4].node.get_untracked();
                ordinary.apply(patch(3, json!([
                    {"op":"set-prop","id":3,"property":"text","value":"Edited"}
                ]))).unwrap();
                assert!(Arc::ptr_eq(&theme, &ordinary.0.borrow().nodes[&3].theme.get_untracked()));
                assert!(Arc::ptr_eq(&sibling, &ordinary.0.borrow().nodes[&4].node.get_untracked()));
            }).child(text("Ordinary edit")))
            .child(nsh_base::button().on_press(move || {
                let before = reject.0.borrow().nodes[&3].node.get_untracked();
                let theme = reject.0.borrow().nodes[&3].theme.get_untracked();
                assert!(reject.apply(patch(4, json!([
                    {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                    {"op":"set-prop","id":2,"property":"theme","value":r#"{"brand":"missing-color"}"#}
                ]))).is_err());
                assert_eq!(reject.0.borrow().store.generation, 3);
                assert!(Arc::ptr_eq(&before, &reject.0.borrow().nodes[&3].node.get_untracked()));
                assert!(Arc::ptr_eq(&theme, &reject.0.borrow().nodes[&3].theme.get_untracked()));
                reject.apply(patch(4,json!([
                    {"op":"set-prop","id":3,"property":"text","value":"After rejection"}
                ]))).unwrap();
            }).child(text("Reject invalid scope")))
    }

    #[test]
    fn default_text_inherits_live_semantic_foreground_without_remounting() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<ScopedTheme>())).unwrap();
        app.wait_for("text:Outside").unwrap();
        let native = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("lui-4"))
            .unwrap()
            .id;
        let light = app
            .screen()
            .span_style("text:Theme reference")
            .unwrap()
            .color;
        assert_eq!(
            app.screen().span_style("text:Outside").unwrap().color,
            light
        );
        app.set_environment("dark appearance", |environment| {
            environment.color_scheme = nsh_core::platform::ColorScheme::Dark;
        })
        .unwrap();
        app.wait_until(
            "inherited dark text",
            std::time::Duration::from_secs(1),
            |screen| {
                let expected = screen.span_style("text:Theme reference").unwrap().color;
                expected != light && screen.span_style("text:Outside").unwrap().color == expected
            },
        )
        .unwrap();
        assert_eq!(
            app.screen().span_style("text:Inside").unwrap().color,
            nsh_core::Color::parse("#abcdef").unwrap()
        );
        assert!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .any(|node| node.test_id.as_deref() == Some("lui-4") && node.id == native)
        );
    }

    #[test]
    fn scoped_theme_updates_and_ordinary_edits_keep_native_identity_and_sparse_signals() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<ScopedTheme>())).unwrap();
        app.wait_for("text:Inside").unwrap();
        let inside = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("lui-3"))
            .unwrap()
            .id;
        let outside = app.screen().span_style("text:Outside").unwrap().color;
        assert_eq!(
            app.screen().span_style("text:Inside").unwrap().color,
            nsh_core::Color::parse("#123456").unwrap()
        );
        app.press("Change scope").unwrap();
        app.wait_until(
            "scoped dark appearance",
            std::time::Duration::from_secs(1),
            |screen| {
                screen
                    .span_style("text:Inside")
                    .is_ok_and(|style| style.color == nsh_core::Color::parse("#abcdef").unwrap())
            },
        )
        .unwrap();
        assert_eq!(
            app.screen().span_style("text:Outside").unwrap().color,
            outside
        );
        app.press("Ordinary edit").unwrap();
        app.wait_for("text:Edited").unwrap();
        app.press("Reject invalid scope").unwrap();
        app.wait_for("text:After rejection").unwrap();
        assert_eq!(app.screen().count("text:must not publish").unwrap(), 0);
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|n| n.test_id.as_deref() == Some("lui-3"))
                .unwrap()
                .id,
            inside
        );
        let nodes = app.screen().layout_nodes();
        let fractional = nodes
            .iter()
            .find(|n| n.test_id.as_deref() == Some("lui-5"))
            .unwrap();
        let render_root = nodes
            .iter()
            .find(|n| n.parent == nsh_core::ROOT_ID)
            .unwrap();
        assert!(
            (fractional.bounds.size.width.0 - render_root.bounds.size.width.0 * 0.5).abs() < 0.1
        );
    }

    #[derive(Clone)]
    struct SurfaceKind(&'static str);
    #[component]
    fn AuthoredSurface() -> impl IntoElement {
        let kind = engine_context::<SurfaceKind>().unwrap().0;
        let renderer = Renderer::new(|_, _| {});
        renderer
            .apply(patch(
                1,
                json!([
                    {"op":"create-node","id":1,"kind":kind},
                {"op":"set-prop","id":1,"property":"text","value":"Surface"},
                    {"op":"set-prop","id":1,"property":"width","value":320},
                    {"op":"create-node","id":2,"kind":"text"},
                    {"op":"set-prop","id":2,"property":"text","value":"Surface content"},
                    {"op":"insert-child","parent":1,"child":2,"index":0}
                ]),
            ))
            .unwrap();
        renderer.set_root(1).unwrap();
        renderer.element()
    }
    #[test]
    fn authored_dialog_and_sheet_width_targets_the_visible_panel() {
        for kind in ["dialog", "sheet"] {
            let mut app = Headless::start(EngineConfig {
                context: EngineContext::default().with(SurfaceKind(kind)),
                ..EngineConfig::new(Root::of::<AuthoredSurface>())
            })
            .unwrap();
            app.wait_for("text:Surface content").unwrap();
            let nodes = app.screen().layout_nodes();
            let content = nodes
                .iter()
                .find(|n| n.test_id.as_deref() == Some("lui-2"))
                .unwrap();
            let panel = nodes.iter().find(|n| n.id == content.parent).unwrap();
            assert!(
                (panel.bounds.size.width.0 - 320.0).abs() < 0.1,
                "{kind}: {:?}",
                panel.bounds
            );
        }
    }

    #[derive(Clone)]
    struct PickerFixture {
        kind: &'static str,
        refuse_first: bool,
        seen: Arc<Mutex<Vec<Event>>>,
    }

    fn menu_ops() -> Value {
        json!([
            {"op":"create-node","id":20,"kind":"dropdown-menu"},
            {"op":"create-node","id":21,"kind":"menu-item"},
            {"op":"set-prop","id":21,"property":"text","value":"First"},
            {"op":"set-prop","id":21,"property":"press-enabled","value":true},
            {"op":"create-node","id":22,"kind":"menu-item"},
            {"op":"set-prop","id":22,"property":"text","value":"Disabled"},
            {"op":"set-prop","id":22,"property":"enabled","value":false},
            {"op":"create-node","id":23,"kind":"menu-item"},
            {"op":"set-prop","id":23,"property":"text","value":"Last"},
            {"op":"set-prop","id":23,"property":"press-enabled","value":true},
        {"op":"create-node","id":30,"kind":"menu-trigger"},
        {"op":"set-prop","id":30,"property":"text","value":"More"},
        {"op":"create-node","id":31,"kind":"dropdown-menu"},
        {"op":"create-node","id":32,"kind":"menu-item"},
        {"op":"set-prop","id":32,"property":"text","value":"Nested"},
        {"op":"set-prop","id":32,"property":"press-enabled","value":true},
        {"op":"insert-child","parent":31,"child":32,"index":0},
        {"op":"insert-child","parent":30,"child":31,"index":0},
            {"op":"insert-child","parent":20,"child":21,"index":0},
            {"op":"insert-child","parent":20,"child":22,"index":1},
        {"op":"insert-child","parent":20,"child":23,"index":2},
        {"op":"insert-child","parent":20,"child":30,"index":3}
        ])
    }

    #[component]
    fn PickerScenario() -> impl IntoElement {
        let fixture = engine_context::<PickerFixture>().unwrap();
        let kind = fixture.kind;
        let refusal = fixture.refuse_first;
        let seen = fixture.seen.clone();
        let attempts = Rc::new(Cell::new(0));
        let renderer = Renderer::new(move |event, renderer| {
            seen.lock().unwrap().push(event.clone());
            let generation = renderer.0.borrow().store.generation + 1;
            match event {
                Event::Press(10) if kind != "menu-trigger" => {
                    attempts.set(attempts.get() + 1);
                    if refusal && attempts.get() == 1 {
                        return;
                    }
                    if renderer.current_incarnation(20).is_none() {
                        let mut ops = menu_ops().as_array().unwrap().clone();
                        ops.push(json!({"op":"insert-child","parent":1,"child":20,"index":1}));
                        renderer
                            .apply(patch(generation, Value::Array(ops)))
                            .unwrap();
                    }
                }
                Event::Text(10, text) => renderer
                    .apply(patch(
                        generation,
                        json!([
                            {"op":"set-prop","id":10,"property":"text","value":text}
                        ]),
                    ))
                    .unwrap(),
                Event::Dismiss(20) | Event::Press(21 | 23 | 32)
                    if renderer.current_incarnation(20).is_some() =>
                {
                    renderer
                        .apply(patch(generation, json!([{"op":"detach-subtree","id":20}])))
                        .unwrap();
                }
                _ => {}
            }
        });
        let mut ops=json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":10,"kind":kind},
            {"op":"set-prop","id":10,"property":"text","value":if kind=="combobox" {""} else {"Choose"}},
            {"op":"insert-child","parent":1,"child":10,"index":0}
        ]).as_array().unwrap().clone();
        if kind == "menu-trigger" {
            ops.extend(menu_ops().as_array().unwrap().iter().cloned());
            ops.push(json!({"op":"insert-child","parent":10,"child":20,"index":0}));
        } else {
            ops.push(json!({"op":"set-prop","id":10,"property":"press-enabled","value":true}));
            if kind == "combobox" {
                ops.push(json!({"op":"set-prop","id":10,"property":"change-enabled","value":true}));
                ops.push(json!({"op":"set-prop","id":10,"property":"submit-enabled","value":true}));
                ops.push(json!({"op":"set-prop","id":10,"property":"placeholder","value":"Query"}));
            }
        }
        renderer.apply(patch(1, Value::Array(ops))).unwrap();
        renderer.set_root(1).unwrap();
        renderer.element()
    }
    fn picker(kind: &'static str, refuse_first: bool) -> (Headless, Arc<Mutex<Vec<Event>>>) {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(PickerFixture {
                kind,
                refuse_first,
                seen: seen.clone(),
            }),
            ..EngineConfig::new(Root::of::<PickerScenario>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        (app, seen)
    }
    #[test]
    fn native_menu_keyboard_skips_disabled_items_and_dispatches_the_existing_press() {
        let (mut app, seen) = picker("menu-trigger", false);
        assert_eq!(app.screen().count("role:menuitem[First]").unwrap(), 0);
        app.press_key("tab").unwrap();
        app.press_key("enter").unwrap();
        app.wait_for("role:menuitem[First]").unwrap();
        app.press_key("down").unwrap();
        app.press_key("enter").unwrap();
        app.wait_until(
            "menu selection closes",
            std::time::Duration::from_secs(1),
            |s| s.count("role:menuitem[Last]") == Ok(0),
        )
        .unwrap();
        assert_eq!(*seen.lock().unwrap(), [Event::Press(23)]);
    }
    #[test]
    fn model_owned_select_can_refuse_open_then_dismiss_without_replacing_its_trigger() {
        let (mut app, seen) = picker("select", true);
        let identity = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("lui-10"))
            .unwrap()
            .id;
        app.press("Choose").unwrap();
        assert_eq!(app.screen().count("role:menuitem[First]").unwrap(), 0);
        app.press("Choose").unwrap();
        app.wait_for("role:menuitem[First]").unwrap();
        app.press_key("escape").unwrap();
        app.wait_until(
            "controlled menu dismissed",
            std::time::Duration::from_secs(1),
            |s| s.count("role:menuitem[First]") == Ok(0),
        )
        .unwrap();
        assert_eq!(
            *seen.lock().unwrap(),
            [Event::Press(10), Event::Press(10), Event::Dismiss(20)]
        );
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|n| n.test_id.as_deref() == Some("lui-10"))
                .unwrap()
                .id,
            identity
        );
    }
    #[test]
    fn combobox_keeps_its_controlled_query_and_input_identity_through_popup_opening() {
        let (mut app, seen) = picker("combobox", false);
        let identity = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("lui-10"))
            .unwrap()
            .id;
        app.press("id:lui-10").unwrap();
        app.wait_for("role:menuitem[First]").unwrap();
        app.type_text("id:lui-10", "typed").unwrap();
        assert_eq!(app.screen().input_text("id:lui-10").unwrap(), Some("typed"));
        app.press_key("enter").unwrap();
        assert!(
            seen.lock()
                .unwrap()
                .iter()
                .any(|event| matches!(event,Event::Text(10,text) if text=="typed"))
        );
        assert!(seen.lock().unwrap().contains(&Event::Submit(10)));
        assert!(seen.lock().unwrap().contains(&Event::Press(10)));
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|n| n.test_id.as_deref() == Some("lui-10"))
                .unwrap()
                .id,
            identity
        );
    }
    #[test]
    fn native_submenu_owns_right_arrow_focus_and_nested_selection() {
        let (mut app, seen) = picker("menu-trigger", false);
        app.press_key("tab").unwrap();
        app.press_key("enter").unwrap();
        app.wait_for("role:menuitem[First]").unwrap();
        app.press_key("down").unwrap();
        app.press_key("down").unwrap();
        app.press_key("right").unwrap();
        app.wait_for("role:menuitem[Nested]").unwrap();
        app.press_key("enter").unwrap();
        app.wait_until(
            "nested selection closes",
            std::time::Duration::from_secs(1),
            |s| s.count("role:menuitem[Nested]") == Ok(0),
        )
        .unwrap();
        assert_eq!(*seen.lock().unwrap(), [Event::Press(32)]);
    }
    #[component]
    fn OverlayScenario() -> impl IntoElement {
        let renderer = Renderer::new(move |event, renderer| {
            let generation = renderer.0.borrow().store.generation + 1;
            match event {
                Event::Press(10) if renderer.current_incarnation(20).is_none() => renderer.apply(patch(generation,json!([
                    {"op":"create-node","id":20,"kind":"popover"},
                    {"op":"set-prop","id":20,"property":"anchor","value":"below"},
                    {"op":"set-prop","id":20,"property":"anchor-target","value":"anchor-button"},
                    {"op":"set-prop","id":20,"property":"anchor-offset","value":5.0},
                    {"op":"create-node","id":21,"kind":"text-field"},
                    {"op":"set-prop","id":21,"property":"text","value":"draft"},
                    {"op":"set-prop","id":21,"property":"autofocus","value":true},
                    {"op":"set-prop","id":21,"property":"change-enabled","value":true},
                    {"op":"create-node","id":22,"kind":"button"},
                    {"op":"set-prop","id":22,"property":"text","value":"Reposition"},
                    {"op":"set-prop","id":22,"property":"press-enabled","value":true},
                    {"op":"insert-child","parent":20,"child":21,"index":0},
                    {"op":"insert-child","parent":20,"child":22,"index":1},
                    {"op":"insert-child","parent":1,"child":20,"index":2}
                ]))).unwrap(),
                Event::Text(21,text)=>renderer.apply(patch(generation,json!([
                    {"op":"set-prop","id":21,"property":"text","value":text}
                ]))).unwrap(),
                Event::Dismiss(20)=>renderer.apply(patch(generation,json!([
                    {"op":"detach-subtree","id":20}
                ]))).unwrap(),
                Event::Press(22) if renderer.current_incarnation(20).is_some()=> {
                    assert!(renderer.apply(patch(generation,json!([
                        {"op":"set-prop","id":20,"property":"anchor-target","value":"different-anchor"}
                    ]))).unwrap_err().contains("changing popup anchor source"));
                    assert_eq!(renderer.0.borrow().store.generation,generation-1);
                    renderer.apply(patch(generation,json!([
                        {"op":"set-prop","id":20,"property":"anchor-offset","value":10.0}
                    ]))).unwrap();
                }
                _=>{}
            }
        });
        renderer.apply(patch(1,json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":10,"kind":"button"},
            {"op":"set-prop","id":10,"property":"text","value":"Anchor"},
            {"op":"set-prop","id":10,"property":"accessibility-identifier","value":"anchor-button"},
            {"op":"set-prop","id":10,"property":"press-enabled","value":true},
            {"op":"create-node","id":11,"kind":"button"},
            {"op":"set-prop","id":11,"property":"text","value":"Move popup"},
            {"op":"set-prop","id":11,"property":"press-enabled","value":true},
            {"op":"insert-child","parent":1,"child":10,"index":0},
            {"op":"insert-child","parent":1,"child":11,"index":1}
        ]))).unwrap();
        renderer.set_root(1).unwrap();
        renderer.element()
    }
    #[test]
    fn externally_anchored_popover_preserves_editor_identity_and_escape_restores_focus() {
        let mut config = EngineConfig::new(Root::of::<OverlayScenario>());
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.wait_for("Anchor").unwrap();
        app.press("Anchor").unwrap();
        app.wait_for("id:lui-21").unwrap();
        let before = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("lui-21"))
            .unwrap()
            .id;
        app.type_text("id:lui-21", " kept").unwrap();
        let text = app
            .screen()
            .input_text("id:lui-21")
            .unwrap()
            .map(str::to_owned)
            .unwrap();
        app.press("Reposition").unwrap();
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|n| n.test_id.as_deref() == Some("lui-21"))
                .unwrap()
                .id,
            before
        );
        assert_eq!(
            app.screen().input_text("id:lui-21").unwrap(),
            Some(text.as_str())
        );
        app.type_text("id:lui-21", "").unwrap();
        app.press_key("escape").unwrap();
        app.wait_until("popover removed", std::time::Duration::from_secs(1), |s| {
            s.count("id:lui-21") == Ok(0)
        })
        .unwrap();
        app.press_key("space").unwrap();
        app.wait_for("id:lui-21").unwrap();
        let after = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("lui-21"))
            .unwrap()
            .id;
        assert_ne!(before, after);
        assert!(text.contains("kept"));
    }
    #[component]
    fn TooltipScenario() -> impl IntoElement {
        let renderer = Renderer::new(|_, _| {});
        renderer
            .apply(patch(
                1,
                json!([
                    {"op":"create-node","id":1,"kind":"row"},
                    {"op":"create-node","id":10,"kind":"button"},
                    {"op":"set-prop","id":10,"property":"text","value":"Hint anchor"},
                    {"op":"create-node","id":20,"kind":"tooltip"},
                    {"op":"set-prop","id":20,"property":"text","value":"Native hint"},
                    {"op":"set-prop","id":20,"property":"anchor","value":"above"},
                    {"op":"set-prop","id":20,"property":"tooltip-delay","value":250},
                    {"op":"insert-child","parent":1,"child":10,"index":0},
                    {"op":"insert-child","parent":1,"child":20,"index":1}
                ]),
            ))
            .unwrap();
        renderer.set_root(1).unwrap();
        renderer.element()
    }
    #[test]
    fn anchored_tooltip_uses_native_keyboard_hint_visibility_and_escape() {
        let mut config = EngineConfig::new(Root::of::<TooltipScenario>());
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        assert_eq!(app.screen().count("text:Native hint").unwrap(), 0);
        app.press_key("tab").unwrap();
        app.wait_for("text:Native hint").unwrap();
        app.press_key("escape").unwrap();
        app.wait_until(
            "native hint hidden",
            std::time::Duration::from_secs(1),
            |s| s.count("text:Native hint") == Ok(0),
        )
        .unwrap();
    }
}

#[cfg(test)]
mod image_tests;

#[cfg(test)]
mod heading_tests;

#[cfg(test)]
mod input_tests;

#[cfg(test)]
mod file_picker_tests;

#[cfg(test)]
mod media_tests;
