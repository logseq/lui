//! Canonical LUI surfaces composed from public NSH surface components.
use super::{Emit, Presentation, emit_flag, enabled, label};
use crate::{render::Event, store::Node, ui};
use nsh_core::{
    AccessibilityActionDef, StyleKey, StyleValue, element::StyleRefinement, prelude::*,
};
use std::sync::Arc;

mod native_split;

pub(super) fn supported(kind: &str) -> bool {
    matches!(kind, "drawer" | "resizable" | "split")
}

pub(super) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "drawer" && node.children.len() != 2 {
        return Err("NSH drawer requires its sidebar and main-content children".into());
    }
    if node.kind == "split" {
        native_split::validate(node)?;
    }
    Ok(())
}

pub(super) fn element(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    emit: Emit,
    presentation: Presentation,
) -> Option<AnyElement> {
    match node.get_untracked().kind.as_str() {
        "drawer" => Some(drawer(node, emit, presentation)),
        "resizable" => Some(resizable(node, children, presentation)),
        "split" => Some(native_split::element(node, emit, presentation)),
        _ => None,
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct WidthState {
    source: Option<f32>,
    minimum: f32,
    maximum: f32,
    width: Option<f32>,
}

impl WidthState {
    fn read(node: &Node) -> Self {
        let source = node
            .props
            .get("width")
            .and_then(serde_json::Value::as_f64)
            .map(|width| width as f32);
        let minimum = (node.number("min-width", 0.0) as f32).max(0.0);
        let maximum = (node.number("max-width", f32::MAX as f64) as f32).max(minimum);
        Self {
            source,
            minimum,
            maximum,
            width: source.map(|width| width.clamp(minimum, maximum)),
        }
    }

    fn reconcile(self, mut next: Self) -> Self {
        if self.source == next.source {
            next.width = self
                .width
                .map(|width| width.clamp(next.minimum, next.maximum));
        }
        next
    }

    fn resize(mut self, width: f32) -> Self {
        self.width = Some(width.clamp(self.minimum, self.maximum));
        self
    }
}

fn resizable(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    mut presentation: Presentation,
) -> AnyElement {
    let source = computed(move || WidthState::read(&node.get()));
    let width = signal(source.get_untracked());
    effect(move || {
        let next = width.get_untracked().reconcile(source.get());
        if width.get_untracked() != next {
            width.set(next);
        }
    });
    let measured = stored(0.0_f32);
    let drag_start = stored(0.0_f32);
    let authored = presentation.style.clone();
    presentation.style = std::rc::Rc::new(move || {
        let authored = authored();
        match width.get().width {
            Some(width) => authored.with(
                StyleKey::Width,
                StyleKey::Width
                    .parse_value(StyleValue::Number(width))
                    .expect("bounded native resizable width"),
            ),
            None => authored,
        }
    });
    let id = node.get_untracked().id;
    let name = move || {
        let authored = label(node);
        if authored.is_empty() {
            "Resizable".into()
        } else {
            authored
        }
    };
    let handle = nsh_base::ResizeHandle::element(nsh_base::ResizeHandleProps {
        edge: Some(nsh_base::HandleEdge::Trailing).into(),
        disabled: Prop::bind(move || !enabled(node)),
        accessibility_label: Prop::bind(move || Some(name())),
        ..Default::default()
    })
    .test_id(&format!("lui-{id}-resize-handle"))
    .on_event(move |event: &nsh_base::ResizeHandleEvent| {
        if !enabled(node) {
            return;
        }
        match event {
            nsh_base::ResizeHandleEvent::DragStart => {
                drag_start.replace(
                    width
                        .get_untracked()
                        .width
                        .unwrap_or_else(|| measured.get()),
                );
            }
            nsh_base::ResizeHandleEvent::DragMove(offset) => {
                width.set(width.get_untracked().resize(drag_start.get() + offset.0));
            }
            nsh_base::ResizeHandleEvent::DragEnd(_)
            | nsh_base::ResizeHandleEvent::StateChange(_) => {}
        }
    });
    // ResizeHandle owns pointer capture. The existing LUI root provides the
    // adjustable actions because the public handle has no action callback prop.
    presentation.host(
        view()
            .relative()
            .role(AccessibilityRole::Adjustable)
            .label(name)
            .on_layout(move |bounds: &Bounds<Points>| {
                measured.replace(bounds.size.width.0);
            })
            .accessibility_actions(vec![
                AccessibilityActionDef {
                    name: "increment".into(),
                    label: None,
                },
                AccessibilityActionDef {
                    name: "decrement".into(),
                    label: None,
                },
            ])
            .on_accessibility_action(move |action: &str| {
                if !enabled(node) {
                    return;
                }
                let by = match action {
                    "increment" => 16.0,
                    "decrement" => -16.0,
                    _ => return,
                };
                let state = width.get_untracked();
                width.set(state.resize(state.width.unwrap_or_else(|| measured.get()) + by));
            })
            .child(children)
            .child(handle),
    )
}

fn drawer(node: Signal<Arc<Node>>, emit: Emit, presentation: Presentation) -> AnyElement {
    let children = presentation
        .children
        .as_ref()
        .expect("drawer child renderer")
        .clone();
    let identities = children.identities;
    let sidebar_identity = computed(move || identities.get().first().copied());
    let main_identity = computed(move || identities.get().get(1).copied());
    let sidebar = children.render.clone();
    let main = children.render;
    let id = node.get_untracked().id;
    let theme = presentation.theme;
    let authored = presentation.style.clone();
    let sheet = nsh_base::Sheet::element(nsh_base::SheetProps {
        open: Prop::bind(move || Some(node.get().boolean("selected", false))),
        side: Placement::Left.into(),
        close_on_escape: Prop::bind(move || enabled(node)),
        close_on_backdrop_press: Prop::bind(move || enabled(node)),
        popup_class: Some("p-4 gap-3 border".into()).into(),
        popup_style: Prop::bind(move || {
            let width = node.get().number("width", 360.0) as f32;
            ui::part(
                StyleRefinement::default()
                    .w(px(width))
                    .max_w(nsh_core::element::window().width)
                    .bg(ui::color(theme, "background"))
                    .text_color(ui::color(theme, "foreground"))
                    .border_color(ui::color(theme, "border")),
            )
            .then(&authored())
        }),
        backdrop_style: Prop::bind(move || {
            ui::part(StyleRefinement::default().bg(ui::color(theme, "background").opacity(0.6)))
        }),
        ..Default::default()
    })
    .on_event(move |event: &nsh_base::SheetEvent| {
        if let nsh_base::SheetEvent::OpenChange(selected, _) = event {
            emit_flag(node, "toggle-enabled", &emit, Event::Toggle(id, *selected));
        }
    })
    .child(
        view()
            .role(AccessibilityRole::Group)
            .label(move || label(node))
            .child(dynamic(move || {
                sidebar_identity.get().map(|identity| sidebar(identity))
            })),
    );
    // The sidebar is the first canonical child; the second remains in flow.
    // Sheet owns modal focus, dismissal and reduced-motion-aware transitions.
    presentation.host_identity(
        view()
            .size_full()
            .child(dynamic(move || {
                main_identity.get().map(|identity| main(identity))
            }))
            .child(sheet),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{render::Renderer, wire::Batch};
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::json;
    use std::{
        cell::Cell,
        rc::Rc,
        sync::{
            Mutex,
            atomic::{AtomicBool, Ordering},
        },
    };

    #[derive(Clone)]
    struct Fixture {
        follow: Arc<AtomicBool>,
        events: Arc<Mutex<Vec<Event>>>,
    }

    #[component]
    fn ResizableProbe() -> impl IntoElement {
        let generation = Rc::new(Cell::new(1_u64));
        let renderer = Renderer::new(move |event, renderer| {
            let operations = match event {
                Event::Text(3, text) => {
                    vec![json!({"op":"set-prop","id":3,"property":"text","value":text})]
                }
                Event::Press(4) | Event::NativePress(4, _) => {
                    vec![json!({"op":"set-prop","id":2,"property":"width","value":140})]
                }
                Event::Press(5) | Event::NativePress(5, _) => {
                    vec![json!({"op":"set-prop","id":2,"property":"max-width","value":150})]
                }
                _ => Vec::new(),
            };
            if !operations.is_empty() {
                generation.set(generation.get() + 1);
                renderer
                    .apply(
                        Batch::decode(
                            &json!({"generation":generation.get(),"ops":operations}).to_string(),
                        )
                        .unwrap(),
                    )
                    .unwrap();
            }
        });
        renderer.apply(Batch::decode(&json!({"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"set-prop","id":1,"property":"width","value":600},
            {"op":"create-node","id":2,"kind":"resizable"},
            {"op":"set-prop","id":2,"property":"width","value":200},
            {"op":"set-prop","id":2,"property":"height","value":100},
            {"op":"set-prop","id":2,"property":"min-width","value":120},
            {"op":"set-prop","id":2,"property":"max-width","value":260},
            {"op":"set-prop","id":2,"property":"accessibility-label","value":"Inspector width"},
            {"op":"create-node","id":3,"kind":"text-field"},
            {"op":"set-prop","id":3,"property":"accessibility-label","value":"Inspector editor"},
            {"op":"set-prop","id":3,"property":"change-enabled","value":true},
            {"op":"create-node","id":4,"kind":"button"},
            {"op":"set-prop","id":4,"property":"text","value":"Reset width"},
            {"op":"set-prop","id":4,"property":"press-enabled","value":true},
            {"op":"create-node","id":5,"kind":"button"},
            {"op":"set-prop","id":5,"property":"text","value":"Clamp width"},
            {"op":"set-prop","id":5,"property":"press-enabled","value":true},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":4,"index":1},
            {"op":"insert-child","parent":1,"child":5,"index":2},
            {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}).to_string()).unwrap()).unwrap();
        renderer.set_root(1).unwrap();
        renderer.element()
    }

    #[test]
    fn resizable_native_drag_clamps_and_reconciles_source_without_remounting() -> Result<(), String>
    {
        let mut app = Headless::start(EngineConfig {
            viewport: Size::new(px(600.0), px(400.0)),
            ..EngineConfig::new(Root::of::<ResizableProbe>())
        })
        .map_err(|error| error.to_string())?;
        app.wait_for("label:Inspector editor")?;
        let find = |app: &Headless, id: &str| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some(id))
                .ok_or_else(|| format!("missing {id}"))
        };
        let editor = find(&app, "lui-3")?.id;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 200.0);
        app.drag_and_hold("id:lui-2-resize-handle", Point::new(px(120.0), px(0.0)))?;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 260.0);
        app.drop_held()?;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 260.0);
        app.type_text("label:Inspector editor", "retained")?;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 260.0);
        app.press("text:Reset width")?;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 140.0);
        app.drag("id:lui-2-resize-handle", Point::new(px(100.0), px(0.0)))?;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 240.0);
        app.press("text:Clamp width")?;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 150.0);
        app.drag("id:lui-2-resize-handle", Point::new(px(-100.0), px(0.0)))?;
        assert_eq!(find(&app, "lui-2")?.bounds.size.width.0, 120.0);
        assert_eq!(find(&app, "lui-3")?.id, editor);
        assert_eq!(
            app.screen().input_text("label:Inspector editor")?,
            Some("retained")
        );
        Ok(())
    }

    #[component]
    fn DrawerProbe() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        let generation = Rc::new(Cell::new(1_u64));
        let renderer = Renderer::new(move |event, renderer| {
            fixture.events.lock().unwrap().push(event.clone());
            let operations = match event {
                Event::Toggle(2, selected) if fixture.follow.load(Ordering::Relaxed) => {
                    vec![json!({"op":"set-prop","id":2,"property":"selected","value":selected})]
                }
                Event::Press(6) | Event::NativePress(6, _) => {
                    vec![json!({"op":"set-prop","id":2,"property":"selected","value":true})]
                }
                Event::Text(8, text) => {
                    vec![json!({"op":"set-prop","id":8,"property":"text","value":text})]
                }
                Event::Press(12) | Event::NativePress(12, _) => vec![
                    json!({"op":"detach-subtree","id":3}),
                    json!({"op":"create-node","id":10,"kind":"column"}),
                    json!({"op":"create-node","id":11,"kind":"text-field"}),
                    json!({"op":"set-prop","id":11,"property":"accessibility-label","value":"New sidebar editor"}),
                    json!({"op":"insert-child","parent":10,"child":11,"index":0}),
                    json!({"op":"insert-child","parent":2,"child":10,"index":0}),
                ],
                _ => Vec::new(),
            };
            if !operations.is_empty() {
                generation.set(generation.get() + 1);
                renderer
                    .apply(
                        Batch::decode(
                            &json!({"generation": generation.get(), "ops":operations}).to_string(),
                        )
                        .unwrap(),
                    )
                    .unwrap();
            }
        });
        renderer.apply(Batch::decode(&json!({"generation":1,"ops":[
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"set-prop","id":1,"property":"width","value":900},
            {"op":"set-prop","id":1,"property":"height","value":700},
            {"op":"create-node","id":2,"kind":"drawer"},
            {"op":"set-prop","id":2,"property":"text","value":"Navigation"},
            {"op":"set-prop","id":2,"property":"selected","value":true},
            {"op":"set-prop","id":2,"property":"toggle-enabled","value":true},
            {"op":"create-node","id":3,"kind":"column"},
            {"op":"create-node","id":4,"kind":"text-field"},
            {"op":"set-prop","id":4,"property":"accessibility-label","value":"Sidebar editor"},
            {"op":"create-node","id":5,"kind":"column"},
            {"op":"create-node","id":6,"kind":"button"},
            {"op":"set-prop","id":6,"property":"text","value":"Open drawer"},
            {"op":"set-prop","id":6,"property":"press-enabled","value":true},
            {"op":"create-node","id":8,"kind":"text-field"},
            {"op":"set-prop","id":8,"property":"accessibility-label","value":"Main editor"},
            {"op":"set-prop","id":8,"property":"change-enabled","value":true},
            {"op":"create-node","id":12,"kind":"button"},
            {"op":"set-prop","id":12,"property":"text","value":"Replace sidebar"},
            {"op":"set-prop","id":12,"property":"press-enabled","value":true},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":2,"child":5,"index":1},
            {"op":"insert-child","parent":3,"child":4,"index":0},
            {"op":"insert-child","parent":3,"child":12,"index":1},
            {"op":"insert-child","parent":5,"child":6,"index":0},
            {"op":"insert-child","parent":5,"child":8,"index":1}
        ]}).to_string()).unwrap()).unwrap();
        renderer.set_root(1).unwrap();
        renderer.element()
    }

    #[test]
    fn drawer_uses_native_sheet_and_keeps_refused_selected_state() -> Result<(), String> {
        let fixture = Fixture {
            follow: Arc::new(AtomicBool::new(false)),
            events: Arc::new(Mutex::new(Vec::new())),
        };
        let mut app = Headless::start(EngineConfig {
            viewport: Size::new(px(900.0), px(700.0)),
            context: EngineContext::default().with(fixture.clone()),
            ..EngineConfig::new(Root::of::<DrawerProbe>())
        })
        .map_err(|error| error.to_string())?;
        app.wait_for("label:Sidebar editor")?;
        app.press_key("escape")?;
        assert_eq!(
            fixture
                .events
                .lock()
                .unwrap()
                .iter()
                .filter(|event| matches!(event, Event::Toggle(2, false)))
                .count(),
            1
        );
        assert_eq!(app.screen().count("label:Sidebar editor")?, 1);
        fixture.follow.store(true, Ordering::Relaxed);
        app.press_key("escape")?;
        app.wait_for_gone("label:Sidebar editor", std::time::Duration::from_secs(3))?;
        app.type_text("label:Main editor", "kept draft")?;
        let editor = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("lui-8"))
            .ok_or("missing main editor")?
            .id;
        app.press("text:Open drawer")?;
        app.wait_for("label:Sidebar editor")?;
        app.press("text:Replace sidebar")?;
        app.wait_for("label:New sidebar editor")?;
        assert!(
            app.screen()
                .layout_nodes()
                .iter()
                .any(|node| node.id == editor)
        );
        assert_eq!(
            app.screen().input_text("label:Main editor")?,
            Some("kept draft")
        );
        app.press_key("escape")?;
        app.wait_for_gone(
            "label:New sidebar editor",
            std::time::Duration::from_secs(3),
        )?;
        assert!(
            app.screen()
                .layout_nodes()
                .iter()
                .any(|node| node.id == editor)
        );
        assert_eq!(
            app.screen().input_text("label:Main editor")?,
            Some("kept draft")
        );
        Ok(())
    }
}
