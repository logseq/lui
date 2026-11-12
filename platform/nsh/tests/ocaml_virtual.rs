//! Real OCaml sparse rows through the public native ABI, NSH engine and agent.
#[path = "support/ocaml_virtual.rs"]
mod fixture;
use fixture::*;
use nsh_testing::Headless;
use serde_json::{Value, json};
use std::{collections::BTreeMap, time::Duration};

impl Agent {
    fn press(&mut self, identifier: &str) -> Result<(), String> {
        self.request(
            json!({"op":"press", "selector":format!("prop:accessibility-identifier={identifier}")}),
        )?;
        Ok(())
    }
}
fn completion(tree: &Value, token: usize) -> Option<(String, usize)> {
    status(tree)
        .split_once("completions=")?
        .1
        .split(',')
        .find_map(|entry| {
            let mut parts = entry.split(':');
            let found: usize = parts.next()?.parse().ok()?;
            let outcome = parts.next()?.to_owned();
            let count = parts.next()?.parse().ok()?;
            (found == token).then_some((outcome, count))
        })
}
fn wait_status(app: &mut Headless, agent: &mut Agent, expected: &str) -> Result<Value, String> {
    wait_tree(app, agent, expected, |tree| status(tree).contains(expected))
}
fn jump(
    app: &mut Headless,
    agent: &mut Agent,
    identifier: &str,
    token: &mut usize,
    outcome: &str,
) -> Result<Value, String> {
    *token += 1;
    agent.press(identifier)?;
    let tree = wait_tree(app, agent, "exactly one scroll completion", |tree| {
        completion(tree, *token).is_some()
    })?;
    assert_eq!(completion(&tree, *token), Some((outcome.to_owned(), 1)));
    app.wait(Duration::from_millis(40))?;
    let settled = agent.tree()?;
    assert_eq!(completion(&settled, *token), Some((outcome.to_owned(), 1)));
    Ok(settled)
}
#[test]
fn real_ocaml_sparse_rows_keep_focus_and_bound_both_trees_through_reorder() -> Result<(), String> {
    let library = fixture_library("virtual", "LUI_NSH_VIRTUAL_LIBRARY")?;
    let (mut app, mut agent) = start(library.clone())?;
    let baseline = wait_status(&mut app, &mut agent, "count=0 ")?;
    let baseline_wire = nodes(&baseline).len();
    let mut token = 0;
    let mut samples = BTreeMap::new();
    for count in [1_000, 100_000] {
        app.press(if count == 1_000 {
            "id:load-1k"
        } else {
            "id:load-100k"
        })?;
        wait_status(&mut app, &mut agent, &format!("count={count} "))?;
        app.wait_for("id:row-2-editor")?;
        app.type_text("id:row-2-editor", "!")?;
        let edited = wait_status(&mut app, &mut agent, "edited2=\"Row 2!\"")?;
        let wire_editor = identified(&edited, "row-2-editor").unwrap()["id"].clone();
        let native_editor = native_id(&app, "row-2-editor").ok_or("no native editor")?;
        let far = jump(&mut app, &mut agent, "jump-last", &mut token, "succeeded")?;
        assert!(
            indices(&far).contains(&2),
            "distant focused row was not pinned"
        );
        assert!(indices(&far).iter().any(|index| *index >= count - 10));
        app.wait_for(&format!("id:activate-{}", count - 1))?;
        let extent = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("virtual-list"))
            .and_then(|node| node.scroll)
            .and_then(|scroll| scroll.content_size)
            .ok_or("list did not expose its logical extent")?;
        assert!(
            extent.height.0 >= (count - 1) as f32 * 32.0,
            "source extent was truncated to sparse rows"
        );
        agent.press(&format!("activate-{}", count - 1))?;
        wait_status(&mut app, &mut agent, &format!("activated={}", count - 1))?;
        agent.press("reorder")?;
        let reordered = wait_status(&mut app, &mut agent, &format!("row2-index={}", count - 1))?;
        assert_eq!(
            identified(&reordered, "row-2-editor").unwrap()["id"],
            wire_editor
        );
        assert_eq!(native_id(&app, "row-2-editor"), Some(native_editor));
        // No selector refocuses the editor: this character proves native focus survived.
        app.press_key("z")?;
        wait_status(&mut app, &mut agent, "edited2=\"Row 2!z\"")?;
        jump(&mut app, &mut agent, "jump-top", &mut token, "succeeded")?;
        let pinned = wait_tree(
            &mut app,
            &mut agent,
            "distant reordered editor pin",
            |tree| indices(tree).contains(&(count - 1)),
        )?;
        samples.insert(count, bounded(&app, &pinned, count));
        // Focusing an input is a native keyboard step, not a pressable action.
        app.type_text("id:outside-editor", "")?;
        let released = wait_tree(
            &mut app,
            &mut agent,
            "stationary blur releases the distant editor",
            |tree| {
                identified(tree, "row-2-editor").is_none() && !indices(tree).contains(&(count - 1))
            },
        )?;
        bounded(&app, &released, count);
        jump(&mut app, &mut agent, "jump-last", &mut token, "succeeded")?;
        app.wait_for("id:row-2-editor")?;
        assert_eq!(app.screen().input_text("id:row-2-editor")?, Some("Row 2!z"));
        app.type_text("id:row-2-editor", "r")?;
        wait_status(&mut app, &mut agent, "edited2=\"Row 2!zr\"")?;
        agent.press("remove-row-2")?;
        let removed = wait_tree(&mut app, &mut agent, "focused row removal", |tree| {
            status(tree).contains(&format!("count={} ", count - 1))
                && identified(tree, "row-2-editor").is_none()
        })?;
        bounded(&app, &removed, count - 1);
        app.press_key("q")?;
        wait_status(&mut app, &mut agent, "edited2=\"Row 2!zr\"")?;
        agent.press("shrink")?;
        let shrunk = wait_status(&mut app, &mut agent, "count=20 ")?;
        bounded(&app, &shrunk, 20);
        jump(
            &mut app,
            &mut agent,
            "jump-missing",
            &mut token,
            "missing-target",
        )?;
        agent.press("clear")?;
        let cleared = wait_tree(
            &mut app,
            &mut agent,
            "Clear releases committed rows",
            |tree| {
                status(tree).contains("count=0 ")
                    && indices(tree).is_empty()
                    && nodes(tree).len() == baseline_wire
            },
        )?;
        bounded(&app, &cleared, 0);
    }
    let small = samples[&1_000];
    let large = samples[&100_000];
    assert!(
        large.0 <= small.0 + 12,
        "LUI nodes grew with source size: {samples:?}"
    );
    assert!(
        large.1 <= small.1 + 32,
        "NSH nodes grew with source size: {samples:?}"
    );
    for _cycle in 0..10 {
        agent.press("load-100k")?;
        wait_status(&mut app, &mut agent, "count=100000 ")?;
        let far = jump(&mut app, &mut agent, "jump-last", &mut token, "succeeded")?;
        bounded(&app, &far, 100_000);
        agent.press("clear")?;
        let cleared = wait_tree(
            &mut app,
            &mut agent,
            "repeat Clear returns LUI nodes to baseline",
            |tree| status(tree).contains("count=0 ") && nodes(tree).len() == baseline_wire,
        )?;
        bounded(&app, &cleared, 0);
    }
    eprintln!("real OCaml sparse source comparison (LUI, NSH, rows): {samples:?}");
    drop(agent);
    drop(app);
    let (mut reopened, mut agent) = start(library)?;
    let fresh = wait_status(&mut reopened, &mut agent, "count=0 ")?;
    assert_eq!(nodes(&fresh).len(), baseline_wire);
    assert!(status(&fresh).contains("edited2=\"Row 2\" token=0"));
    assert_eq!(bounded(&reopened, &fresh, 0).2, 0);
    Ok(())
}
