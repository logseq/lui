//! Thin metadata projection onto the public native NSH Tree controller.
use super::{ChildIdentity, Presentation};
use crate::{render::Event, store::Node, ui};
use nsh_core::{
    element::{Renderer, StyleRefinement},
    prelude::*,
};
use std::{rc::Rc, sync::Arc};

type SourceLookup = Rc<dyn Fn(ChildIdentity) -> Option<Source>>;
#[derive(Clone, Copy)]
pub(crate) struct Source {
    pub node: Signal<Arc<Node>>,
    pub children: Signal<Vec<ChildIdentity>>,
}
pub(crate) struct Callbacks {
    pub lookup: SourceLookup,
    pub emit: Rc<dyn Fn(ChildIdentity, Event)>,
}

pub(crate) fn validate_root(node: &Node) -> Result<(), String> {
    if node.boolean("pointer-enabled", false) {
        return Err("NSH native Tree does not expose root pointer callbacks".into());
    }
    Ok(())
}

pub(crate) fn metadata_kind(kind: &str) -> bool {
    matches!(
        kind,
        "row" | "column" | "panel" | "card" | "box" | "list-item"
    )
}

/// These nodes are data entries, not independent view bodies. Reject actual
/// authored behavior that the native Tree API cannot project, never all of a
/// kind's possible properties merely because that kind also serves as a view.
pub(crate) fn validate_source<'a>(
    root: &'a Node,
    lookup: &impl Fn(u64) -> Result<&'a Node, String>,
) -> Result<(), String> {
    let mut pending = root.children.as_ref().clone();
    let mut count = 0_u64;
    while let Some(id) = pending.pop() {
        let node = lookup(id)?;
        if !metadata_kind(&node.kind) {
            return Err(format!(
                "NSH Tree children are item metadata; {} body views are not supported",
                node.kind
            ));
        }
        if !node.string("role").is_empty() && node.string("role") != "treeitem" {
            return Err("NSH Tree item metadata uses the native treeitem role".into());
        }
        for (property, value) in &node.props {
            if matches!(
                property.as_str(),
                "key"
                    | "text"
                    | "accessibility-label"
                    | "accessibility-identifier"
                    | "role"
                    | "selected"
                    | "expanded"
                    | "enabled"
                    | "change-enabled"
                    | "toggle-enabled"
                    | "press-enabled"
                    | "icon"
            ) {
                continue;
            }
            // Explicit false capabilities retain their ordinary absence semantics.
            if property.ends_with("-enabled") && value.as_bool() == Some(false) {
                continue;
            }
            return Err(format!(
                "NSH Tree item metadata does not implement authored {property}; use native Tree item data and callbacks"
            ));
        }
        count += 1;
        if count > u64::from(u32::MAX) {
            return Err("NSH Tree exceeds native u32 item capacity".into());
        }
        pending.extend(node.children.iter().copied());
    }
    Ok(())
}

fn key(identity: ChildIdentity) -> SharedString {
    format!("{}:{}", identity.0, identity.1).into()
}
fn identity(key: &str) -> Option<ChildIdentity> {
    let (id, incarnation) = key.split_once(':')?;
    Some((id.parse().ok()?, incarnation.parse().ok()?))
}

#[derive(Clone, PartialEq)]
struct Projection {
    items: Vec<nsh_base::TreeItem>,
    expanded: Option<Vec<SharedString>>,
    selected: nsh_base::SelectValue,
}
fn project(children: &[ChildIdentity], lookup: &SourceLookup) -> Projection {
    fn items(
        children: &[ChildIdentity],
        lookup: &SourceLookup,
        selected: &mut Option<SharedString>,
        has_selected: &mut bool,
        expanded: &mut Vec<SharedString>,
        has_expanded: &mut bool,
    ) -> Vec<nsh_base::TreeItem> {
        children
            .iter()
            .filter_map(|&item| {
                let source = lookup(item)?;
                let node = source.node.get();
                let id = key(item);
                *has_selected |= node.props.contains_key("selected");
                if selected.is_none() && node.boolean("selected", false) {
                    *selected = Some(id.clone());
                }
                *has_expanded |= node.props.contains_key("expanded");
                if node.boolean("expanded", false) {
                    expanded.push(id.clone());
                }
                let label = node.string("accessibility-label");
                let label = if label.is_empty() {
                    node.string("text")
                } else {
                    label
                };
                Some(
                    nsh_base::TreeItem::new(id, label.to_owned())
                        .disabled(!node.boolean("enabled", true))
                        .children(source.children.with(|children| {
                            items(
                                children,
                                lookup,
                                selected,
                                has_selected,
                                expanded,
                                has_expanded,
                            )
                        })),
                )
            })
            .collect()
    }
    let (mut selected, mut expanded) = (None, Vec::new());
    let (mut has_selected, mut has_expanded) = (false, false);
    let items = items(
        children,
        lookup,
        &mut selected,
        &mut has_selected,
        &mut expanded,
        &mut has_expanded,
    );
    Projection {
        items,
        expanded: has_expanded.then_some(expanded),
        selected: if has_selected {
            nsh_base::SelectValue::Controlled(selected)
        } else {
            nsh_base::SelectValue::Uncontrolled
        },
    }
}

pub(crate) fn element(
    node: Signal<Arc<Node>>,
    children: Signal<Vec<ChildIdentity>>,
    callbacks: Callbacks,
    presentation: Presentation,
) -> AnyElement {
    let reading = callbacks.lookup.clone();
    let projection = computed(move || children.with(|children| project(children, &reading)));
    // Separate equality-checked projections: source selection/expansion changes
    // do not rebuild native Flat when the public Vec<TreeItem> is unchanged.
    let items = computed(move || projection.with(|value| value.items.clone()));
    let expanded = computed(move || projection.with(|value| value.expanded.clone()));
    let selected = computed(move || projection.with(|value| value.selected.clone()));
    let theme = presentation.theme;
    let drawing = callbacks.lookup.clone();
    let renderer = Renderer::new(move |entry: &nsh_base::TreeEntry| {
        let Some(identity) = identity(&entry.id) else {
            return view().into_element();
        };
        let Some(source) = drawing(identity) else {
            return view().into_element();
        };
        let label = entry.label.clone();
        let folder = entry.folder;
        let depth = entry.depth;
        let identifier = computed(move || {
            let node = source.node.get();
            let authored = node.string("accessibility-identifier");
            if authored.is_empty() {
                format!("lui-{}", identity.0)
            } else {
                authored.to_owned()
            }
        });
        dynamic(move || {
            view()
                .test_id(&identifier.get())
                .flex_row()
                .items_center()
                .gap_2()
                .pl(px(depth as f32 * 14.0))
                .child(if folder {
                    ui::icon("chevron-right", px(14.0))
                        .app_class(Some("group-aria-expanded:rotate-90".into()))
                        .into_element()
                } else {
                    view().w(px(14.0)).into_element()
                })
                .child(when(
                    move || !source.node.get().string("icon").is_empty(),
                    move || {
                        ui::icon(
                            move || SharedString::from(source.node.get().string("icon").to_owned()),
                            px(16.0),
                        )
                    },
                ))
                .child(text(label.clone()))
        })
        .into_element()
    });
    let lookup = callbacks.lookup;
    let emit = callbacks.emit;
    presentation.component(
        nsh_base::Tree::element(nsh_base::TreeProps {
            items: Prop::bind(move || items.get()),
            expanded: Prop::bind(move || expanded.get()),
            selected: Prop::bind(move || selected.get()),
            accessibility_label: Prop::bind(move || Some(super::label(node))),
            list_style: Prop::bind(move || {
                ui::part(StyleRefinement::default().gap(px(node.get().number("gap", 0.0) as f32)))
            }),
            item_class: Some("group".into()).into(),
            item_style: Prop::bind(move || {
                let mut row = view()
                    .px_2()
                    .py_1()
                    .rounded(move || ui::radius(theme))
                    .text_color(move || ui::color(theme, "foreground"))
                    .hover(|style| style.bg(move || ui::color(theme, "accent")))
                    .selected(|style| style.bg(move || ui::color(theme, "accent")))
                    .active(|style| style.opacity(0.7))
                    .disabled_style(|style| style.opacity(0.5))
                    .focus_visible(|style| {
                        style
                            .outline(px(2.0))
                            .outline_color(move || ui::color(theme, "ring"))
                    })
                    .transition_colors()
                    .duration(if theme.get().reduced_motion {
                        0.0
                    } else {
                        120.0
                    });
                row.style().clone().into()
            }),
            render_item: Some(renderer).into(),
            ..Default::default()
        })
        .on_event(move |event: &nsh_base::TreeEvent| {
            let (key, flag, build): (_, _, fn(u64) -> Event) = match event {
                nsh_base::TreeEvent::SelectedChange(key) => (key, "change-enabled", Event::Change),
                nsh_base::TreeEvent::Expand(key) => {
                    (key, "toggle-enabled", |id| Event::Toggle(id, true))
                }
                nsh_base::TreeEvent::Collapse(key) => {
                    (key, "toggle-enabled", |id| Event::Toggle(id, false))
                }
                nsh_base::TreeEvent::Action(key) => (key, "press-enabled", Event::Press),
                nsh_base::TreeEvent::ExpandedChange(_) => return,
            };
            let Some(identity) = identity(key) else {
                return;
            };
            let Some(source) = lookup(identity) else {
                return;
            };
            let node = source.node.get_untracked();
            let event = build(node.id);
            if node.boolean("enabled", true) && node.boolean(flag, false) {
                emit(identity, event);
            }
        }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{render::Renderer as LuiRenderer, wire::Batch};
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::{Value, json};
    use std::{cell::Cell, sync::Mutex};

    struct Fixture {
        controlled: bool,
        count: usize,
        events: Arc<Mutex<Vec<Event>>>,
        rejected: Arc<Mutex<bool>>,
    }
    fn batch(generation: u64, ops: Value) -> Batch {
        Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
    }
    fn apply(renderer: &LuiRenderer, generation: &Cell<u64>, ops: Value) {
        let next = generation.get() + 1;
        renderer.apply(batch(next, ops)).unwrap();
        generation.set(next);
    }
    fn item(
        ops: &mut Vec<Value>,
        id: u64,
        parent: u64,
        index: usize,
        text: &str,
        controlled: bool,
        folder: bool,
    ) {
        ops.extend([
            json!({"op":"create-node","id":id,"kind":"list-item"}),
            json!({"op":"set-prop","id":id,"property":"role","value":"treeitem"}),
            json!({"op":"set-prop","id":id,"property":"text","value":text}),
            json!({"op":"set-prop","id":id,"property":"change-enabled","value":true}),
            json!({"op":"set-prop","id":id,"property":"press-enabled","value":true}),
            json!({"op":"insert-child","parent":parent,"child":id,"index":index}),
        ]);
        if folder {
            ops.push(json!({"op":"set-prop","id":id,"property":"toggle-enabled","value":true}));
        }
        if controlled {
            ops.push(json!({"op":"set-prop","id":id,"property":"selected","value":false}));
            if folder {
                ops.push(json!({"op":"set-prop","id":id,"property":"expanded","value":false}));
            }
        }
    }
    #[component]
    fn NativeTreeProbe() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        let generation = Rc::new(Cell::new(0));
        let publishing = generation.clone();
        let accepted = Rc::new(Cell::new(false));
        let following = accepted.clone();
        let events = fixture.events.clone();
        let renderer = LuiRenderer::new(move |event, renderer| {
            events.lock().unwrap().push(event.clone());
            if following.get() {
                match event {
                    Event::Toggle(id, expanded) => apply(&renderer, &publishing, json!([{"op":"set-prop","id":id,"property":"expanded","value":expanded}])),
                    Event::Change(id) => apply(&renderer, &publishing, json!([11,12,13,20].map(|candidate| json!({"op":"set-prop","id":candidate,"property":"selected","value":candidate==id})))),
                    _ => {}
                }
            }
        });
        let mut ops = vec![
            json!({"op":"create-node","id":1,"kind":"column"}),
            json!({"op":"create-node","id":2,"kind":"text-field"}),
            json!({"op":"set-prop","id":2,"property":"text","value":"outside draft"}),
            json!({"op":"set-prop","id":2,"property":"accessibility-label","value":"Outside editor"}),
            json!({"op":"insert-child","parent":1,"child":2,"index":0}),
            json!({"op":"create-node","id":10,"kind":"tree"}),
            json!({"op":"set-prop","id":10,"property":"accessibility-label","value":"Files"}),
            json!({"op":"set-prop","id":10,"property":"width","value":400}),
            json!({"op":"set-prop","id":10,"property":"height","value":240}),
            json!({"op":"insert-child","parent":1,"child":10,"index":1}),
        ];
        if fixture.count > 0 {
            for index in 0..fixture.count {
                item(
                    &mut ops,
                    100 + index as u64,
                    10,
                    index,
                    &format!("Entry {index}"),
                    false,
                    false,
                );
            }
        } else {
            item(&mut ops, 11, 10, 0, "Folder", fixture.controlled, true);
            item(&mut ops, 12, 11, 0, "Leaf", fixture.controlled, false);
            item(&mut ops, 13, 11, 1, "Disabled", fixture.controlled, false);
            ops.push(json!({"op":"set-prop","id":13,"property":"enabled","value":false}));
            item(&mut ops, 20, 10, 1, "Last", fixture.controlled, false);
        }
        apply(&renderer, &generation, json!(ops));
        renderer.set_root(1).unwrap();
        on_key_with(
            "f5",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| accepted.set(true),
        );
        for (key, ops) in [
            (
                "f6",
                json!([{"op":"set-prop","id":12,"property":"text","value":"Renamed leaf"}]),
            ),
            (
                "f7",
                json!([{"op":"move-child","parent":10,"child":20,"index":0}]),
            ),
            (
                "f8",
                json!([{"op":"set-prop","id":12,"property":"icon","value":"check"}]),
            ),
        ] {
            let renderer = renderer.clone();
            let generation = generation.clone();
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| apply(&renderer, &generation, ops.clone()),
            );
        }
        let legacy = renderer.clone();
        let legacy_generation = generation.clone();
        let legacy_rejected = fixture.rejected.clone();
        on_key_with(
            "f3",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let next = legacy_generation.get() + 1;
                let error = legacy
                    .apply(batch(
                        next,
                        json!([
                            {"op":"set-prop","id":2,"property":"text","value":"must not publish"},
                            {"op":"set-prop","id":11,"property":"pointer-enabled","value":true}
                        ]),
                    ))
                    .unwrap_err();
                assert!(error.contains("authored pointer-enabled"), "{error}");
                apply(
                    &legacy,
                    &legacy_generation,
                    json!([{"op":"set-prop","id":20,"property":"text","value":"Last renamed"}]),
                );
                *legacy_rejected.lock().unwrap() = true;
            },
        );
        let rejecting = renderer.clone();
        let final_generation = generation;
        let rejected = fixture.rejected.clone();
        on_key_with(
            "f2",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                let next = final_generation.get() + 1;
                let error=rejecting.apply(batch(next,json!([
                {"op":"set-prop","id":2,"property":"text","value":"must not publish"},
                {"op":"create-node","id":99,"kind":"text-field"},
                {"op":"set-prop","id":99,"property":"text","value":"unsupported editor"},
                {"op":"insert-child","parent":11,"child":99,"index":0}
            ]))).unwrap_err();
                assert!(error.contains("item metadata"), "{error}");
                apply(
                    &rejecting,
                    &final_generation,
                    json!([{"op":"set-prop","id":20,"property":"text","value":"Last renamed"}]),
                );
                *rejected.lock().unwrap() = true;
            },
        );
        renderer.element()
    }
    type Started = (Headless, Arc<Mutex<Vec<Event>>>, Arc<Mutex<bool>>);
    fn start(controlled: bool, count: usize) -> Started {
        let events = Arc::new(Mutex::new(Vec::new()));
        let rejected = Arc::new(Mutex::new(false));
        let mut config = EngineConfig {
            context: EngineContext::default().with(Fixture {
                controlled,
                count,
                events: events.clone(),
                rejected: rejected.clone(),
            }),
            ..EngineConfig::new(Root::of::<NativeTreeProbe>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        (app, events, rejected)
    }
    #[test]
    fn uncontrolled_native_tree_owns_expansion_and_selected_leaf_does_not_reactivate() {
        let (mut app, events, _) = start(false, 0);
        assert_eq!(app.screen().count("role:tree[Files]").unwrap(), 1);
        assert_eq!(app.screen().count("role:treeitem[Leaf]").unwrap(), 0);
        app.press("role:treeitem[Folder]").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [Event::Change(11), Event::Toggle(11, true)]
        );
        assert_eq!(app.screen().count("role:treeitem[Leaf]").unwrap(), 1);
        app.press("role:treeitem[Leaf]").unwrap();
        events.lock().unwrap().clear();
        app.press("role:treeitem[Leaf]").unwrap();
        assert!(
            events.lock().unwrap().is_empty(),
            "native selected-change is not repeated Press"
        );
        app.press_key("enter").unwrap();
        app.press_key("space").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [Event::Press(12)],
            "native leaf Action is Return, not Space"
        );
    }
    #[test]
    fn controlled_values_refuse_then_accept_native_requests_without_custom_state() {
        let (mut app, events, _) = start(true, 0);
        app.press("role:treeitem[Folder]").unwrap();
        assert_eq!(app.screen().count("role:treeitem[Leaf]").unwrap(), 0);
        assert!(
            !app.screen()
                .accessibility_state("role:treeitem[Folder]")
                .unwrap()
                .selected
        );
        app.press_key("f5").unwrap();
        app.press("role:treeitem[Folder]").unwrap();
        assert!(
            app.screen()
                .accessibility_state("role:treeitem[Folder]")
                .unwrap()
                .selected
        );
        assert_eq!(app.screen().count("role:treeitem[Leaf]").unwrap(), 1);
        assert_eq!(
            *events.lock().unwrap(),
            [
                Event::Change(11),
                Event::Toggle(11, true),
                Event::Change(11),
                Event::Toggle(11, true)
            ]
        );
    }
    #[test]
    fn native_cursor_keys_skip_disabled_rows_and_keep_native_default_action() {
        let (mut app, events, _) = start(false, 0);
        app.press("role:treeitem[Folder]").unwrap();
        events.lock().unwrap().clear();
        app.press_key("right").unwrap();
        app.press_key("down").unwrap();
        app.press_key("enter").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [Event::Change(12), Event::Change(20), Event::Press(20)]
        );
        app.press_key("left").unwrap();
        assert!(
            !events
                .lock()
                .unwrap()
                .iter()
                .any(|event| matches!(event, Event::Change(13) | Event::Press(13)))
        );
    }
    #[test]
    fn native_keys_survive_metadata_updates_and_reorder_while_outside_editor_is_retained() {
        let (mut app, _, _) = start(false, 0);
        app.press("role:treeitem[Folder]").unwrap();
        let row = app
            .screen()
            .press_target("role:treeitem[Folder]")
            .unwrap()
            .unwrap();
        let editor = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("lui-2"))
            .unwrap()
            .id;
        app.type_text("id:lui-2", " retained").unwrap();
        let text = app
            .screen()
            .input_text("id:lui-2")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("f6").unwrap();
        app.press_key("f8").unwrap();
        app.press_key("f7").unwrap();
        assert_eq!(
            app.screen().count("role:treeitem[Renamed leaf]").unwrap(),
            1
        );
        assert_eq!(
            app.screen().press_target("role:treeitem[Folder]").unwrap(),
            Some(row)
        );
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some("lui-2"))
                .unwrap()
                .id,
            editor
        );
        app.press_key("x").unwrap();
        assert_eq!(
            app.screen().input_text("id:lui-2").unwrap(),
            Some(format!("{text}x").as_str())
        );
    }
    #[test]
    fn arbitrary_body_views_fail_atomically_and_retry_keeps_generation() {
        let (mut app, _, rejected) = start(false, 0);
        let before = app
            .screen()
            .input_text("id:lui-2")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("f2").unwrap();
        assert!(*rejected.lock().unwrap());
        assert_eq!(
            app.screen().input_text("id:lui-2").unwrap(),
            Some(before.as_str())
        );
        assert_eq!(app.screen().count("text:unsupported editor").unwrap(), 0);
        assert_eq!(
            app.screen().count("role:treeitem[Last renamed]").unwrap(),
            1
        );
    }
    #[test]
    fn native_tree_virtualizes_a_thousand_metadata_items() {
        let (app, _, _) = start(false, 1000);
        let mounted = app.screen().count("role:treeitem").unwrap();
        assert!(
            mounted > 0 && mounted < 100,
            "native Tree made {mounted} rows for1000 metadata items"
        );
    }
    #[test]
    fn legacy_pointer_subscriptions_are_refused_before_other_edits_publish() {
        let (mut app, _, rejected) = start(false, 0);
        let before = app
            .screen()
            .input_text("id:lui-2")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("f3").unwrap();
        assert!(*rejected.lock().unwrap());
        assert_eq!(
            app.screen().input_text("id:lui-2").unwrap(),
            Some(before.as_str())
        );
        assert_eq!(
            app.screen().count("role:treeitem[Last renamed]").unwrap(),
            1
        );
    }
}
