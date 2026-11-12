//! Real Parent source replacement in a process owning only its own OCaml library.
#[path = "support/ocaml_virtual.rs"]
mod fixture;
use fixture::*;
use std::time::Duration;

fn current_factory_visible(screen: &nsh_testing::Screen, revision: i32) -> bool {
    let prefix = format!("Factory {revision} row ");
    let nodes = screen.layout_nodes();
    let Some(viewport) = nodes
        .iter()
        .find(|node| node.test_id.as_deref() == Some("replacement-scroll"))
    else {
        return false;
    };
    !viewport.hidden
        && nodes.iter().any(|node| {
            !node.hidden
                && node
                    .text
                    .as_ref()
                    .is_some_and(|text| text.text.visible_text().starts_with(&prefix))
                && node.bounds.size.width.0 > 0.0
                && node.bounds.size.height.0 > 0.0
                && node.bounds.origin.x.0 >= viewport.bounds.origin.x.0
                && node.bounds.origin.y.0 >= viewport.bounds.origin.y.0
                && node.bounds.origin.x.0 + node.bounds.size.width.0
                    <= viewport.bounds.origin.x.0 + viewport.bounds.size.width.0
                && node.bounds.origin.y.0 + node.bounds.size.height.0
                    <= viewport.bounds.origin.y.0 + viewport.bounds.size.height.0
        })
}

#[test]
fn real_ocaml_parent_source_factory_replacement_never_leaves_a_blank_viewport() -> Result<(), String>
{
    let library = fixture_library("virtual_replacement", "LUI_NSH_VIRTUAL_REPLACEMENT_LIBRARY")?;
    let (mut app, mut agent) = start(library)?;
    let initial = wait_tree(&mut app, &mut agent, "initial replacement source", |tree| {
        identified(tree, "virtual-list")
            .is_some_and(|node| node["props"]["virtual-total-count"] == 1_000)
    })?;
    let wire_scroll =
        identified(&initial, "replacement-scroll").ok_or("missing parent Scroll")?["id"].clone();
    let wire_list =
        identified(&initial, "virtual-list").ok_or("missing Parent source")?["id"].clone();
    app.wait_for("id:replacement-scroll")?;
    let native_scroll =
        native_id(&app, "replacement-scroll").ok_or("parent Scroll has no native owner")?;
    let outside =
        identified(&initial, "replacement-outside").ok_or("missing outside input")?["id"].clone();
    app.scroll("id:replacement-scroll", nsh_core::geometry::px(100_000.0))?;
    let far = wait_tree(&mut app, &mut agent, "far Parent source demand", |tree| {
        indices(tree).last() == Some(&999)
    })?;
    bounded(&app, &far, 1_000);
    app.wait_for("text:Factory 0 row 999")?;
    app.wait_until(
        "initial far factory occupies its actual viewport",
        Duration::from_secs(5),
        |screen| current_factory_visible(screen, 0),
    )?;
    let mut generation = identified(&far, "virtual-list").unwrap()["props"]["virtual-generation"]
        .as_u64()
        .ok_or("missing source generation")?;
    for revision in 1..=2 {
        app.press("id:rebuild-factory")?;
        let replaced = wait_tree(
            &mut app,
            &mut agent,
            "new real source factory revision",
            |tree| {
                status(tree) == format!("factory={revision}")
                    && identified(tree, "virtual-list").is_some_and(|node| {
                        node["props"]["virtual-generation"]
                            .as_u64()
                            .is_some_and(|next| next > generation)
                    })
            },
        )?;
        assert_eq!(
            identified(&replaced, "replacement-scroll").unwrap()["id"],
            wire_scroll
        );
        assert_eq!(
            identified(&replaced, "virtual-list").unwrap()["id"],
            wire_list
        );
        assert_eq!(
            identified(&replaced, "replacement-outside").unwrap()["id"],
            outside
        );
        assert_eq!(native_id(&app, "replacement-scroll"), Some(native_scroll));
        // Either a preserved or reset source position is valid here. The real
        // native viewport must contain current-revision data without another
        // wheel/scroll command or synthetic VirtualWindow after replacement.
        app.wait_until(
            "current factory row inside its actual parent viewport",
            Duration::from_secs(5),
            |screen| current_factory_visible(screen, revision),
        )
        .map_err(|error| {
            format!(
                "{error}; canonical={replaced}; native={:?}",
                app.screen().texts()
            )
        })?;
        let settled = agent.tree()?;
        bounded(&app, &settled, 1_000);
        generation = identified(&settled, "virtual-list").unwrap()["props"]["virtual-generation"]
            .as_u64()
            .ok_or("replacement lost source generation")?;
    }
    Ok(())
}
