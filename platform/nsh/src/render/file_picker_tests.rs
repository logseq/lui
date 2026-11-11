//! File-dialog requests and answers through NSH's public native-service seam.
use super::*;
use nsh_core::file_dialog::FileRequest;
use nsh_engine::{EngineConfig, EngineContext, Root};
use nsh_testing::Headless;
use serde_json::json;
use std::{path::PathBuf, sync::Mutex};

struct PickerProbe(Arc<Mutex<Vec<Event>>>);

fn patch(generation: u64, ops: Value) -> Batch {
    Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
}

fn publish(renderer: &Renderer, ops: Value) {
    let generation = renderer.0.borrow().store.generation + 1;
    renderer.apply(patch(generation, ops)).unwrap();
}

#[component]
fn FileSelection() -> impl IntoElement {
    let observed = engine_context::<PickerProbe>().unwrap().0.clone();
    let renderer = Renderer::new(move |event, renderer| {
        observed.lock().unwrap().push(event.clone());
        if let Event::Text(id, value) = event {
            publish(
                &renderer,
                json!([
                    {"op":"set-prop","id":id,"property":"text","value":value}
                ]),
            );
        }
    });
    publish(
        &renderer,
        json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":"file-picker"},
            {"op":"create-node","id":3,"kind":"text-field"},
            {"op":"set-prop","id":3,"property":"text","value":"draft"},
            {"op":"set-prop","id":3,"property":"change-enabled","value":true},
            {"op":"insert-child","parent":2,"child":3,"index":0},
            {"op":"insert-child","parent":1,"child":2,"index":0}
        ]),
    );
    renderer.set_root(1).unwrap();
    let token = Rc::new(Cell::new(9_007_199_254_740_992_i64));
    let mut actions = Vec::new();
    for (label, options, issue) in [
        ("Pick files", json!([]), true),
        (
            "Edit options",
            json!([
                {"op":"set-prop","id":2,"property":"multiple","value":true},
                {"op":"set-prop","id":2,"property":"accept","value":".MD, *.txt"}
            ]),
            false,
        ),
        (
            "Pick folders",
            json!([
                {"op":"set-prop","id":2,"property":"directory","value":true},
                {"op":"set-prop","id":2,"property":"multiple","value":true},
                {"op":"set-prop","id":2,"property":"accept","value":"image/png"}
            ]),
            true,
        ),
        (
            "Disable request",
            json!([
                {"op":"set-prop","id":2,"property":"enabled","value":false}
            ]),
            true,
        ),
        (
            "Enable request",
            json!([
                {"op":"set-prop","id":2,"property":"enabled","value":true}
            ]),
            false,
        ),
    ] {
        let renderer = renderer.clone();
        let token = token.clone();
        actions.push(nsh_base::button().child(text(label)).on_press(move || {
            let mut ops = options.as_array().unwrap().clone();
            if issue {
                token.set(token.get()+1);
                ops.push(json!({"op":"set-prop","id":2,"property":"request","value":token.get()}));
            }
            publish(&renderer, Value::Array(ops));
        }).into_element());
    }
    let repeat = renderer.clone();
    let repeated_token = token.clone();
    actions.push(
        nsh_base::button()
            .child(text("Repeat request"))
            .on_press(move || {
                publish(
                    &repeat,
                    json!([
                        {"op":"set-prop","id":2,"property":"request","value":repeated_token.get()},
                        {"op":"set-prop","id":2,"property":"source","value":"files"}
                    ]),
                );
            })
            .into_element(),
    );
    let reject = renderer.clone();
    actions.push(
        nsh_base::button()
            .child(text("Reject legacy options"))
            .on_press(move || {
                let generation = reject.0.borrow().store.generation;
                let picker = reject.0.borrow().nodes[&2].node.get_untracked();
                let editor = reject.0.borrow().nodes[&3].node.get_untracked();
                for (property, value) in [
                    ("source", json!("photos")),
                    ("source", json!("camera")),
                    ("completion", json!(1)),
                    ("types", json!("public.image")),
                    ("accept", json!("image/png")),
                ] {
                    assert!(reject.apply(patch(generation+1, json!([
                {"op":"set-prop","id":3,"property":"text","value":"must not publish"},
                {"op":"set-prop","id":2,"property":property,"value":value}
            ]))).is_err());
                    assert_eq!(reject.0.borrow().store.generation, generation);
                    assert!(Arc::ptr_eq(
                        &picker,
                        &reject.0.borrow().nodes[&2].node.get_untracked()
                    ));
                    assert!(Arc::ptr_eq(
                        &editor,
                        &reject.0.borrow().nodes[&3].node.get_untracked()
                    ));
                }
            })
            .into_element(),
    );
    let replace = renderer.clone();
    actions.push(
        nsh_base::button()
            .child(text("Replace picker"))
            .on_press(move || {
                let incarnation = replace.0.borrow().store.nodes[&2].incarnation;
                publish(
                    &replace,
                    json!([
                        {"op":"drop-node","id":2},
                        {"op":"create-node","id":2,"kind":"file-picker"},
                        {"op":"insert-child","parent":2,"child":3,"index":0},
                        {"op":"insert-child","parent":1,"child":2,"index":0}
                    ]),
                );
                replace.emit(
                    2,
                    incarnation,
                    Event::Picked(2, "stale native answer".into()),
                );
                replace.emit(2, incarnation, Event::Dismiss(2));
            })
            .into_element(),
    );
    view().flex_col().child(renderer.element()).child(actions)
}

fn start() -> (Headless, Arc<Mutex<Vec<Event>>>) {
    let observed = Arc::new(Mutex::new(Vec::new()));
    let mut app = Headless::start(EngineConfig {
        context: EngineContext::default().with(PickerProbe(observed.clone())),
        ..EngineConfig::new(Root::of::<FileSelection>())
    })
    .unwrap();
    app.wait_for("id:lui-3").unwrap();
    assert!(
        app.screen().file_requests().is_empty(),
        "no request token opens no dialog"
    );
    (app, observed)
}

fn identity(app: &Headless, id: &str) -> nsh_core::NodeId {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some(id))
        .unwrap()
        .id
}

fn answers(observed: &Mutex<Vec<Event>>) -> Vec<Value> {
    observed
        .lock()
        .unwrap()
        .iter()
        .filter_map(|event| match event {
            Event::Picked(2, payload) => Some(serde_json::from_str(payload).unwrap()),
            _ => None,
        })
        .collect()
}

#[test]
fn file_dialog_results_keep_exact_tokens_paths_and_authored_child_identity() {
    let (mut app, observed) = start();
    let picker = identity(&app, "lui-2");
    let editor = identity(&app, "lui-3");
    let first = std::env::temp_dir().join("notes-中文.md");
    let second = std::env::temp_dir().join("two.txt");
    app.on_pick_paths(vec![first.clone()]).unwrap();
    app.type_text("id:lui-3", " edited").unwrap();
    app.press("text:Pick files").unwrap();
    assert_eq!(
        answers(&observed),
        [json!({"request":9_007_199_254_740_993_i64,"paths":[first]})]
    );
    app.press("text:Repeat request").unwrap();
    app.press("text:Edit options").unwrap();
    assert_eq!(
        app.screen().file_requests().len(),
        1,
        "same token and option edits do not reopen"
    );
    app.on_pick_paths(vec![first.clone(), second.clone()])
        .unwrap();
    app.press("text:Pick files").unwrap();
    let requests = app.screen().file_requests();
    assert_eq!(requests.len(), 2);
    let FileRequest::OpenDialog(dialog) = &requests[1] else {
        panic!("native open dialog")
    };
    assert!(dialog.multiple && dialog.picks_files());
    assert_eq!(dialog.filters[0].extensions, ["md", "txt"]);
    assert_eq!(
        answers(&observed)[1],
        json!({"request":9_007_199_254_740_994_i64,"paths":[first,second]})
    );
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft edited")
    );
    assert_eq!(identity(&app, "lui-2"), picker);
    assert_eq!(identity(&app, "lui-3"), editor);
}

#[test]
fn native_cancel_is_dismiss_and_folder_dialog_uses_native_folder_options() {
    let (mut app, observed) = start();
    app.on_pick_paths(Vec::new()).unwrap();
    app.press("text:Pick files").unwrap();
    assert_eq!(*observed.lock().unwrap(), [Event::Dismiss(2)]);
    app.on_pick_paths(vec![std::env::temp_dir()]).unwrap();
    app.press("text:Pick folders").unwrap();
    let FileRequest::OpenDialog(dialog) = &app.screen().file_requests()[1] else {
        panic!("native folder dialog")
    };
    assert!(dialog.picks_folders() && !dialog.picks_files() && dialog.multiple);
    assert!(
        dialog.filters.is_empty(),
        "native folder dialogs ignore file filters"
    );
    assert_eq!(answers(&observed).len(), 1);
}

#[test]
fn disabled_requests_wait_for_enable_and_old_incarnations_cannot_deliver_answers() {
    let (mut app, observed) = start();
    app.on_pick_paths(vec![PathBuf::from("selected.txt")])
        .unwrap();
    app.press("text:Disable request").unwrap();
    assert!(app.screen().file_requests().is_empty());
    app.press("text:Enable request").unwrap();
    assert_eq!(answers(&observed).len(), 1);
    let old = identity(&app, "lui-2");
    app.press("text:Replace picker").unwrap();
    assert_ne!(identity(&app, "lui-2"), old);
    assert_eq!(answers(&observed).len(), 1);
    assert!(!observed.lock().unwrap().contains(&Event::Dismiss(2)));
    app.press("text:Pick files").unwrap();
    assert_eq!(answers(&observed).len(), 2);
}

#[test]
fn native_dialog_failure_is_a_result_and_unsupported_options_are_atomic() {
    let (mut app, observed) = start();
    app.type_text("id:lui-3", " retained").unwrap();
    let editor = identity(&app, "lui-3");
    app.press("text:Reject legacy options").unwrap();
    assert!(app.screen().file_requests().is_empty());
    assert_eq!(
        app.screen().input_text("id:lui-3").unwrap(),
        Some("draft retained")
    );
    assert_eq!(identity(&app, "lui-3"), editor);
    // The default headless environment has no native file-dialog service.
    app.press("text:Pick files").unwrap();
    let results = answers(&observed);
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["paths"], json!([]));
    assert!(
        results[0]["error"]
            .as_str()
            .is_some_and(|error| !error.is_empty())
    );
    assert!(!observed.lock().unwrap().contains(&Event::Dismiss(2)));
}
