//! Feasibility probe: public cell lifetimes expose bounded demand and retained
//! distant editors. This is NSH evidence, not yet LUI sparse-wire qualification.
use nsh_core::platform::{Idiom, Os};
use nsh_core::{
    element::{engine_context, input},
    prelude::*,
};
use nsh_engine::{EngineConfig, EngineContext, Environment, Root};
use nsh_testing::Headless;
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
    time::Duration,
};

#[derive(Default)]
struct Probe {
    cells: BTreeMap<usize, usize>,
    made: usize,
    dropped: usize,
}
struct Context {
    count: usize,
    probe: Arc<Mutex<Probe>>,
}

#[component]
fn PublicList() -> impl IntoElement {
    let context = engine_context::<Context>().expect("probe context");
    let data = signal((0..context.count).collect::<Vec<_>>());
    let edited = signal("Row 2".to_owned());
    let count = context.count;
    let list = element_ref();
    let showing = signal(true);
    on_key_with(
        "f8",
        nsh_core::element::KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| showing.set(false),
    );
    on_key_with(
        "f7",
        nsh_core::element::KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| list.scroll_to_end(false),
    );
    on_key_with(
        "f6",
        nsh_core::element::KeyOptions {
            when: nsh_core::keymap::When::Always,
            ..Default::default()
        },
        move |_| data.update(|rows| rows.swap(2, count - 1)),
    );
    view()
        .flex_1()
        .child(text(move || {
            format!(
                "Row2 at {}",
                data.with(|rows| rows.iter().position(|id| *id == 2).unwrap())
            )
        }))
        .child(
            nsh_base::Button::element(Default::default())
                .test_id("reorder")
                .on_event(move |event: &nsh_base::ButtonEvent| {
                    if matches!(event, nsh_base::ButtonEvent::Press) {
                        data.update(|rows| rows.swap(2, count - 1));
                    }
                })
                .child(text("Reorder")),
        )
        .child(when(
            move || showing.get(),
            move || {
                let context = context.clone();
                virtual_list(
                    move || data.with(Vec::len),
                    move |position| {
                        let probe = context.probe.clone();
                        let slot = {
                            let mut probe = probe.lock().unwrap();
                            let slot = probe.made;
                            probe.made += 1;
                            slot
                        };
                        let demand = probe.clone();
                        effect(move || {
                            let index = position.index();
                            let count = position.count();
                            let mut probe = demand.lock().unwrap();
                            if index < count {
                                probe.cells.insert(slot, index);
                            } else {
                                probe.cells.remove(&slot);
                            }
                        });
                        cleanup(move || {
                            let mut probe = probe.lock().unwrap();
                            probe.cells.remove(&slot);
                            probe.dropped += 1;
                        });
                        input()
                            .test_id(&format!("cell-{slot}"))
                            .h(px(32.0))
                            .label(move || {
                                data.with(|rows| {
                                    rows.get(position.index())
                                        .map(|id| format!("Row {id}"))
                                        .unwrap_or_default()
                                })
                            })
                            .value(move || {
                                data.with(|rows| match rows.get(position.index()) {
                                    Some(2) => edited.get(),
                                    Some(id) => format!("Row {id}"),
                                    None => String::new(),
                                })
                            })
                            .on_change(move |text: &str| {
                                if data.with_untracked(|rows| rows.get(position.index()).copied())
                                    == Some(2)
                                {
                                    edited.set(text.to_owned());
                                }
                            })
                    },
                )
                .element_ref(&list)
                .test_id("list")
                .h(px(320.0))
                .estimated_item_size(px(32.0))
                .keys(move || data.get())
            },
        ))
}

fn run_case(count: usize, reorder: bool) -> Result<(), String> {
    let probe = Arc::new(Mutex::new(Probe::default()));
    let mut app = Headless::start(EngineConfig {
        trace: true,
        environment: Environment {
            os: Os::Linux,
            idiom: Idiom::Desktop,
            ..Default::default()
        },
        context: EngineContext::default().with(Context {
            count,
            probe: probe.clone(),
        }),
        ..EngineConfig::new(Root::of::<PublicList>())
    })
    .unwrap();
    app.wait_for("label:Row 2")?;
    app.type_text("label:Row 2", "!")?;
    assert_eq!(app.screen().input_text("label:Row 2")?, Some("Row 2!"));
    let slot = *probe
        .lock()
        .unwrap()
        .cells
        .iter()
        .find(|(_, index)| **index == 2)
        .ok_or("no public demand for row 2")?
        .0;
    let test_id = format!("cell-{slot}");
    let editor = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(test_id.as_str()))
        .ok_or("missing editor identity")?
        .id;
    app.press_key("f7")?;
    app.wait_for(&format!("label:Row {}", count - 1))?;
    {
        let state = probe.lock().unwrap();
        assert_eq!(
            state.cells.get(&slot),
            Some(&2),
            "focused cell was recycled"
        );
        assert!(
            state.cells.values().any(|index| *index > count - 20),
            "public demand missed distant window"
        );
        assert!(
            state.cells.len() < 300,
            "cell demand grew with source length: {}",
            state.cells.len()
        );
    }
    {
        let state = probe.lock().unwrap();
        eprintln!(
            "source={count}, live cell demand={}, constructed cells={}",
            state.cells.len(),
            state.made
        );
    }
    if reorder {
        app.press_key("f6")?;
        app.wait_for(&format!("text:Row2 at {}", count - 1))?;
        app.wait_until(
            "retained row follows reorder",
            Duration::from_secs(3),
            |_| probe.lock().unwrap().cells.get(&slot) == Some(&(count - 1)),
        )?;
        assert_eq!(app.screen().input_text("label:Row 2")?, Some("Row 2!"));
        assert!(
            app.screen()
                .layout_nodes()
                .iter()
                .any(|node| node.id == editor),
            "reorder recreated the retained native editor"
        );
    }
    app.press_key("f8")?;
    app.wait_until(
        "cell owners disposed on unmount",
        Duration::from_secs(3),
        |_| probe.lock().unwrap().cells.is_empty(),
    )?;
    drop(app);
    let state = probe.lock().unwrap();
    assert!(state.cells.is_empty(), "cell demand outlived the engine");
    assert_eq!(
        state.made, state.dropped,
        "cell owner cleanup was unbalanced"
    );
    Ok(())
}

#[test]
fn public_cells_are_bounded_keep_distant_focus_and_dispose() -> Result<(), String> {
    for count in [1_000, 100_000] {
        run_case(count, false)?;
    }
    Ok(())
}

#[test]
fn public_keys_preserve_the_focused_editor_across_source_reorder() -> Result<(), String> {
    let errors: Vec<_> = [1_000, 100_000]
        .into_iter()
        .filter_map(|count| {
            run_case(count, true)
                .err()
                .map(|error| format!("source={count}: {error}"))
        })
        .collect();
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("\n"))
    }
}
