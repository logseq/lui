//! Ordered retained alternatives measured by the public native layout engine.
use super::{ChildIdentity, Presentation};
use crate::store::Node;
use nsh_core::{
    StyleDecl, StyleKey, StyleValue,
    element::Style,
    geometry::{Bounds, Points, Size},
    prelude::*,
};
use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

fn vertical(node: &Node) -> bool {
    node.string("orientation") == "vertical"
}

fn choose(
    identities: &[ChildIdentity],
    measured: &HashMap<ChildIdentity, Size<Points>>,
    available: Option<Size<Points>>,
    vertical: bool,
) -> Option<ChildIdentity> {
    let available = available?;
    let (&last, candidates) = identities.split_last()?;
    let along = |size: Size<Points>| if vertical { size.height } else { size.width };
    for identity in candidates {
        // Do not briefly appear a later candidate before its predecessors have
        // received their first native layout. A zero-sized candidate is valid.
        let size = measured.get(identity)?;
        if along(*size).0 <= along(available).0 + 0.5 {
            return Some(*identity);
        }
    }
    Some(last)
}

fn intrinsic(vertical: bool) -> Style {
    let key = if vertical {
        StyleKey::Height
    } else {
        StyleKey::Width
    };
    Style::from_decls([StyleDecl::Set(
        key,
        key.parse_value(StyleValue::Str("max-content"))
            .expect("public native intrinsic dimension"),
    )])
}

pub(super) fn element(node: Signal<Arc<Node>>, presentation: Presentation) -> AnyElement {
    let children = presentation
        .children
        .clone()
        .expect("retained fit candidates");
    let identities = children.identities;
    let measured = signal(HashMap::<ChildIdentity, Size<Points>>::new());
    let available = signal(None::<Size<Points>>);
    // Membership changes prune once per direct list update, rather than each
    // disposed candidate mutating a shared registry during owner teardown.
    effect(move || {
        let active: HashSet<_> = identities.get().into_iter().collect();
        if measured.with_untracked(|sizes| sizes.keys().any(|id| !active.contains(id))) {
            measured.update(|sizes| sizes.retain(|id, _| active.contains(id)));
        }
    });
    let selected = computed(move || {
        identities.with(|identities| {
            measured.with(|measured| {
                choose(identities, measured, available.get(), vertical(&node.get()))
            })
        })
    });
    let render = children.render;
    let candidates = each(
        identities,
        |identity| *identity,
        move |identity, index| {
            let identity = identity.get_untracked();
            crate::events::scope_visibility(move || selected.get() == Some(identity));
            view()
                .flex_none()
                .min_w_0()
                .min_h_0()
                .col_start(1)
                .row_start(1)
                .style_with(move |s| {
                    let vertical = vertical(&node.get());
                    let last = index.get() + 1 == identities.with(Vec::len);
                    let s = if vertical { s.w_full() } else { s };
                    let s = if last {
                        if vertical { s.h_full() } else { s.w_full() }
                    } else {
                        s
                    };
                    if selected.get() == Some(identity) {
                        s
                    } else {
                        // Intrinsic measurement never changes the candidate's
                        // proposal when it becomes selected. Invisible native
                        // subtrees retain state but take no pointer or focus.
                        s.absolute().top(px(0.0)).left(px(0.0)).invisible()
                    }
                })
                .state_inline_style(move || {
                    if index.get() + 1 == identities.with(Vec::len) {
                        Style::default()
                    } else {
                        intrinsic(vertical(&node.get()))
                    }
                })
                .on_layout(move |bounds: &Bounds<Points>| {
                    if measured.with_untracked(|sizes| sizes.get(&identity) != Some(&bounds.size)) {
                        measured.update(|sizes| {
                            sizes.insert(identity, bounds.size);
                        });
                    }
                })
                .child(render(identity))
        },
    );
    presentation.host(
        view().min_w_0().min_h_0().child(
            view()
                .flex_1()
                .self_stretch()
                .min_w_0()
                .min_h_0()
                .grid()
                .grid_cols(1)
                .grid_rows(1)
                .on_layout(move |bounds: &Bounds<Points>| {
                    if available.get_untracked() != Some(bounds.size) {
                        available.set(Some(bounds.size));
                    }
                })
                .child(candidates),
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        render::{Event, Renderer},
        wire::Batch,
    };
    use nsh_core::geometry::size;
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::Headless;
    use serde_json::{Value, json};
    use std::{cell::Cell, rc::Rc, sync::Mutex};

    #[test]
    fn ordered_choice_waits_for_unknown_predecessors_and_uses_last_as_fallback() {
        let first = (1, 1);
        let last = (2, 2);
        let mut measured = HashMap::new();
        let available = Some(size(px(100.0), px(50.0)));
        assert_eq!(choose(&[first, last], &measured, available, false), None);
        measured.insert(first, size(px(150.0), px(30.0)));
        assert_eq!(
            choose(&[first, last], &measured, available, false),
            Some(last)
        );
        assert_eq!(
            choose(&[first, last], &measured, available, true),
            Some(first)
        );
        measured.insert(first, Size::default());
        assert_eq!(
            choose(&[first, last], &measured, available, false),
            Some(first)
        );
        assert_eq!(choose(&[], &measured, available, false), None);
    }

    struct Fixture {
        vertical: bool,
        events: Arc<Mutex<Vec<Event>>>,
    }
    fn apply(renderer: &Renderer, generation: &Cell<u64>, ops: Value) {
        let next = generation.get() + 1;
        renderer
            .apply(Batch::decode(&json!({"generation":next,"ops":ops}).to_string()).unwrap())
            .unwrap();
        generation.set(next);
    }
    #[component]
    fn FitProbe() -> impl IntoElement {
        let fixture = engine_context::<Fixture>().unwrap();
        let events = fixture.events.clone();
        let renderer = Renderer::new(move |event, _| events.lock().unwrap().push(event));
        let generation = Rc::new(Cell::new(0));
        let mut ops = vec![
            json!({"op":"create-node","id":1,"kind":"column"}),
            json!({"op":"create-node","id":2,"kind":"edge-inset"}),
            json!({"op":"set-prop","id":2,"property":"edge","value":"top"}),
            json!({"op":"set-prop","id":2,"property":"width","value":420}),
            json!({"op":"set-prop","id":2,"property":"height","value":300}),
            json!({"op":"insert-child","parent":1,"child":2,"index":0}),
            json!({"op":"create-node","id":3,"kind":"text-field"}),
            json!({"op":"set-prop","id":3,"property":"accessibility-label","value":"Main draft"}),
            json!({"op":"insert-child","parent":2,"child":3,"index":0}),
            json!({"op":"create-node","id":10,"kind":"view-that-fits"}),
            json!({"op":"set-prop","id":10,"property":"width","value":200}),
            json!({"op":"set-prop","id":10,"property":"height","value":100}),
            json!({"op":"insert-child","parent":2,"child":10,"index":1}),
        ];
        if fixture.vertical {
            ops.push(json!({"op":"set-prop","id":10,"property":"orientation","value":"vertical"}));
        }
        for (id, width, height, label) in [
            (11, 300, 150, "Preferred draft"),
            (12, 80, 30, "Fallback draft"),
        ] {
            ops.extend([
                json!({"op":"create-node","id":id,"kind":"column"}),
                json!({"op":"set-prop","id":id,"property":"width","value":width}),
                json!({"op":"set-prop","id":id,"property":"height","value":height}),
                json!({"op":"insert-child","parent":10,"child":id,"index":id-11}),
                json!({"op":"create-node","id":id+10,"kind":"text-field"}),
                json!({"op":"set-prop","id":id+10,"property":"accessibility-label","value":label}),
                json!({"op":"set-prop","id":id+10,"property":"appear-enabled","value":true}),
                json!({"op":"insert-child","parent":id,"child":id+10,"index":0}),
            ]);
        }
        apply(&renderer, &generation, json!(ops));
        renderer.set_root(1).unwrap();
        for (key, ops) in [
            (
                "f5",
                json!([{"op":"set-prop","id":10,"property":"width","value":400},{"op":"set-prop","id":10,"property":"height","value":200}]),
            ),
            (
                "f6",
                json!([{"op":"set-prop","id":10,"property":"width","value":200},{"op":"set-prop","id":10,"property":"height","value":100}]),
            ),
            (
                "f7",
                json!([{"op":"move-child","parent":10,"child":12,"index":0}]),
            ),
            (
                "f8",
                json!([{"op":"set-prop","id":2,"property":"visible","value":false}]),
            ),
            (
                "f9",
                json!([{"op":"set-prop","id":2,"property":"visible","value":true}]),
            ),
            (
                "f4",
                json!([{"op":"set-prop","id":11,"property":"width","value":120},{"op":"set-prop","id":11,"property":"height","value":60}]),
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
        renderer.element()
    }
    fn start(vertical: bool) -> (Headless, Arc<Mutex<Vec<Event>>>) {
        let events = Arc::new(Mutex::new(Vec::new()));
        let mut config = EngineConfig {
            context: EngineContext::default().with(Fixture {
                vertical,
                events: events.clone(),
            }),
            ..EngineConfig::new(Root::of::<FitProbe>())
        };
        config.environment.os = nsh_core::platform::Os::MacOs;
        config.environment.reduce_motion = true;
        let mut app = Headless::start(config).unwrap();
        app.first_render().unwrap();
        app.wait_for("label:Fallback draft").unwrap();
        (app, events)
    }
    fn id(app: &Headless, name: &str) -> nsh_core::NodeId {
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some(name))
            .unwrap()
            .id
    }
    #[test]
    fn both_axes_switch_without_remounting_or_losing_independent_drafts() {
        for vertical in [false, true] {
            let (mut app, events) = start(vertical);
            let fallback = id(&app, "lui-22");
            assert_eq!(app.screen().count("label:Preferred draft").unwrap(), 0);
            assert_eq!(*events.lock().unwrap(), [Event::Appear(22)]);
            app.type_text("label:Fallback draft", "saved fallback")
                .unwrap();
            app.press_key("f5").unwrap();
            app.wait_for("label:Preferred draft").unwrap();
            let preferred = id(&app, "lui-21");
            app.type_text("label:Preferred draft", "saved preferred")
                .unwrap();
            app.press_key("f6").unwrap();
            app.wait_for("label:Fallback draft").unwrap();
            assert_eq!(id(&app, "lui-22"), fallback);
            assert_eq!(
                app.screen().input_text("label:Fallback draft").unwrap(),
                Some("saved fallback")
            );
            app.press_key("f5").unwrap();
            app.wait_for("label:Preferred draft").unwrap();
            assert_eq!(id(&app, "lui-21"), preferred);
            assert_eq!(
                app.screen().input_text("label:Preferred draft").unwrap(),
                Some("saved preferred")
            );
            assert_eq!(
                *events.lock().unwrap(),
                [
                    Event::Appear(22),
                    Event::Appear(21),
                    Event::Appear(22),
                    Event::Appear(21)
                ]
            );
        }
    }
    #[test]
    fn keyboard_traversal_excludes_unselected_candidates() {
        let (mut app, _) = start(false);
        app.type_text("label:Main draft", "outside").unwrap();
        app.press_key("tab").unwrap();
        app.press_key("x").unwrap();
        assert_eq!(
            app.screen().input_text("label:Fallback draft").unwrap(),
            Some("x")
        );
        assert_eq!(
            app.screen().input_text("label:Main draft").unwrap(),
            Some("outside")
        );
    }
    #[test]
    fn live_candidate_geometry_order_and_outer_visibility_use_retained_nodes() {
        let (mut app, events) = start(false);
        app.press_key("f4").unwrap();
        app.wait_for("label:Preferred draft").unwrap();
        let preferred = id(&app, "lui-21");
        let fallback = id(&app, "lui-22");
        app.press_key("f7").unwrap();
        app.wait_for("label:Fallback draft").unwrap();
        assert_eq!(id(&app, "lui-22"), fallback);
        events.lock().unwrap().clear();
        app.press_key("f8").unwrap();
        assert_eq!(app.screen().count("label:Fallback draft").unwrap(), 0);
        assert_eq!(app.screen().count("label:Main draft").unwrap(), 1);
        app.press_key("f9").unwrap();
        app.wait_for("label:Fallback draft").unwrap();
        assert_eq!(id(&app, "lui-22"), fallback);
        assert_eq!(id(&app, "lui-21"), preferred);
        assert_eq!(*events.lock().unwrap(), [Event::Appear(22)]);
    }
}
