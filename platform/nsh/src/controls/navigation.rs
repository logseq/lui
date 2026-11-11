//! Authored-child navigation composed from public NSH controllers and primitives.
use super::{ChildRenderer, Emit, Presentation, label};
use crate::{store::Node, ui};
use nsh_core::{AccessibilityCurrent, AccessibilityState, element::Style, prelude::*};
use std::sync::Arc;

pub(super) fn supported(kind: &str) -> bool {
    matches!(
        kind,
        "breadcrumb" | "pagination" | "stepper" | "step" | "timeline" | "timeline-item"
    )
}

/// Keep layout on the actual authored-child container. The outer semantic
/// group owns padding, size, identity and pointer listeners; Toolbar owns only
/// native roving focus and the child row, including its authored gap/main/cross.
fn horizontal(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    presentation: Presentation,
    breadcrumb: bool,
) -> AnyElement {
    let theme = presentation.theme;
    let body = match (breadcrumb, presentation.children.clone()) {
        (true, Some(source)) => each(
            source.identities,
            |identity| *identity,
            move |identity, index| {
                vec![
                    when(
                        move || index.get() > 0,
                        move || {
                            ui::icon("chevron-right", px(12.0))
                                .text_color(move || ui::color(theme, "muted-foreground"))
                        },
                    )
                    .into_element(),
                    (source.render)(identity.get_untracked()),
                ]
            },
        ),
        _ => children,
    };
    let row = nsh_base::Toolbar::element(nsh_base::ToolbarProps {
        accessibility_label: Prop::bind(move || Some(label(node))),
        ..Default::default()
    })
    .flex_1()
    .min_w_0()
    .items_center()
    .gap(px(if breadcrumb { 4.0 } else { 2.0 }))
    .state_inline_style(move || {
        Style::from_decls(
            crate::style::content_layout(&node.get(), &theme.get())
                .expect("validated navigation content layout"),
        )
    })
    .child(body);
    presentation.host(
        view()
            .flex_row()
            .min_w_0()
            .role(AccessibilityRole::Group)
            .label(move || label(node))
            .child(row),
    )
}

#[derive(Clone, Copy)]
struct StepPosition {
    index: ReadSignal<usize>,
    count: Memo<usize>,
    active: Memo<i64>,
}
impl StepPosition {
    fn state(self) -> &'static str {
        let index = self.index.get() as i64;
        match index.cmp(&self.active.get()) {
            std::cmp::Ordering::Less => "completed",
            std::cmp::Ordering::Equal => "active",
            std::cmp::Ordering::Greater => "pending",
        }
    }
}

fn stepper(
    node: Signal<Arc<Node>>,
    source: ChildRenderer,
    presentation: Presentation,
) -> AnyElement {
    // Borrow once per structural change rather than cloning the sibling vector
    // from each Step's visual binding. Keyed owners keep the same Step host.
    let count = computed(move || source.identities.with(Vec::len));
    let active = computed(move || {
        node.get()
            .props
            .get("active")
            .and_then(serde_json::Value::as_i64)
            .unwrap_or(0)
    });
    let body = each(
        source.identities,
        |identity| *identity,
        move |identity, index| {
            provide_context(StepPosition {
                index,
                count,
                active,
            });
            (source.render)(identity.get_untracked())
        },
    );
    presentation.host(
        view()
            .flex_row()
            .items_center()
            .gap(px(8.0))
            .role(AccessibilityRole::List)
            .label(move || label(node))
            .child(body),
    )
}

fn step(node: Signal<Arc<Node>>, presentation: Presentation) -> AnyElement {
    let position = use_context::<StepPosition>().unwrap_or_else(|| StepPosition {
        index: signal(0).read_only(),
        count: computed(|| 1),
        active: computed(|| 0),
    });
    let theme = presentation.theme;
    let indicator = view()
        .size(px(24.0))
        .flex_shrink_0()
        .rounded_full()
        .items_center()
        .justify_center()
        .border_1()
        .accessibility_elements_hidden(true)
        .style_with(move |style| {
            let pending = position.state() == "pending";
            style
                .border_color(ui::color(
                    theme,
                    if pending {
                        "muted-foreground"
                    } else {
                        "primary"
                    },
                ))
                .bg(ui::color(theme, "primary").opacity(if pending { 0.0 } else { 1.0 }))
                .text_color(ui::color(
                    theme,
                    if pending {
                        "muted-foreground"
                    } else {
                        "primary-foreground"
                    },
                ))
        })
        .child(
            when(
                move || position.state() == "completed",
                || ui::icon("check", px(12.0)),
            )
            .otherwise(move || text(move || (position.index.get() + 1).to_string()).text_xs()),
        );
    presentation.host(
        view()
            .flex_row()
            .flex_1()
            .items_center()
            .gap(px(6.0))
            .role(AccessibilityRole::Group)
            .label(move || {
                SharedString::from(format!(
                    "{} ({})",
                    node.get().string("text"),
                    position.state()
                ))
            })
            .accessibility_state(move || AccessibilityState {
                current: (position.state() == "active").then_some(AccessibilityCurrent::Step),
                ..Default::default()
            })
            .child(indicator)
            .child(
                text(move || node.get().string("text").to_owned())
                    .accessibility_elements_hidden(true)
                    .text_color(move || {
                        ui::color(
                            theme,
                            if position.state() == "pending" {
                                "muted-foreground"
                            } else {
                                "foreground"
                            },
                        )
                    })
                    .style_with(move |style| {
                        style.font_weight(if position.state() == "active" {
                            FontWeight::SEMIBOLD
                        } else {
                            FontWeight::NORMAL
                        })
                    }),
            )
            .child(when(
                move || position.index.get() + 1 < position.count.get(),
                move || {
                    view()
                        .test_id("lui-step-connector")
                        .flex_1()
                        .min_w(px(20.0))
                        .h(px(1.0))
                        .bg(move || ui::color(theme, "border"))
                        .accessibility_elements_hidden(true)
                },
            )),
    )
}

fn indicator_role(node: Signal<Arc<Node>>) -> &'static str {
    match node.get().string("variant") {
        "primary" => "primary",
        "destructive" => "destructive",
        _ => "muted-foreground",
    }
}

fn timeline_item(node: Signal<Arc<Node>>, presentation: Presentation) -> AnyElement {
    let theme = presentation.theme;
    // There is no public base TimelineItem. Use its actual native interactive
    // host and the existing canonical NativeEvents path: a typed Button would
    // discard modifiers and PressDetail/down/up payloads on the pinned API.
    let indicator = view()
        .size(px(24.0))
        .flex_shrink_0()
        .items_center()
        .justify_center()
        .rounded_full()
        .accessibility_elements_hidden(true)
        .text_color(move || ui::color(theme, indicator_role(node)))
        .bg(move || {
            ui::color(theme, indicator_role(node)).opacity(
                if node.get().string("icon").is_empty() && node.get().string("indicator").is_empty()
                {
                    0.0
                } else {
                    0.16
                },
            )
        })
        .child(
            when(
                move || !node.get().string("icon").is_empty(),
                move || {
                    ui::icon(
                        move || SharedString::from(node.get().string("icon").to_owned()),
                        px(16.0),
                    )
                },
            )
            .otherwise(move || {
                when(
                    move || !node.get().string("indicator").is_empty(),
                    move || {
                        text(move || node.get().string("indicator").to_owned())
                            .text_xs()
                            .font_weight(FontWeight::SEMIBOLD)
                    },
                )
                .otherwise(move || {
                    view()
                        .size(px(10.0))
                        .rounded_full()
                        .bg(move || ui::color(theme, indicator_role(node)))
                })
            }),
        );
    let marker = view()
        .flex_col()
        .items_center()
        .gap(px(4.0))
        .child(indicator)
        .child(when(
            move || node.get().boolean("connector", true),
            move || {
                view()
                    .test_id("lui-timeline-connector")
                    .w(px(1.0))
                    .min_h(px(24.0))
                    .flex_1()
                    .bg(move || ui::color(theme, "border"))
                    .accessibility_elements_hidden(true)
            },
        ));
    let body = view()
        .flex_col()
        .min_w_0()
        .flex_1()
        .gap(px(2.0))
        .child(
            text(move || node.get().string("title").to_owned()).font_weight(FontWeight::SEMIBOLD),
        )
        .child(when(
            move || !node.get().string("description").is_empty(),
            move || {
                text(move || node.get().string("description").to_owned())
                    .text_color(move || ui::color(theme, "muted-foreground"))
            },
        ))
        .child(when(
            move || !node.get().string("meta").is_empty(),
            move || {
                text(move || node.get().string("meta").to_owned())
                    .text_xs()
                    .text_color(move || ui::color(theme, "muted-foreground"))
            },
        ));
    presentation.host(
        view()
            .flex_row()
            .items_stretch()
            .gap(px(10.0))
            .p_2()
            .rounded(move || ui::radius(theme))
            .role(move || {
                if node.get().boolean("press-enabled", false) {
                    AccessibilityRole::Button
                } else {
                    AccessibilityRole::Group
                }
            })
            .label(move || SharedString::from(node.get().string("title").to_owned()))
            .accessibility_state(move || AccessibilityState {
                selected: node.get().boolean("selected", false),
                ..Default::default()
            })
            .bg(move || {
                ui::color(theme, "accent").opacity(if node.get().boolean("selected", false) {
                    1.0
                } else {
                    0.0
                })
            })
            .text_color(move || {
                ui::color(
                    theme,
                    if node.get().boolean("selected", false) {
                        "accent-foreground"
                    } else {
                        "foreground"
                    },
                )
            })
            .style_with(move |style| {
                style
                    .transition_colors()
                    .duration(if theme.get().reduced_motion {
                        0.0
                    } else {
                        120.0
                    })
            })
            .hover(|style| {
                style.bg(move || {
                    ui::color(theme, "accent").opacity(
                        if node.get().boolean("press-enabled", false)
                            || node.get().boolean("selected", false)
                        {
                            1.0
                        } else {
                            0.0
                        },
                    )
                })
            })
            .active(|style| {
                style.opacity(move || {
                    if node.get().boolean("press-enabled", false) {
                        0.7
                    } else {
                        1.0
                    }
                })
            })
            .focus_visible(|style| {
                style
                    .outline(px(2.0))
                    .outline_color(move || ui::color(theme, "ring"))
            })
            .child(marker)
            .child(body)
            .child(when(
                move || node.get().boolean("press-enabled", false),
                move || {
                    ui::icon("chevron-right", px(14.0))
                        .text_color(move || ui::color(theme, "muted-foreground"))
                },
            )),
    )
}

pub(super) fn element(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    _emit: Emit,
    presentation: Presentation,
) -> Option<AnyElement> {
    Some(match node.get_untracked().kind.as_str() {
        "breadcrumb" => horizontal(node, children, presentation, true),
        "pagination" => horizontal(node, children, presentation, false),
        "stepper" => {
            let source = presentation
                .children
                .clone()
                .expect("Stepper requires retained child rendering");
            stepper(node, source, presentation)
        }
        "step" => step(node, presentation),
        "timeline" => presentation.host(
            view()
                .flex_col()
                .role(AccessibilityRole::List)
                .label(move || label(node))
                .child(children),
        ),
        "timeline-item" => timeline_item(node, presentation),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        events::PointerKind,
        render::{Event, Renderer},
        wire::Batch,
    };
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::{Value, json};
    use std::{cell::Cell, rc::Rc, sync::Mutex};

    struct Fixture {
        kind: &'static str,
        events: Arc<Mutex<Vec<Event>>>,
    }
    fn patch(renderer: &Renderer, generation: &Cell<u64>, ops: Value) {
        let next = generation.get() + 1;
        renderer
            .apply(Batch::decode(&json!({"generation":next,"ops":ops}).to_string()).unwrap())
            .unwrap();
        generation.set(next);
    }
    fn create(ops: &mut Vec<Value>, id: u64, kind: &str, parent: u64, index: usize, props: Value) {
        ops.push(json!({"op":"create-node","id":id,"kind":kind}));
        for (property, value) in props.as_object().unwrap() {
            ops.push(json!({"op":"set-prop","id":id,"property":property,"value":value}));
        }
        ops.push(json!({"op":"insert-child","parent":parent,"child":id,"index":index}));
    }
    #[component]
    fn NavigationProbe() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        let observed = fixture.events.clone();
        let generation = Rc::new(Cell::new(0));
        let publishing = generation.clone();
        let renderer = Renderer::new(move |event, renderer| {
            observed.lock().unwrap().push(event.clone());
            if let Event::Text(id, value) = event {
                patch(
                    &renderer,
                    &publishing,
                    json!([{"op":"set-prop","id":id,"property":"text","value":value}]),
                );
            }
        });
        let mut ops = vec![json!({"op":"create-node","id":1,"kind":"column"})];
        create(
            &mut ops,
            2,
            "text-field",
            1,
            0,
            json!({"text":"anchor","accessibility-label":"Before navigation"}),
        );
        match fixture.kind {
            "breadcrumb" | "pagination" => {
                create(
                    &mut ops,
                    10,
                    fixture.kind,
                    1,
                    1,
                    json!({"accessibility-label":"Navigation","width":500,"gap":12}),
                );
                for (index, (id, name)) in [(11, "First"), (12, "Disabled"), (13, "Last")]
                    .into_iter()
                    .enumerate()
                {
                    create(
                        &mut ops,
                        id,
                        "button",
                        10,
                        index,
                        json!({"text":name,"enabled":id!=12,"press-enabled":true}),
                    );
                }
                create(
                    &mut ops,
                    14,
                    "text-field",
                    10,
                    3,
                    json!({"text":"draft","accessibility-label":"Retained editor","change-enabled":true,"width":120}),
                );
            }
            "stepper" => {
                create(
                    &mut ops,
                    10,
                    "stepper",
                    1,
                    1,
                    json!({"accessibility-label":"Progress"}),
                );
                for (index, (id, name)) in [(11, "One"), (12, "Two"), (13, "Three")]
                    .into_iter()
                    .enumerate()
                {
                    create(&mut ops, id, "step", 10, index, json!({"text":name}));
                }
            }
            "timeline" => {
                create(
                    &mut ops,
                    10,
                    "timeline",
                    1,
                    1,
                    json!({"accessibility-label":"History","gap":7}),
                );
                create(
                    &mut ops,
                    11,
                    "timeline-item",
                    10,
                    0,
                    json!({"title":"Entry","description":"Before","meta":"Yesterday","indicator":"A","variant":"primary","press-enabled":true,"pointer-enabled":true}),
                );
                create(
                    &mut ops,
                    12,
                    "timeline-item",
                    10,
                    1,
                    json!({"title":"Passive","connector":false}),
                );
            }
            other => panic!("unknown fixture {other}"),
        }
        patch(&renderer, &generation, json!(ops));
        renderer.set_root(1).unwrap();
        let updates = match fixture.kind {
            "breadcrumb" | "pagination" => vec![
                (
                    "f5",
                    json!([{"op":"set-prop","id":10,"property":"gap","value":20},{"op":"set-prop","id":10,"property":"main","value":"end"},{"op":"set-prop","id":10,"property":"cross","value":"center"}]),
                ),
                (
                    "f6",
                    json!([{"op":"move-child","parent":10,"child":13,"index":0}]),
                ),
            ],
            "stepper" => vec![
                (
                    "f5",
                    json!([{"op":"set-prop","id":10,"property":"active","value":1}]),
                ),
                (
                    "f6",
                    json!([{"op":"move-child","parent":10,"child":13,"index":0}]),
                ),
                (
                    "f7",
                    json!([{"op":"set-prop","id":10,"property":"active","value":5}]),
                ),
                (
                    "f8",
                    json!([{"op":"set-prop","id":10,"property":"active","value":-1}]),
                ),
            ],
            _ => vec![
                (
                    "f5",
                    json!([
                        {"op":"set-prop","id":11,"property":"title","value":"After"},
                        {"op":"set-prop","id":11,"property":"description","value":"New detail"},
                        {"op":"set-prop","id":11,"property":"meta","value":"Now"},
                        {"op":"set-prop","id":11,"property":"indicator","value":"B"},
                        {"op":"set-prop","id":11,"property":"icon","value":"check"},
                        {"op":"set-prop","id":11,"property":"variant","value":"destructive"},
                        {"op":"set-prop","id":11,"property":"connector","value":false},
                        {"op":"set-prop","id":11,"property":"selected","value":true}
                    ]),
                ),
                (
                    "f6",
                    json!([{"op":"set-prop","id":11,"property":"icon","value":""}]),
                ),
                (
                    "f7",
                    json!([{"op":"set-prop","id":11,"property":"indicator","value":""},{"op":"set-prop","id":11,"property":"press-enabled","value":false},{"op":"set-prop","id":11,"property":"pointer-enabled","value":false}]),
                ),
            ],
        };
        for (key, ops) in updates {
            let renderer = renderer.clone();
            let generation = generation.clone();
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| patch(&renderer, &generation, ops.clone()),
            );
        }
        renderer.element()
    }
    fn start(kind: &'static str) -> (Headless, Arc<Mutex<Vec<Event>>>) {
        let events = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(Fixture {
                kind,
                events: events.clone(),
            }),
            ..EngineConfig::new(Root::of::<NavigationProbe>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        (app, events)
    }
    fn native(app: &Headless, id: u64) -> nsh_testing::LayoutNode {
        let identifier = format!("lui-{id}");
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some(identifier.as_str()))
            .unwrap()
    }
    #[test]
    fn authored_navigation_uses_native_roving_without_activating_on_focus() {
        for kind in ["breadcrumb", "pagination"] {
            let (mut app, events) = start(kind);
            assert_eq!(app.screen().count("role:group[Navigation]").unwrap(), 1);
            assert_eq!(app.screen().count("role:toolbar[Navigation]").unwrap(), 1);
            assert_eq!(
                app.screen().count("role:button").unwrap(),
                3,
                "no generated page controls"
            );
            app.type_text("id:lui-2", "").unwrap();
            app.press_key("tab").unwrap();
            app.press_key("right").unwrap();
            assert!(
                events.lock().unwrap().is_empty(),
                "moving native focus must not activate a destination"
            );
            app.press_key("space").unwrap();
            assert_eq!(*events.lock().unwrap(), [Event::Press(13)]);
            app.press_key("home").unwrap();
            app.press_key("space").unwrap();
            assert_eq!(
                *events.lock().unwrap(),
                [Event::Press(13), Event::Press(11)]
            );
        }
    }
    #[test]
    fn navigation_layout_reaches_children_and_reorder_keeps_editor_identity() {
        for kind in ["breadcrumb", "pagination"] {
            let (mut app, _) = start(kind);
            app.type_text("id:lui-14", " kept").unwrap();
            let before = native(&app, 14);
            let text = app
                .screen()
                .input_text("id:lui-14")
                .unwrap()
                .unwrap()
                .to_owned();
            let original = native(&app, 11).bounds;
            app.press_key("f5").unwrap();
            let first = native(&app, 11).bounds;
            let second = native(&app, 12).bounds;
            assert!(
                first.origin.x > original.origin.x,
                "authored main=end must reach the child row"
            );
            assert!(second.origin.x - first.origin.x - first.size.width >= px(20.0));
            app.press_key("f6").unwrap();
            assert_eq!(native(&app, 14).id, before.id);
            assert_eq!(
                app.screen().input_text("id:lui-14").unwrap(),
                Some(text.as_str())
            );
            assert!(native(&app, 13).bounds.origin.x < native(&app, 11).bounds.origin.x);
        }
    }
    #[test]
    fn steps_follow_default_active_live_values_and_keyed_source_positions() {
        let (mut app, events) = start("stepper");
        assert_eq!(app.screen().count("role:list[Progress]").unwrap(), 1);
        assert_eq!(app.screen().count("role:group[One (active)]").unwrap(), 1);
        assert_eq!(app.screen().count("role:group[Two (pending)]").unwrap(), 1);
        assert_eq!(app.screen().count("id:lui-step-connector").unwrap(), 2);
        assert_eq!(
            app.screen()
                .accessibility_state("id:lui-11")
                .unwrap()
                .current,
            Some(AccessibilityCurrent::Step)
        );
        let before = native(&app, 11).id;
        app.press_key("f5").unwrap();
        assert_eq!(
            app.screen().count("role:group[One (completed)]").unwrap(),
            1
        );
        assert_eq!(
            app.screen()
                .accessibility_state("id:lui-12")
                .unwrap()
                .current,
            Some(AccessibilityCurrent::Step)
        );
        app.press_key("f6").unwrap();
        assert_eq!(native(&app, 11).id, before);
        assert_eq!(
            app.screen().count("role:group[Three (completed)]").unwrap(),
            1
        );
        assert_eq!(app.screen().count("role:group[One (active)]").unwrap(), 1);
        app.press_key("f7").unwrap();
        for name in ["One", "Two", "Three"] {
            assert_eq!(
                app.screen()
                    .count(&format!("role:group[{name} (completed)]"))
                    .unwrap(),
                1
            );
        }
        app.press_key("f8").unwrap();
        for name in ["One", "Two", "Three"] {
            assert_eq!(
                app.screen()
                    .count(&format!("role:group[{name} (pending)]"))
                    .unwrap(),
                1
            );
        }
        assert!(events.lock().unwrap().is_empty());
    }
    #[test]
    fn timeline_uses_live_content_marker_precedence_and_retains_its_host() {
        let (mut app, _) = start("timeline");
        assert_eq!(app.screen().count("role:list[History]").unwrap(), 1);
        assert_eq!(app.screen().count("role:button[Entry]").unwrap(), 1);
        assert_eq!(app.screen().count("role:group[Passive]").unwrap(), 1);
        assert_eq!(
            app.screen().count("id:lui-timeline-connector").unwrap(),
            1,
            "connector defaults true, explicit false wins"
        );
        assert_eq!(app.screen().count("text:A").unwrap(), 1);
        let before = native(&app, 11).id;
        app.press_key("f5").unwrap();
        assert_eq!(native(&app, 11).id, before);
        assert!(
            app.screen()
                .accessibility_state("role:button[After]")
                .unwrap()
                .selected
        );
        for value in ["New detail", "Now"] {
            assert_eq!(app.screen().count(&format!("text:{value}")).unwrap(), 1);
        }
        assert_eq!(
            app.screen().count("text:B").unwrap(),
            0,
            "icon takes precedence over indicator text"
        );
        assert_eq!(app.screen().count("id:lui-timeline-connector").unwrap(), 0);
        app.press_key("f6").unwrap();
        assert_eq!(app.screen().count("text:B").unwrap(), 1);
        app.press_key("f7").unwrap();
        assert_eq!(native(&app, 11).id, before);
        assert_eq!(app.screen().count("text:B").unwrap(), 0);
        assert_eq!(app.screen().count("role:group[After]").unwrap(), 1);
    }
    #[test]
    fn timeline_item_preserves_native_pointer_modifiers_and_keyboard_activation() {
        let (mut app, events) = start("timeline");
        app.hold_keys("ctrl+shift+meta+alt", true).unwrap();
        app.press("role:button[Entry]").unwrap();
        app.hold_keys("ctrl+shift+meta+alt", false).unwrap();
        let observed = events.lock().unwrap().clone();
        assert_eq!(
            observed
                .iter()
                .filter(|event| matches!(event, Event::NativePress(11, 7)))
                .count(),
            1
        );
        for kind in [PointerKind::Down, PointerKind::Up, PointerKind::PressDetail] {
            assert_eq!(observed.iter().filter(|event| matches!(event, Event::Pointer { node:11, kind:current, detail } if *current == kind && detail.modifiers == 7 && detail.x.is_finite() && detail.y.is_finite() && detail.button == 0 && detail.target_class.is_empty())).count(), 1, "{observed:?}");
        }
        events.lock().unwrap().clear();
        app.type_text("id:lui-2", "").unwrap();
        app.press_key("tab").unwrap();
        app.press_key("space").unwrap();
        assert_eq!(
            events
                .lock()
                .unwrap()
                .iter()
                .filter(|event| matches!(event, Event::Press(11)))
                .count(),
            1
        );
        app.press_key("f7").unwrap();
        events.lock().unwrap().clear();
        app.press("id:lui-11").unwrap();
        assert!(
            events.lock().unwrap().is_empty(),
            "live flags must guard existing listeners"
        );
    }
}
