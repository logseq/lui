//! Canonical LUI surfaces composed from public NSH surface components.
use super::{Emit, Presentation, emit_flag, enabled, label};
use crate::{render::Event, store::Node, ui};
use nsh_core::{
    AccessibilityActionDef, AccessibilityValue, PropertyValue, StyleKey, StyleValue,
    element::StyleRefinement, prelude::*,
};
use std::sync::Arc;

pub(super) fn supported(kind: &str) -> bool {
    matches!(kind, "drawer" | "resizable" | "split")
}

pub(super) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "drawer" && node.children.len() != 2 {
        return Err("NSH drawer requires its sidebar and main-content children".into());
    }
    if node.kind == "split" {
        if node.children.len() != 2 {
            return Err("NSH split requires exactly two pane children".into());
        }
        if node.number("resize-handle-offset", 0.0).abs() > f32::MAX as f64 {
            return Err("NSH split handle offset exceeds native layout range".into());
        }
        if node.number("resize-duration", 0.0) != 0.0
            || node.props.contains_key("resize-easing")
            || node.props.contains_key("resize-origin")
        {
            return Err("NSH split animated track resizing is not implemented; remove resize-duration/easing/origin".into());
        }
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
        "split" => Some(split(node, emit, presentation)),
        _ => None,
    }
}

// The shared OCaml geometry applies pane limits to user proposals, while a
// controlled source may close below its drag minimum or maximum.
#[derive(Clone, Copy, Debug, PartialEq)]
struct SplitPlan {
    available: f32,
    first: f32,
    gap: f32,
    handle: f32,
    offset: f32,
    pixels: bool,
    rtl: bool,
    minimum: [f32; 2],
    maximum: [f32; 2],
}

impl SplitPlan {
    fn source(node: &Node, span: f32, rtl: bool, panes: [Option<Arc<Node>>; 2]) -> Self {
        let gap = node.number("gap", 9.0) as f32;
        let available = (span - gap).max(0.0);
        let pixels = node.props.contains_key("first-pane-width");
        let first = if pixels {
            node.number("first-pane-width", 0.0) as f32
        } else {
            (node.number("value", 0.5) as f32).clamp(0.0, 1.0) * available
        }
        .clamp(0.0, available);
        let mut minimum = [0.0; 2];
        let mut maximum = [available; 2];
        for (index, pane) in panes.into_iter().enumerate() {
            if let Some(pane) = pane {
                minimum[index] = pane.number("min-width", 0.0) as f32;
                maximum[index] = pane.number("max-width", available as f64) as f32;
            }
        }
        Self {
            available,
            first,
            gap,
            handle: node.number(
                "resize-handle-width",
                if gap > 0.0 { gap as f64 } else { 3.0 },
            ) as f32,
            offset: node.number("resize-handle-offset", 0.0) as f32,
            pixels,
            rtl,
            minimum,
            maximum,
        }
    }

    fn pane(self, index: usize) -> f32 {
        if index == 0 {
            self.first
        } else {
            self.available - self.first
        }
    }

    fn handle_start(self) -> f32 {
        let logical = self.first + self.gap / 2.0 + self.offset;
        (if self.rtl {
            self.available + self.gap - logical
        } else {
            logical
        }) - self.handle / 2.0
    }

    fn proposal(self, first: f32) -> f64 {
        let [first_min, second_min] = self.minimum;
        let [first_max, second_max] = self.maximum;
        let fraction = if self.available <= 0.0 {
            0.5
        } else if first_min + second_min > self.available {
            first_min / (first_min + second_min)
        } else if first_max + second_max < self.available {
            let sum = first_max + second_max;
            if sum == 0.0 { 0.5 } else { first_max / sum }
        } else {
            let low = first_min.max(self.available - second_max);
            let high = first_max.min(self.available - second_min);
            // Incompatible per-pane ranges retain the shared geometry's
            // lower-bound-first ordering rather than panicking in clamp().
            let upper_bounded = first.min(high);
            upper_bounded.max(low) / self.available
        };
        if self.pixels {
            (fraction * self.available) as f64
        } else {
            fraction as f64
        }
    }
}

fn split(node: Signal<Arc<Node>>, emit: Emit, presentation: Presentation) -> AnyElement {
    let children = presentation
        .children
        .as_ref()
        .expect("split child renderer")
        .clone();
    let identities = children.identities;
    let lookup = children.lookup.clone();
    let span = signal(0.0_f32);
    let plan = computed(move || {
        let panes = identities.with(|ids| {
            [0, 1].map(|index| {
                ids.get(index)
                    .and_then(|id| lookup(*id))
                    .map(|node| node.get())
            })
        });
        SplitPlan::source(
            &node.get(),
            span.get(),
            nsh_core::element::layout_rtl(),
            panes,
        )
    });
    let active = move || {
        node.get().boolean("change-enabled", false)
            && enabled(node)
            && plan.get().handle > 0.0
            && plan.get().available > 0.0
    };
    let id = node.get_untracked().id;
    let request: std::rc::Rc<dyn Fn(f32)> = std::rc::Rc::new(move |first| {
        if !active() {
            return;
        }
        let current = plan.get_untracked();
        let proposal = current.proposal(first);
        let source = if current.pixels {
            current.first as f64
        } else {
            (current.first / current.available) as f64
        };
        if (proposal - source).abs() > 0.000_001 {
            emit_flag(node, "change-enabled", &emit, Event::Value(id, proposal));
        }
    });
    let divider = element_ref();
    let focused = signal(false);
    divider.on_focus_in(move || focused.set(true));
    divider.on_focus_out(move || focused.set(false));
    let keys = request.clone();
    effect(move || {
        if !focused.get() || !active() {
            return;
        }
        for (key, share) in [
            ("left", -0.05),
            ("right", 0.05),
            ("home", -1.0),
            ("end", 1.0),
        ] {
            let request = keys.clone();
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::NotEditing,
                    repeat: true,
                    for_focus: true,
                    ..Default::default()
                },
                move |_| {
                    let current = plan.get_untracked();
                    let direction = if current.rtl && matches!(key, "left" | "right") {
                        -1.0
                    } else {
                        1.0
                    };
                    request(current.first + current.available * share * direction);
                },
            );
        }
    });
    let drag_start = stored(0.0_f32);
    let dragged = request.clone();
    let divider_label = move || {
        let name = label(node);
        if name.is_empty() {
            "Split divider".to_owned()
        } else {
            format!("{name} divider")
        }
    };
    let handle = nsh_base::ResizeHandle::element(nsh_base::ResizeHandleProps {
        edge: Some(nsh_base::HandleEdge::Leading).into(),
        disabled: Prop::bind(move || !active()),
        accessibility_label: Prop::bind(move || Some(divider_label().into())),
        ..Default::default()
    })
    .test_id(&format!("lui-{id}-split-handle"))
    .state_inline_style(move || {
        let width = plan.get().handle;
        nsh_core::element::Style::default().with(
            StyleKey::Width,
            StyleKey::Width
                .parse_value(StyleValue::Number(width))
                .expect("validated native split handle width"),
        )
    })
    .on_event(move |event: &nsh_base::ResizeHandleEvent| match event {
        nsh_base::ResizeHandleEvent::DragStart if active() => {
            drag_start.replace(plan.get_untracked().first);
            divider.focus();
        }
        nsh_base::ResizeHandleEvent::DragMove(offset) if active() => {
            let delta = if plan.get_untracked().rtl {
                -offset.0
            } else {
                offset.0
            };
            dragged(drag_start.get() + delta);
        }
        _ => {}
    });
    let adjusted = request;
    // Native ResizeHandle owns pointer capture. This semantic divider adds the
    // public keyboard/AT bindings its typed component props do not expose.
    let divider = view()
        .element_ref(&divider)
        .test_id(&format!("lui-{id}-split-divider"))
        .absolute()
        .top(px(0.0))
        .bottom(px(0.0))
        .role(AccessibilityRole::Adjustable)
        .label(divider_label)
        .focusable(active)
        .style_when(move || plan.get().handle == 0.0, |style| style.hidden())
        .style_with(move |style| {
            let current = plan.get();
            style.left(px(current.handle_start())).w(px(current.handle))
        })
        .accessibility_value(move || {
            let current = plan.get();
            Some(AccessibilityValue {
                min: Some(0.0),
                max: Some(if current.pixels {
                    current.available
                } else {
                    1.0
                }),
                now: Some(if current.pixels {
                    current.first
                } else {
                    current.first / current.available.max(1.0)
                }),
                ..Default::default()
            })
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
            let current = plan.get_untracked();
            let direction = match action {
                "increment" => 0.05,
                "decrement" => -0.05,
                _ => return,
            };
            adjusted(current.first + current.available * direction);
        })
        .child(handle);
    let render = children.render;
    let pane_lookup = children.lookup;
    let panes = view()
        .relative()
        .min_w(px(0.0))
        .min_h(px(0.0))
        .w_full()
        .flex_1()
        .flex_row()
        .gap(move || px(plan.get().gap))
        .on_layout(move |bounds: &Bounds<Points>| {
            let width = bounds.size.width.0;
            if span.get_untracked() != width {
                span.set(width);
            }
        })
        .child(each(
            identities,
            |identity| *identity,
            move |identity, index| {
                let pane = pane_lookup(identity.get_untracked());
                view()
                    .min_w(px(0.0))
                    .min_h(px(0.0))
                    .flex_shrink_0()
                    .overflow_hidden()
                    .test_id(&format!(
                        "lui-{id}-split-pane-{}",
                        identity.get_untracked().0
                    ))
                    .style_with(move |style| style.w(px(plan.get().pane(index.get()))))
                    .state_inline_style(move || {
                        let clipped =
                            pane.is_none_or(|pane| pane.get().string("overflow") != "visible");
                        nsh_core::element::Style::default()
                            .with(StyleKey::Overflow, PropertyValue::Bool(clipped))
                    })
                    .child(render(identity.get_untracked()))
            },
        ))
        .child(divider);
    presentation.host(view().relative().flex_col().child(panes))
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

    #[derive(Clone)]
    struct SplitFixture {
        pixels: bool,
        follow: Arc<AtomicBool>,
        proposals: Arc<Mutex<Vec<f64>>>,
    }

    fn split_batch(generation: u64, ops: serde_json::Value) -> Batch {
        Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
    }

    #[component]
    fn SplitProbe() -> impl IntoElement {
        let fixture = engine_context::<SplitFixture>().unwrap();
        let generation = Rc::new(Cell::new(1_u64));
        let seen = fixture.proposals.clone();
        let follow = fixture.follow.clone();
        let pixels = fixture.pixels;
        let next = generation.clone();
        let renderer = Renderer::new(move |event, renderer| {
            let ops = match event {
                Event::Value(2, value) => {
                    seen.lock().unwrap().push(value);
                    if follow.load(Ordering::Relaxed) {
                        vec![
                            json!({"op":"set-prop","id":2,"property":if pixels {"first-pane-width"} else {"value"},"value":value}),
                        ]
                    } else {
                        Vec::new()
                    }
                }
                Event::Text(id @ (3 | 4), text) => {
                    vec![json!({"op":"set-prop","id":id,"property":"text","value":text})]
                }
                _ => Vec::new(),
            };
            if !ops.is_empty() {
                let generation = next.get() + 1;
                renderer.apply(split_batch(generation, json!(ops))).unwrap();
                next.set(generation);
            }
        });
        let mut ops = vec![
            json!({"op":"create-node","id":1,"kind":"column"}),
            json!({"op":"set-prop","id":1,"property":"width","value":609}),
            json!({"op":"create-node","id":2,"kind":"split"}),
            json!({"op":"set-prop","id":2,"property":"width","value":609}),
            json!({"op":"set-prop","id":2,"property":"height","value":120}),
            json!({"op":"set-prop","id":2,"property":"change-enabled","value":true}),
            json!({"op":"set-prop","id":2,"property":"resize-handle-width","value":20}),
            json!({"op":"set-prop","id":2,"property":"resize-handle-offset","value":7.0}),
            json!({"op":"create-node","id":3,"kind":"text-field"}),
            json!({"op":"set-prop","id":3,"property":"text","value":"First"}),
            json!({"op":"set-prop","id":3,"property":"change-enabled","value":true}),
            json!({"op":"set-prop","id":3,"property":"min-width","value":100}),
            json!({"op":"set-prop","id":3,"property":"max-width","value":400}),
            json!({"op":"create-node","id":4,"kind":"text-field"}),
            json!({"op":"set-prop","id":4,"property":"text","value":"Second"}),
            json!({"op":"set-prop","id":4,"property":"change-enabled","value":true}),
            json!({"op":"set-prop","id":4,"property":"min-width","value":150}),
            json!({"op":"set-prop","id":4,"property":"max-width","value":450}),
            json!({"op":"insert-child","parent":1,"child":2,"index":0}),
            json!({"op":"insert-child","parent":2,"child":3,"index":0}),
            json!({"op":"insert-child","parent":2,"child":4,"index":1}),
        ];
        if pixels {
            ops.push(json!({"op":"set-prop","id":2,"property":"first-pane-width","value":240.0}));
        }
        renderer.apply(split_batch(1, json!(ops))).unwrap();
        renderer.set_root(1).unwrap();
        for key in ["f3", "f4", "f5", "f6", "f7", "f8"] {
            let renderer = renderer.clone();
            let generation = generation.clone();
            on_key_with(
                key,
                KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    let ops = match key {
                        "f3" => {
                            json!([{"op":"set-prop","id":2,"property":if pixels {"first-pane-width"} else {"value"},"value":if pixels {180.0} else {0.25}}])
                        }
                        "f4" => json!([{"op":"insert-child","parent":2,"child":4,"index":0}]),
                        "f5" => json!([{"op":"set-prop","id":2,"property":"width","value":309}]),
                        "f6" => {
                            json!([{"op":"set-prop","id":2,"property":"change-enabled","value":false}])
                        }
                        "f7" => {
                            json!([{"op":"set-prop","id":2,"property":"resize-handle-width","value":0}])
                        }
                        "f8" => {
                            let bad = json!([
                                {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                                {"op":"set-prop","id":2,"property":"resize-duration","value":120}
                            ]);
                            assert!(
                                renderer
                                    .apply(split_batch(generation.get() + 1, bad))
                                    .is_err()
                            );
                            json!([{"op":"set-prop","id":2,"property":"resize-handle-offset","value":0.0}])
                        }
                        _ => unreachable!(),
                    };
                    let next = generation.get() + 1;
                    renderer.apply(split_batch(next, ops)).unwrap();
                    generation.set(next);
                },
            );
        }
        renderer.element()
    }

    fn split_app(pixels: bool, rtl: bool, follow: bool) -> (Headless, SplitFixture) {
        let fixture = SplitFixture {
            pixels,
            follow: Arc::new(AtomicBool::new(follow)),
            proposals: Arc::new(Mutex::new(Vec::new())),
        };
        let mut config = EngineConfig {
            viewport: Size::new(px(800.0), px(400.0)),
            context: EngineContext::default().with(fixture.clone()),
            ..EngineConfig::new(Root::of::<SplitProbe>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.rtl = rtl;
        let mut app = Headless::start(config).unwrap();
        app.wait_for("id:lui-3").unwrap();
        (app, fixture)
    }

    fn split_node(app: &Headless, test_id: &str) -> nsh_testing::LayoutNode {
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some(test_id))
            .unwrap()
    }

    #[test]
    fn split_native_drag_is_controlled_and_respects_both_pane_bounds() {
        let (mut app, fixture) = split_app(false, false, false);
        let first = split_node(&app, "lui-3").id;
        let second = split_node(&app, "lui-4").id;
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(300.0)
        );
        app.drag("id:lui-2-split-handle", Point::new(px(100.0), px(0.0)))
            .unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(300.0),
            "refusal must keep accepted model geometry"
        );
        assert!(*fixture.proposals.lock().unwrap().last().unwrap() > 0.5);
        fixture.follow.store(true, Ordering::Relaxed);
        app.drag("id:lui-2-split-handle", Point::new(px(300.0), px(0.0)))
            .unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(400.0)
        );
        assert!((fixture.proposals.lock().unwrap().last().unwrap() - 2.0 / 3.0).abs() < 0.000_01);
        assert_eq!(split_node(&app, "lui-3").id, first);
        assert_eq!(split_node(&app, "lui-4").id, second);
        app.press_key("f6").unwrap();
        let before = fixture.proposals.lock().unwrap().len();
        app.drag("id:lui-2-split-handle", Point::new(px(-100.0), px(0.0)))
            .unwrap();
        assert_eq!(fixture.proposals.lock().unwrap().len(), before);
    }

    #[test]
    fn split_pixel_sources_resize_independently_and_reorder_keeps_editor_focus_and_draft() {
        let (mut app, fixture) = split_app(true, false, true);
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(240.0)
        );
        app.type_text("id:lui-3", " draft").unwrap();
        let first = split_node(&app, "lui-3").id;
        let second = split_node(&app, "lui-4").id;
        app.press_key("f3").unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(180.0)
        );
        assert!(
            fixture.proposals.lock().unwrap().is_empty(),
            "programmatic resize is not a user event"
        );
        app.press_key("f5").unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(180.0)
        );
        app.press_key("f4").unwrap();
        assert_eq!(split_node(&app, "lui-4").id, second);
        assert_eq!(split_node(&app, "lui-3").id, first);
        assert_eq!(app.screen().focused(), Some(first));
        assert_eq!(
            app.screen().input_text("id:lui-3").unwrap(),
            Some("First draft")
        );
        assert_eq!(
            split_node(&app, "lui-2-split-pane-4").bounds.size.width,
            px(180.0)
        );
    }

    #[test]
    fn split_rtl_handle_geometry_delta_and_zero_width_input_follow_logical_order() {
        let (mut app, fixture) = split_app(false, true, true);
        let first = split_node(&app, "lui-2-split-pane-3");
        let second = split_node(&app, "lui-2-split-pane-4");
        let handle = split_node(&app, "lui-2-split-handle");
        assert!(first.bounds.origin.x > second.bounds.origin.x);
        assert_eq!(handle.bounds.size.width, px(20.0));
        assert!((handle.bounds.center().x.0 - (first.bounds.origin.x.0 - 4.5 - 7.0)).abs() <= 1.0);
        app.drag("id:lui-2-split-handle", Point::new(px(-60.0), px(0.0)))
            .unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(360.0)
        );
        assert!((fixture.proposals.lock().unwrap().last().unwrap() - 0.6).abs() < 0.000_01);
        app.press_key("f7").unwrap();
        assert_eq!(app.screen().count("id:lui-2-split-divider").unwrap(), 0);
        let before = fixture.proposals.lock().unwrap().len();
        app.press_key("right").unwrap();
        assert_eq!(fixture.proposals.lock().unwrap().len(), before);
        app.press_key("f3").unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(150.0)
        );
    }

    #[test]
    fn split_native_divider_keyboard_is_scoped_and_animation_options_reject_atomically() {
        let (mut app, fixture) = split_app(false, false, true);
        app.drag("id:lui-2-split-handle", Point::default()).unwrap();
        app.press_key("right").unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(330.0)
        );
        app.press_key("home").unwrap();
        assert_eq!(
            split_node(&app, "lui-2-split-pane-3").bounds.size.width,
            px(150.0)
        );
        app.type_text("id:lui-3", " editing").unwrap();
        let before = fixture.proposals.lock().unwrap().len();
        app.press_key("right").unwrap();
        assert_eq!(
            fixture.proposals.lock().unwrap().len(),
            before,
            "input navigation must not resize the split"
        );
        app.press_key("f8").unwrap();
        assert_eq!(
            app.screen().input_text("id:lui-3").unwrap(),
            Some("First editing")
        );
    }

    #[test]
    fn split_geometry_matches_shared_infeasible_limits_and_programmatic_zero() {
        let mut node = Node {
            kind: "split".into(),
            ..Default::default()
        };
        let first = Node {
            props: serde_json::from_value(json!({"min-width":100,"max-width":400})).unwrap(),
            ..Default::default()
        };
        let second = Node {
            props: serde_json::from_value(json!({"min-width":150,"max-width":700})).unwrap(),
            ..Default::default()
        };
        let mut plan = SplitPlan::source(
            &node,
            1009.0,
            false,
            [Some(Arc::new(first)), Some(Arc::new(second))],
        );
        assert!((plan.proposal(10.0) - 0.3).abs() < 0.000_01);
        assert!((plan.proposal(900.0) - 0.4).abs() < 0.000_01);
        plan.maximum = [200.0, 300.0];
        assert!((plan.proposal(900.0) - 0.4).abs() < 0.000_01);
        plan.minimum = [600.0, 900.0];
        assert!((plan.proposal(900.0) - 0.4).abs() < 0.000_01);
        node.props = serde_json::from_value(json!({"first-pane-width":0.0})).unwrap();
        let plan = SplitPlan::source(&node, 609.0, false, [None, None]);
        assert_eq!(plan.first, 0.0);
        assert_eq!(plan.handle, 9.0);
        assert_eq!(plan.offset, 0.0);
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
