//! Retained collection parts composed from public NSH semantics.
use super::{ChildRenderer, Emit, Presentation, emit_flag, enabled, label};
use crate::{render::Event, store::Node, ui};
use nsh_core::{AccessibilityState, prelude::*};
use std::sync::Arc;

pub(super) fn supported(kind: &str) -> bool {
    matches!(
        kind,
        "list-item"
            | "accordion"
            | "table"
            | "table-row"
            | "table-cell"
            | "list-section"
            | "list-section-header"
            | "list-section-footer"
            | "bottom-tabs"
            | "bottom-tab"
    )
}

/// Typed native row parts expose activation and disclosure, but not richer
/// press payloads, inline text editing or Return-only submission. Refuse those
/// callbacks explicitly until native projections or an editor mode exist.
pub(super) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "list-item" {
        if node.boolean("change-enabled", false) {
            return Err(
                "NSH list-item change-enabled inline editor mode is not implemented yet".into(),
            );
        }
        for flag in [
            "long-press-enabled",
            "double-press-enabled",
            "submit-enabled",
        ] {
            if node.boolean(flag, false) {
                return Err(format!(
                    "NSH list-item {flag} requires native typed event projection, which is not implemented yet"
                ));
            }
        }
    }
    Ok(())
}

pub(super) fn validate_transition(previous: &Node, next: &Node) -> Result<(), String> {
    if previous.incarnation == next.incarnation
        && next.kind == "list-item"
        && previous.props.contains_key("expanded") != next.props.contains_key("expanded")
    {
        return Err(
            "NSH list-item flat/disclosure mode changes require a new node incarnation".into(),
        );
    }
    Ok(())
}

fn partition_children(source: super::ChildRenderer, nested: bool) -> AnyElement {
    let lookup = source.lookup;
    let render = source.render;
    each(
        move || {
            source
                .identities
                .get()
                .into_iter()
                .filter(|identity| {
                    // Kind is immutable within an incarnation. Property edits must not
                    // rebuild sibling membership or move their retained bodies.
                    lookup(*identity)
                        .is_some_and(|node| (node.get_untracked().kind == "list-item") == nested)
                })
                .collect::<Vec<_>>()
        },
        |identity| *identity,
        move |identity, _| render(identity.get_untracked()),
    )
    .into_element()
}

/// Apple and Web both prefer the first source-selected tab, falling back to the
/// first child even if it is disabled. This memo derives presentation only.
fn bottom_tabs(
    node: Signal<Arc<Node>>,
    source: ChildRenderer,
    presentation: Presentation,
) -> AnyElement {
    let selecting = source.clone();
    let active = computed(move || {
        let identities = selecting.identities.get();
        identities
            .iter()
            .copied()
            .find(|identity| {
                (selecting.lookup)(*identity)
                    .is_some_and(|node| node.get().boolean("selected", false))
            })
            .or_else(|| identities.first().copied())
    });
    let rendering = source.clone();
    let pages = each(
        source.identities,
        |identity| *identity,
        move |identity, _| {
            let identity = identity.get_untracked();
            let visible = move || active.get() == Some(identity);
            crate::events::scope_visibility(visible);
            // Realize a page only on its first selection. After that it remains
            // mounted under the same keyed owner, including its native draft state.
            let visited = signal(visible());
            effect(move || {
                if visible() && !visited.get_untracked() {
                    visited.set(true);
                }
            });
            let render = rendering.render.clone();
            when(visited, move || {
                view()
                    .flex_1()
                    .min_w_0()
                    .min_h_0()
                    .accessibility_elements_hidden(move || !visible())
                    .style_when(move || !visible(), |style| style.hidden())
                    .child(render(identity))
            })
            .into_element()
        },
    );
    let theme = presentation.theme;
    let triggers = each(
        source.identities,
        |identity| *identity,
        move |identity, _| {
            let identity = identity.get_untracked();
            let Some(tab) = (source.lookup)(identity) else {
                return view().into_element();
            };
            let press = source.press.clone();
            ui::controls::tab(
                nsh_base::TabProps {
                    selected: Prop::bind(move || active.get() == Some(identity)),
                    disabled: Prop::bind(move || !enabled(tab)),
                    accessibility_label: Prop::bind(move || {
                        Some(tab.get().string("title").to_owned().into())
                    }),
                    ..Default::default()
                },
                theme,
            )
            .key(format!("trigger-{}-{}", identity.0, identity.1))
            .test_id(format!("lui-tab-trigger-{}-{}", identity.0, identity.1))
            .on_event(move |_: &nsh_base::TabEvent| press(identity))
            .child(when(
                move || !tab.get().string("icon").is_empty(),
                move || {
                    ui::icon(
                        move || SharedString::from(tab.get().string("icon").to_owned()),
                        px(20.0),
                    )
                },
            ))
            .child(text(move || tab.get().string("title").to_owned()))
            .into_element()
        },
    );
    presentation.host(
        view()
            .flex_col()
            .flex_1()
            .min_w_0()
            .min_h_0()
            // Pages are outside TabsContext: ordinary controls inside a page must
            // remain controls, rather than registering as native tab triggers.
            .child(view().flex_1().min_w_0().min_h_0().child(pages))
            .child(
                ui::controls::Tabs::element(ui::controls::TabsProps {
                    theme: Some(theme).into(),
                    label: Prop::bind(move || label(node)),
                    ..Default::default()
                })
                .child(triggers),
            ),
    )
}

fn list_item(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    emit: Emit,
    presentation: Presentation,
) -> AnyElement {
    let initial = node.get_untracked();
    let id = initial.id;
    let theme = presentation.theme;
    let actionable = initial.boolean("press-enabled", false);
    if initial.props.contains_key("expanded") {
        let (content, nested) = match presentation.children.clone() {
            Some(source) => (
                partition_children(source.clone(), false),
                partition_children(source, true),
            ),
            None => (children, view().into_element()),
        };
        return presentation.component(
            nsh_base::Accordion::element(nsh_base::AccordionProps {
                value: Prop::bind(move || {
                    if node.get().boolean("expanded", false) {
                        vec!["children".into()]
                    } else {
                        Vec::new()
                    }
                }),
                disabled: Prop::bind(move || !enabled(node)),
                ..Default::default()
            })
            .on_event(move |event: &nsh_base::AccordionEvent| {
                let nsh_base::AccordionEvent::Change(value) = event;
                emit_flag(
                    node,
                    "toggle-enabled",
                    &emit,
                    Event::Toggle(id, !value.is_empty()),
                );
            })
            .child(
                nsh_base::AccordionItem::element(nsh_base::AccordionItemProps {
                    value: "children".into(),
                    ..Default::default()
                })
                .child(
                    nsh_base::AccordionHeader::element(Default::default()).child(
                        nsh_base::AccordionTrigger::element(nsh_base::AccordionTriggerProps {
                            accessibility_label: Prop::bind(move || Some(label(node))),
                            ..Default::default()
                        })
                        .flex_row()
                        .items_center()
                        .px_3()
                        .py_2()
                        .child(ui::icon(
                            move || {
                                SharedString::from(if node.get().boolean("expanded", false) {
                                    "chevron-down"
                                } else {
                                    "chevron-right"
                                })
                            },
                            px(16.0),
                        ))
                        .child(super::command_content(node, content, theme)),
                    ),
                )
                .child(
                    nsh_base::AccordionPanel::element(nsh_base::AccordionPanelProps {
                        keep_mounted: true.into(),
                        reveal: true.into(),
                        ..Default::default()
                    })
                    .pl_4()
                    .child(nested),
                ),
            ),
        );
    }
    let body = super::command_content(node, children, theme);
    if actionable {
        presentation.component(
            nsh_base::Button::element(nsh_base::ButtonProps {
                selected: Prop::bind(move || node.get().boolean("selected", false)),
                disabled: Prop::bind(move || !enabled(node)),
                accessibility_label: Prop::bind(move || Some(label(node))),
                role: Prop::bind(move || {
                    Some(if node.get().string("role") == "navigation-heading" {
                        AccessibilityRole::Header
                    } else {
                        AccessibilityRole::Button
                    })
                }),
                ..Default::default()
            })
            .w_full()
            .flex_row()
            .items_center()
            .justify_start()
            .px_3()
            .py_2()
            .hover(|s| s.bg(move || ui::color(theme, "accent")))
            .focus_visible(|s| {
                s.outline(px(2.0))
                    .outline_color(move || ui::color(theme, "ring"))
            })
            .disabled_style(|s| s.opacity(0.5))
            .on_event(move |event: &nsh_base::ButtonEvent| {
                if matches!(event, nsh_base::ButtonEvent::Press) {
                    emit_flag(node, "press-enabled", &emit, Event::Press(id));
                }
            })
            .child(body),
        )
    } else {
        presentation.host(
            view()
                .flex_row()
                .items_center()
                .px_3()
                .py_2()
                .role(move || {
                    if node.get().string("role") == "navigation-heading" {
                        AccessibilityRole::Header
                    } else {
                        AccessibilityRole::Group
                    }
                })
                .disabled(move || !enabled(node))
                .accessibility_state(move || AccessibilityState {
                    selected: node.get().boolean("selected", false),
                    ..Default::default()
                })
                .child(body),
        )
    }
}

pub(super) fn element(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    emit: Emit,
    presentation: Presentation,
) -> Option<AnyElement> {
    let initial = node.get_untracked();
    let id = initial.id;
    let theme = presentation.theme;
    Some(match initial.kind.as_str() {
        "list-item" => list_item(node, children, emit, presentation),
        "accordion" => {
            // One canonical disclosure is one native item. The value remains
            // controlled by LUI, including when an application refuses a toggle.
            let heading = nsh_base::AccordionHeader::element(Default::default()).child(
                when(
                    move || node.get().boolean("toggle-enabled", false),
                    move || {
                        nsh_base::AccordionTrigger::element(nsh_base::AccordionTriggerProps {
                            accessibility_label: Prop::bind(move || Some(label(node))),
                            ..Default::default()
                        })
                        .flex_row()
                        .items_center()
                        .gap_2()
                        .py_2()
                        .text_color(move || ui::color(theme, "foreground"))
                        .hover(|s| s.bg(move || ui::color(theme, "accent")))
                        .focus_visible(|s| {
                            s.outline(px(2.0))
                                .outline_color(move || ui::color(theme, "ring"))
                        })
                        .child(ui::icon(
                            move || {
                                SharedString::from(if node.get().boolean("selected", false) {
                                    "chevron-down"
                                } else {
                                    "chevron-right"
                                })
                            },
                            px(16.0),
                        ))
                        .child(text(move || node.get().string("text").to_owned()))
                    },
                )
                .otherwise(move || text(move || node.get().string("text").to_owned())),
            );
            let panel = nsh_base::AccordionPanel::element(nsh_base::AccordionPanelProps {
                keep_mounted: true.into(),
                reveal: true.into(),
                accessibility_label: Prop::bind(move || Some(label(node))),
                ..Default::default()
            })
            .child(children);
            presentation.component(
                nsh_base::Accordion::element(nsh_base::AccordionProps {
                    value: Prop::bind(move || {
                        let current = node.get();
                        if !current.boolean("toggle-enabled", false)
                            || current.boolean("selected", false)
                        {
                            vec!["content".into()]
                        } else {
                            Vec::new()
                        }
                    }),
                    ..Default::default()
                })
                .on_event(move |event: &nsh_base::AccordionEvent| {
                    let nsh_base::AccordionEvent::Change(value) = event;
                    emit_flag(
                        node,
                        "toggle-enabled",
                        &emit,
                        Event::Toggle(id, !value.is_empty()),
                    );
                })
                .child(
                    nsh_base::AccordionItem::element(nsh_base::AccordionItemProps {
                        value: "content".into(),
                        ..Default::default()
                    })
                    .child(heading)
                    .child(panel),
                ),
            )
        }
        "table" => {
            presentation.component(nsh_base::Table::element(Default::default()).child(children))
        }
        // Official main de7f363, nsh-base/src/table.rs, TableRow: only a flex-row
        // host with Row role and children; no column measurement or context.
        "table-row" => presentation.host(
            view()
                .flex_row()
                .role(AccessibilityRole::Row)
                .accessibility_state(move || AccessibilityState {
                    selected: node.get().boolean("selected", false),
                    ..Default::default()
                })
                .child(children),
        ),
        // Official main de7f363, nsh-base/src/table.rs, TableCell: only this role.
        // Use its public host equivalent to retain canonical cell pointer payloads.
        "table-cell" => presentation.host(
            view()
                .style_with(move |s| {
                    let current = node.get();
                    if current.props.contains_key("width")
                        || current.props.contains_key("width-viewport")
                    {
                        s.flex_none()
                    } else {
                        s.flex_1()
                    }
                })
                .min_w_0()
                .role(AccessibilityRole::Cell)
                .child(when(
                    move || !node.get().string("text").is_empty(),
                    move || text(move || node.get().string("text").to_owned()),
                ))
                .child(children),
        ),
        "list-section" => presentation.host(view().role(AccessibilityRole::Group).child(children)),
        "list-section-header" => {
            presentation.host(view().role(AccessibilityRole::Header).child(children))
        }
        "list-section-footer" => presentation.host(view().child(children)),
        "bottom-tabs" => bottom_tabs(node, presentation.children.clone()?, presentation),
        "bottom-tab" => presentation.passive_host(
            scroll()
                .flex_1()
                .min_w_0()
                .min_h_0()
                .role(AccessibilityRole::Region)
                .label(move || node.get().string("title").to_owned())
                .child(children),
        ),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_core::element::Style;
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::{Value, json};
    use std::{cell::Cell, rc::Rc, sync::Mutex};

    struct Fixture {
        kind: &'static str,
        events: Arc<Mutex<Vec<Event>>>,
    }
    fn node(id: u64, kind: &str, props: Value) -> Signal<Arc<Node>> {
        signal(Arc::new(Node {
            id,
            incarnation: 1,
            kind: kind.into(),
            props: props.as_object().unwrap().clone(),
            ..Default::default()
        }))
    }
    fn presentation(id: u64) -> Presentation {
        Presentation {
            key: format!("collection-{id}").into(),
            test_id: format!("collection-{id}").into(),
            style: Rc::new(Style::default),
            reference: element_ref(),
            theme: signal(Arc::new(crate::style::ThemeView::new(
                tokens(),
                dark(),
                reduce_motion(),
            ))),
            events: None,
            children: None,
        }
    }
    fn retained_editor() -> AnyElement {
        let value = signal(String::from("draft"));
        nsh_base::input()
            .test_id("retained-editor")
            .value(move || value.get())
            .on_change(move |text: &str| value.set(text.to_owned()))
            .into_element()
    }

    fn fixture_patch(renderer: &crate::render::Renderer, generation: &Cell<u64>, ops: Value) {
        let next = generation.get() + 1;
        renderer
            .apply(
                crate::wire::Batch::decode(&json!({"generation":next,"ops":ops}).to_string())
                    .unwrap(),
            )
            .unwrap();
        generation.set(next);
    }

    fn tabs_fixture(fixture: Arc<Fixture>) -> AnyElement {
        let generation = Rc::new(Cell::new(0));
        let accepted = Rc::new(Cell::new(fixture.kind != "bottom-tabs-refuse"));
        let seen = fixture.events.clone();
        let following = accepted.clone();
        let publishing = generation.clone();
        let renderer = crate::render::Renderer::new(move |event, renderer| {
            seen.lock().unwrap().push(event.clone());
            match event {
                Event::Press(selected) if following.get() && [10, 20, 30].contains(&selected) => {
                    let ops = [10,20,30].map(|id| json!({"op":"set-prop","id":id,"property":"selected","value":id==selected}));
                    fixture_patch(&renderer, &publishing, json!(ops));
                }
                Event::Text(id, value) => fixture_patch(
                    &renderer,
                    &publishing,
                    json!([
                        {"op":"set-prop","id":id,"property":"text","value":value}
                    ]),
                ),
                _ => {}
            }
        });
        let mut ops = vec![
            json!({"op":"create-node","id":1,"kind":"bottom-tabs"}),
            json!({"op":"set-prop","id":1,"property":"accessibility-label","value":"Destinations"}),
            json!({"op":"set-prop","id":1,"property":"width","value":480}),
            json!({"op":"set-prop","id":1,"property":"height","value":320}),
        ];
        for (index, (id, title)) in [(10, "One"), (20, "Two"), (30, "Three")]
            .into_iter()
            .enumerate()
        {
            ops.extend([
                json!({"op":"create-node","id":id,"kind":"bottom-tab"}),
                json!({"op":"set-prop","id":id,"property":"title","value":title}),
                json!({"op":"set-prop","id":id,"property":"press-enabled","value":true}),
                json!({"op":"set-prop","id":id,"property":"enabled","value":id!=20}),
                json!({"op":"insert-child","parent":1,"child":id,"index":index}),
                json!({"op":"create-node","id":id+1,"kind":"column"}),
                json!({"op":"set-prop","id":id+1,"property":"appear-enabled","value":true}),
                json!({"op":"insert-child","parent":id,"child":id+1,"index":0}),
                json!({"op":"create-node","id":id+2,"kind":"text-field"}),
                json!({"op":"set-prop","id":id+2,"property":"text","value":format!("draft {title}")}),
                json!({"op":"set-prop","id":id+2,"property":"accessibility-label","value":format!("Editor {title}")}),
                json!({"op":"set-prop","id":id+2,"property":"change-enabled","value":true}),
                json!({"op":"set-prop","id":id+2,"property":"appear-enabled","value":true}),
                json!({"op":"insert-child","parent":id+1,"child":id+2,"index":0}),
                json!({"op":"create-node","id":id+3,"kind":"button"}),
                json!({"op":"set-prop","id":id+3,"property":"text","value":format!("{title} action")}),
                json!({"op":"set-prop","id":id+3,"property":"press-enabled","value":true}),
                json!({"op":"set-prop","id":id+3,"property":"appear-enabled","value":true}),
                json!({"op":"insert-child","parent":id+1,"child":id+3,"index":1}),
            ]);
            if id == 10 {
                ops.extend([
                    json!({"op":"create-node","id":14,"kind":"box"}),
                    json!({"op":"set-prop","id":14,"property":"height","value":800}),
                    json!({"op":"insert-child","parent":11,"child":14,"index":2}),
                ]);
            }
        }
        fixture_patch(&renderer, &generation, json!(ops));
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
                json!([{"op":"move-child","parent":1,"child":30,"index":0}]),
            ),
            (
                "f7",
                json!([{"op":"set-prop","id":10,"property":"selected","value":false},{"op":"set-prop","id":20,"property":"selected","value":false},{"op":"set-prop","id":30,"property":"selected","value":false}]),
            ),
            (
                "f8",
                json!([{"op":"set-prop","id":10,"property":"selected","value":true},{"op":"set-prop","id":30,"property":"selected","value":true}]),
            ),
            (
                "f9",
                json!([{"op":"set-prop","id":10,"property":"selected","value":false},{"op":"set-prop","id":20,"property":"selected","value":false},{"op":"set-prop","id":30,"property":"selected","value":false},{"op":"move-child","parent":1,"child":20,"index":0}]),
            ),
            (
                "f4",
                json!([{"op":"set-prop","id":13,"property":"text","value":"One renamed"}]),
            ),
        ] {
            let editing = renderer.clone();
            let publishing = generation.clone();
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| fixture_patch(&editing, &publishing, ops.clone()),
            );
        }
        renderer.element().into_element()
    }

    #[component]
    fn Collections() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        if fixture.kind == "list-atomic" {
            let renderer = crate::render::Renderer::new(|_, _| {});
            let batch = |generation, ops: Value| {
                crate::wire::Batch::decode(&json!({"generation":generation,"ops":ops}).to_string())
                    .unwrap()
            };
            renderer
                .apply(batch(
                    1,
                    json!([
                        {"op":"create-node","id":1,"kind":"list"},
                        {"op":"create-node","id":10,"kind":"list-item"},
                        {"op":"set-prop","id":10,"property":"text","value":"Original row"},
                        {"op":"set-prop","id":10,"property":"press-enabled","value":true},
                        {"op":"create-node","id":11,"kind":"text-field"},
                        {"op":"set-prop","id":11,"property":"text","value":"Original editor"},
                        {"op":"set-prop","id":11,"property":"accessibility-label","value":"Editor"},
                        {"op":"insert-child","parent":10,"child":11,"index":0},
                        {"op":"insert-child","parent":1,"child":10,"index":0}
                    ]),
                ))
                .unwrap();
            renderer.set_root(1).unwrap();
            let editing = renderer.clone();
            on_key_with(
                "f4",
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    let result = editing.apply(batch(
                        2,
                        json!([
                            {"op":"set-prop","id":11,"property":"text","value":"must not publish"},
                            {"op":"set-prop","id":10,"property":"expanded","value":false},
                            {"op":"set-prop","id":10,"property":"toggle-enabled","value":true}
                        ]),
                    ));
                    assert!(result.unwrap_err().contains("flat/disclosure"));
                    editing
                        .apply(batch(
                            2,
                            json!([
                                {"op":"set-prop","id":10,"property":"text","value":"Retried row"}
                            ]),
                        ))
                        .unwrap();
                },
            );
            return renderer.element().into_element();
        }
        if fixture.kind == "list-item" {
            let parent = node(
                10,
                "list-item",
                json!({"text":"Parent","expanded":false,"toggle-enabled":true}),
            );
            let caption = node(11, "text-field", json!({"text":"Body"}));
            let nested = node(
                12,
                "list-item",
                json!({"text":"Nested","press-enabled":true}),
            );
            let order = signal(vec![(11, 1), (12, 1)]);
            let accepted = signal(false);
            let value = signal(String::from("draft"));
            on_key_with(
                "f5",
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| accepted.set(true),
            );
            on_key_with(
                "f6",
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    order.set(vec![(12, 1), (11, 1)]);
                    let mut next = (*caption.get_untracked()).clone();
                    next.props.insert("text".into(), json!("New body label"));
                    caption.set(Arc::new(next));
                },
            );
            let emit: Emit = Rc::new(move |event| {
                fixture.events.lock().unwrap().push(event.clone());
                if accepted.get_untracked()
                    && let Event::Toggle(10, expanded) = event
                {
                    let mut next = (*parent.get_untracked()).clone();
                    next.props.insert("expanded".into(), json!(expanded));
                    parent.set(Arc::new(next));
                }
            });
            let row_emit = emit.clone();
            let mut authored = presentation(10);
            authored.children = Some(super::super::ChildRenderer {
                identities: order,
                press: Rc::new(|_| {}),
                lookup: Rc::new(move |identity| match identity {
                    (11, 1) => Some(caption),
                    (12, 1) => Some(nested),
                    _ => None,
                }),
                render: Rc::new(move |identity| match identity {
                    (11, 1) => view()
                        .child(text(move || caption.get().string("text").to_owned()))
                        .child(
                            nsh_base::input()
                                .test_id("retained-list-editor")
                                .value(move || value.get())
                                .on_change(move |text: &str| value.set(text.to_owned())),
                        )
                        .into_element(),
                    (12, 1) => element(
                        nested,
                        view().into_element(),
                        row_emit.clone(),
                        presentation(12),
                    )
                    .unwrap(),
                    _ => panic!("unexpected fixture identity"),
                }),
            });
            return element(parent, view().into_element(), emit, authored).unwrap();
        }
        if fixture.kind.starts_with("bottom-tabs") {
            return tabs_fixture(fixture);
        }
        if fixture.kind == "table" {
            let cell = node(3, "table-cell", json!({"text":"Initial"}));
            on_key_with(
                "f5",
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    let mut next = (*cell.get_untracked()).clone();
                    next.props.insert("text".into(), json!("Updated"));
                    cell.set(Arc::new(next));
                },
            );
            on_key_with(
                "f6",
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    let mut next = (*cell.get_untracked()).clone();
                    next.props.insert("width".into(), json!(80));
                    cell.set(Arc::new(next));
                },
            );
            let mut authored = presentation(3);
            let theme = authored.theme;
            authored.style = Rc::new(move || {
                crate::style::compile(
                    &cell.get(),
                    &theme.get(),
                    nsh_core::geometry::Size::default(),
                )
                .unwrap()
            });
            let emit: Emit = Rc::new(|_| {});
            let cell = element(cell, retained_editor(), emit.clone(), authored).unwrap();
            let row = cell;
            let second = element(
                node(
                    4,
                    "table-cell",
                    json!({"text":"a substantially longer label"}),
                ),
                view().into_element(),
                emit.clone(),
                presentation(4),
            )
            .unwrap();
            let third = element(
                node(5, "table-cell", json!({"text":"Short"})),
                view().into_element(),
                emit.clone(),
                presentation(5),
            )
            .unwrap();
            let fourth = element(
                node(6, "table-cell", json!({"text":"Other column"})),
                view().into_element(),
                emit.clone(),
                presentation(6),
            )
            .unwrap();
            let first_row = element(
                node(7, "table-row", json!({"selected":true})),
                view()
                    .flex_row()
                    .w_full()
                    .child(row)
                    .child(second)
                    .into_element(),
                emit.clone(),
                presentation(7),
            )
            .unwrap();
            let second_row = element(
                node(8, "table-row", json!({})),
                view()
                    .flex_row()
                    .w_full()
                    .child(third)
                    .child(fourth)
                    .into_element(),
                emit.clone(),
                presentation(8),
            )
            .unwrap();
            return view()
                .w_96()
                .child(
                    element(
                        node(1, "table", json!({})),
                        view()
                            .w_full()
                            .child(first_row)
                            .child(second_row)
                            .into_element(),
                        emit,
                        presentation(1),
                    )
                    .unwrap(),
                )
                .into_element();
        }
        let disclosure = node(
            1,
            "accordion",
            json!({"text":"Details","selected":false,"toggle-enabled":fixture.kind!="static"}),
        );
        let follow = Rc::new(Cell::new(false));
        let accept = follow.clone();
        on_key_with(
            "f5",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| accept.set(true),
        );
        let emit: Emit = Rc::new(move |event| {
            fixture.events.lock().unwrap().push(event.clone());
            if follow.get()
                && let Event::Toggle(_, open) = event
            {
                let mut next = (*disclosure.get_untracked()).clone();
                next.props.insert("selected".into(), json!(open));
                disclosure.set(Arc::new(next));
            }
        });
        element(disclosure, retained_editor(), emit, presentation(1)).unwrap()
    }
    fn start(kind: &'static str) -> (Headless, Arc<Mutex<Vec<Event>>>) {
        let events = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(Fixture {
                kind,
                events: events.clone(),
            }),
            ..EngineConfig::new(Root::of::<Collections>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        (app, events)
    }
    fn editor(app: &Headless) -> nsh_core::NodeId {
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("retained-editor"))
            .unwrap()
            .id
    }
    #[test]
    fn disclosure_is_controlled_and_keeps_its_editor_across_keyboard_close_reopen() {
        let (mut app, events) = start("accordion");
        app.press("role:button[Details]").unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::Toggle(1, true)]);
        assert_eq!(
            app.screen().count("id:retained-editor").unwrap(),
            0,
            "refused toggle must stay closed"
        );
        app.press_key("f5").unwrap();
        app.press("role:button[Details]").unwrap();
        app.type_text("id:retained-editor", "kept").unwrap();
        let before = editor(&app);
        let before_text = app
            .screen()
            .input_text("id:retained-editor")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("shift+tab").unwrap();
        app.press_key("space").unwrap();
        app.press_key("space").unwrap();
        assert_eq!(editor(&app), before);
        assert_eq!(
            app.screen().input_text("id:retained-editor").unwrap(),
            Some(before_text.as_str())
        );
        assert_eq!(
            *events.lock().unwrap(),
            [
                Event::Toggle(1, true),
                Event::Toggle(1, true),
                Event::Toggle(1, false),
                Event::Toggle(1, true)
            ]
        );
    }
    #[test]
    fn disclosure_without_a_toggle_callback_is_static_content() {
        let (app, events) = start("static");
        assert_eq!(app.screen().count("role:button[Details]").unwrap(), 0);
        assert_eq!(app.screen().count("id:retained-editor").unwrap(), 1);
        assert!(events.lock().unwrap().is_empty());
    }
    #[test]
    fn bottom_tabs_use_native_arrows_skip_disabled_and_follow_canonical_selection() {
        let (mut app, events) = start("bottom-tabs");
        assert_eq!(app.screen().count("role:tab").unwrap(), 3);
        assert_eq!(app.screen().count("role:button[One action]").unwrap(), 1);
        app.press("role:tab[One]").unwrap();
        events.lock().unwrap().clear();
        app.press_key("right").unwrap();
        assert_eq!(
            events
                .lock()
                .unwrap()
                .iter()
                .filter_map(|event| if let Event::Press(id) = event {
                    Some(*id)
                } else {
                    None
                })
                .collect::<Vec<_>>(),
            [30]
        );
        assert!(
            app.screen()
                .accessibility_state("role:tab[Three]")
                .unwrap()
                .selected
        );
        assert_eq!(app.screen().count("role:button[One action]").unwrap(), 0);
        assert_eq!(app.screen().count("role:button[Three action]").unwrap(), 1);
        app.press_key("home").unwrap();
        assert!(
            app.screen()
                .accessibility_state("role:tab[One]")
                .unwrap()
                .selected
        );
        assert_eq!(app.screen().count("role:button[One action]").unwrap(), 1);
    }
    #[test]
    fn static_table_preserves_cell_and_editor_identity_through_a_text_update() {
        let (mut app, _) = start("table");
        assert_eq!(app.screen().count("role:table").unwrap(), 1);
        assert_eq!(app.screen().count("role:row").unwrap(), 2);
        assert_eq!(app.screen().count("role:cell").unwrap(), 4);
        assert!(
            app.screen()
                .accessibility_state("id:collection-7")
                .unwrap()
                .selected
        );
        let bounds = |id: &str| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some(id))
                .unwrap()
                .bounds
        };
        let first = bounds("collection-3");
        let second = bounds("collection-4");
        let third = bounds("collection-5");
        let fourth = bounds("collection-6");
        assert_eq!(first.origin.x, third.origin.x);
        assert_eq!(second.origin.x, fourth.origin.x);
        assert_eq!(first.size.width, third.size.width);
        assert_eq!(second.size.width, fourth.size.width);
        app.press_key("f6").unwrap();
        let explicit = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("collection-3"))
            .unwrap()
            .bounds;
        assert_eq!(
            explicit.size.width,
            px(80.0),
            "authored width overrides equal flexible defaults"
        );
        app.type_text("id:retained-editor", "kept").unwrap();
        let before = editor(&app);
        app.press_key("f5").unwrap();
        app.wait_for("Updated").unwrap();
        assert_eq!(editor(&app), before);
    }
    #[test]
    fn list_disclosure_partitions_body_and_nested_rows_without_replacing_the_editor() {
        let (mut app, events) = start("list-item");
        assert_eq!(app.screen().count("role:button[Nested]").unwrap(), 0);
        app.type_text("id:retained-list-editor", "kept").unwrap();
        let id = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("retained-list-editor"))
            .unwrap()
            .id;
        let before = app
            .screen()
            .input_text("id:retained-list-editor")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press("role:button[Parent]").unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::Toggle(10, true)]);
        assert_eq!(app.screen().count("role:button[Nested]").unwrap(), 0);
        app.press_key("f5").unwrap();
        app.press("role:button[Parent]").unwrap();
        assert_eq!(app.screen().count("role:button[Nested]").unwrap(), 1);
        app.press("role:button[Nested]").unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            [
                Event::Toggle(10, true),
                Event::Toggle(10, true),
                Event::Press(12)
            ]
        );
        app.press_key("f6").unwrap();
        app.wait_for("New body label").unwrap();
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some("retained-list-editor"))
                .unwrap()
                .id,
            id
        );
        assert_eq!(
            app.screen().input_text("id:retained-list-editor").unwrap(),
            Some(before.as_str())
        );
        app.press("role:button[Parent]").unwrap();
        app.press("role:button[Parent]").unwrap();
        assert_eq!(
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some("retained-list-editor"))
                .unwrap()
                .id,
            id
        );
        assert_eq!(
            app.screen().input_text("id:retained-list-editor").unwrap(),
            Some(before.as_str())
        );
    }
    #[test]
    fn list_row_rejects_unavailable_callback_semantics_and_mode_mutation_explicitly() {
        let base = Node {
            kind: "list-item".into(),
            incarnation: 3,
            ..Default::default()
        };
        for flag in [
            "long-press-enabled",
            "double-press-enabled",
            "submit-enabled",
            "change-enabled",
        ] {
            let mut next = base.clone();
            next.props.insert(flag.into(), json!(true));
            assert!(validate(&next).unwrap_err().contains(flag));
        }
        let mut next = base.clone();
        next.props.insert("expanded".into(), json!(false));
        assert!(
            validate_transition(&base, &next)
                .unwrap_err()
                .contains("new node incarnation")
        );
        next.incarnation = 4;
        assert!(validate_transition(&base, &next).is_ok());
    }
    #[test]
    fn changing_native_list_mode_rolls_back_other_edits_and_preserves_retry_generation_and_ids() {
        let (mut app, _) = start("list-atomic");
        let identity = |app: &Headless, id: &str| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some(id))
                .unwrap()
                .id
        };
        let row = identity(&app, "lui-10");
        let editor = identity(&app, "lui-11");
        app.press_key("f4").unwrap();
        app.wait_for("Retried row").unwrap();
        assert_eq!(
            app.screen().input_text("id:lui-11").unwrap(),
            Some("Original editor")
        );
        assert_eq!(identity(&app, "lui-10"), row);
        assert_eq!(identity(&app, "lui-11"), editor);
        assert!(!app.screen().shows("must not publish"));
    }
    fn native_id(app: &Headless, id: u64) -> nsh_core::NodeId {
        let test_id = format!("lui-{id}");
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some(test_id.as_str()))
            .unwrap()
            .id
    }
    fn appearances(events: &Arc<Mutex<Vec<Event>>>, id: u64) -> usize {
        events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| matches!(event,Event::Appear(node) if *node==id))
            .count()
    }
    #[test]
    fn bottom_tab_pages_are_lazy_controlled_and_keep_editor_state_through_reorder() {
        let (mut app, events) = start("bottom-tabs-refuse");
        assert!(
            app.screen()
                .accessibility_state("role:tab[One]")
                .unwrap()
                .selected
        );
        for id in [11, 12, 13] {
            assert_eq!(appearances(&events, id), 1);
        }
        for id in [21, 22, 23, 31, 32, 33] {
            assert_eq!(appearances(&events, id), 0);
        }
        assert!(
            !app.screen()
                .layout_nodes()
                .iter()
                .any(|node| node.test_id.as_deref() == Some("lui-32")),
            "unvisited pages have no native editor"
        );
        app.type_text("id:lui-12", " kept").unwrap();
        let first_id = native_id(&app, 12);
        let first_value = app
            .screen()
            .input_text("id:lui-12")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press("role:tab[Three]").unwrap();
        assert!(
            app.screen()
                .accessibility_state("role:tab[One]")
                .unwrap()
                .selected
        );
        assert_eq!(app.screen().count("role:button[Three action]").unwrap(), 0);
        assert_eq!(
            appearances(&events, 31),
            0,
            "refused activation must not realize or appear its page"
        );
        app.press_key("f5").unwrap();
        app.press("role:tab[Three]").unwrap();
        app.type_text("id:lui-32", " kept").unwrap();
        let third_id = native_id(&app, 32);
        let third_value = app
            .screen()
            .input_text("id:lui-32")
            .unwrap()
            .unwrap()
            .to_owned();
        for id in [31, 32, 33] {
            assert_eq!(appearances(&events, id), 1);
        }
        assert_eq!(
            app.screen().count("role:tab").unwrap(),
            3,
            "page Buttons are not tabs"
        );
        app.press_key("f6").unwrap();
        assert_eq!(native_id(&app, 32), third_id);
        assert_eq!(
            appearances(&events, 31),
            1,
            "reordering a visible page must not re-appear it"
        );
        app.press("role:tab[One]").unwrap();
        assert_eq!(native_id(&app, 12), first_id);
        assert_eq!(
            app.screen().input_text("id:lui-12").unwrap(),
            Some(first_value.as_str())
        );
        for id in [11, 12, 13] {
            assert_eq!(appearances(&events, id), 2);
        }
        app.press("role:tab[Three]").unwrap();
        assert_eq!(native_id(&app, 32), third_id);
        assert_eq!(
            app.screen().input_text("id:lui-32").unwrap(),
            Some(third_value.as_str())
        );
        for id in [31, 32, 33] {
            assert_eq!(appearances(&events, id), 2);
        }
    }
    #[test]
    fn bottom_tab_page_buttons_keep_their_own_activation_and_body_edits_do_not_reappear() {
        let (mut app, events) = start("bottom-tabs");
        let editor = native_id(&app, 12);
        events.lock().unwrap().clear();
        app.press("role:button[One action]").unwrap();
        assert_eq!(*events.lock().unwrap(), [Event::Press(13)]);
        app.press_key("f4").unwrap();
        app.wait_for("One renamed").unwrap();
        assert_eq!(native_id(&app, 12), editor);
        assert_eq!(*events.lock().unwrap(), [Event::Press(13)]);
        assert!(
            app.screen()
                .accessibility_state("role:tab[One]")
                .unwrap()
                .selected
        );
    }
    #[test]
    fn bottom_tab_effective_selection_matches_first_selected_and_first_child_defaults() {
        let (mut app, events) = start("bottom-tabs");
        app.press("role:tab[Three]").unwrap();
        app.press_key("f8").unwrap();
        assert!(
            app.screen()
                .accessibility_state("role:tab[One]")
                .unwrap()
                .selected
        );
        assert!(
            !app.screen()
                .accessibility_state("role:tab[Three]")
                .unwrap()
                .selected
        );
        app.press_key("f7").unwrap();
        assert!(
            app.screen()
                .accessibility_state("role:tab[One]")
                .unwrap()
                .selected
        );
        app.press_key("f9").unwrap();
        assert!(
            app.screen()
                .accessibility_state("role:tab[Two]")
                .unwrap()
                .selected
        );
        assert!(
            app.screen()
                .accessibility_state("role:tab[Two]")
                .unwrap()
                .disabled
        );
        assert_eq!(
            app.screen().count("role:button[Two action]").unwrap(),
            1,
            "disabled first destination remains the source fallback page"
        );
        assert_eq!(appearances(&events, 21), 1);
    }
    #[test]
    fn bottom_tab_page_keeps_its_own_scroll_position_when_hidden_and_shown() {
        let (mut app, _) = start("bottom-tabs");
        let editor_y = |app: &Headless| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some("lui-12"))
                .unwrap()
                .bounds
                .origin
                .y
        };
        let before = editor_y(&app);
        app.scroll("id:lui-10", px(100.0)).unwrap();
        let scrolled = editor_y(&app);
        assert!(scrolled < before);
        app.press("role:tab[Three]").unwrap();
        app.press("role:tab[One]").unwrap();
        assert_eq!(editor_y(&app), scrolled);
        app.scroll("id:lui-10", px(-100.0)).unwrap();
        assert_eq!(editor_y(&app), before);
        assert_eq!(
            app.screen().input_text("id:lui-12").unwrap(),
            Some("draft One")
        );
    }
}
