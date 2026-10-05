//! Imperative dom-op channel: `dom-op` platform requests target rendered
//! nodes by ref (`{"node-id": n}` or `{"#ref"/"ref-id": "identifier"}` —
//! the identifier matches a node's `accessibility-identifier` prop).
//! Ops that produce replies return `(name, json)` pairs the host feeds to
//! `lui_ocaml_platform_event("name\njson")`.

use gpui_kit::gpui::{px, App, Bounds, Focusable, Pixels};
use lui_core::Property;
use serde_json::{json, Value};

use crate::backend::Shared;

/// Resolve one `{"node-id"|"#ref"|"ref-id": …}` ref to a node id.
fn resolve_ref(shared: &Shared, ref_: &Value) -> Option<i64> {
    if let Some(id) = ref_.get("node-id").and_then(Value::as_i64) {
        return Some(id);
    }
    let ident = ref_
        .get("#ref")
        .or_else(|| ref_.get("ref-id"))
        .and_then(Value::as_str)?;
    let shared = shared.borrow();
    shared
        .store
        .nodes
        .iter()
        .find(|(_, node)| {
            node.prop(Property::AccessibilityIdentifier)
                .and_then(|v| v.as_str())
                == Some(ident)
        })
        .map(|(id, _)| *id)
}

fn ref_field<'a>(body: &'a Value, key: &str) -> Option<&'a Value> {
    body.get(key)
}

/// Window-space bounds of `node_id`'s rendered element, if prepainted.
fn node_bounds(shared: &Shared, node_id: i64) -> Option<Bounds<Pixels>> {
    shared.borrow().node_bounds.get(&node_id).copied()
}

fn bounds_json(bounds: Option<Bounds<Pixels>>) -> Value {
    match bounds {
        Some(b) => json!({
            "left": f32::from(b.origin.x),
            "top": f32::from(b.origin.y),
            "right": f32::from(b.origin.x + b.size.width),
            "bottom": f32::from(b.origin.y + b.size.height),
            "width": f32::from(b.size.width),
            "height": f32::from(b.size.height),
        }),
        None => Value::Null,
    }
}

/// Index of `target` (or the ancestor of `target` that is a direct child)
/// inside `container`'s child list.
fn child_index_of(shared: &Shared, container: i64, target: i64) -> Option<usize> {
    let shared = shared.borrow();
    let children = &shared.store.node(container)?.children;
    if let Some(i) = children.iter().position(|c| *c == target) {
        return Some(i);
    }
    // Walk up from target until we hit a direct child of the container.
    let mut cursor = shared.store.node(target)?.parent?;
    loop {
        if let Some(i) = children.iter().position(|c| *c == cursor) {
            return Some(i);
        }
        cursor = shared.store.node(cursor)?.parent?;
    }
}

/// Handle one dom-op. Returns `(name, json)` platform events to emit
/// back to OCaml (currently just `node-rect` replies).
pub fn handle_dom_op(shared: &Shared, op: &str, body: &str, cx: &mut App) -> Vec<(String, Value)> {
    let parsed: Value = match serde_json::from_str(body) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("lui-gpui: dom-op {op} bad json: {e}");
            return Vec::new();
        }
    };
    let ref_ = ref_field(&parsed, "ref").cloned().unwrap_or(Value::Null);
    let target = resolve_ref(shared, &ref_);

    match op {
        "measure-node" => {
            let mut events = Vec::new();
            if let Some(id) = target {
                events.push((
                    "node-rect".to_string(),
                    json!({ "nodeId": id, "rect": bounds_json(node_bounds(shared, id)) }),
                ));
            }
            events
        }
        "scroll-into-view" | "scroll-to-node" => {
            let Some(id) = target else { return Vec::new() };
            let Some(ancestor) = find_scroll_ancestor(shared, id, cx) else {
                return Vec::new();
            };
            if let Some(ix) = child_index_of(shared, ancestor, id) {
                scroll_to_item(shared, ancestor, ix, cx);
            }
            Vec::new()
        }
        "scroll-row-into-view" => {
            let Some(scroller) =
                ref_field(&parsed, "scroller").and_then(|r| resolve_ref(shared, r))
            else {
                return Vec::new();
            };
            let Some(row) = ref_field(&parsed, "row").and_then(|r| resolve_ref(shared, r)) else {
                return Vec::new();
            };
            if let Some(ix) = child_index_of(shared, scroller, row) {
                scroll_to_item(shared, scroller, ix, cx);
            }
            Vec::new()
        }
        "focus" => {
            if let Some(id) = target {
                focus_node(shared, id, cx);
            }
            Vec::new()
        }
        "dump-frames" => {
            dump_tree(shared);
            Vec::new()
        }
        other => {
            eprintln!("lui-gpui: dom-op {other} unsupported: {body}");
            Vec::new()
        }
    }
}

fn find_scroll_ancestor(shared: &Shared, node_id: i64, cx: &mut App) -> Option<i64> {
    let mut cursor = Some(node_id);
    while let Some(id) = cursor {
        let tracked = shared
            .borrow()
            .views
            .get(&id)
            .map(|view| view.read_with(cx, |view, _| view.states.scroll_tracked))
            .unwrap_or(false);
        if tracked {
            return Some(id);
        }
        cursor = shared.borrow().store.node(id).and_then(|n| n.parent);
    }
    None
}

fn scroll_to_item(shared: &Shared, node_id: i64, ix: usize, cx: &mut App) {
    if let Some(view) = shared.borrow().views.get(&node_id).cloned() {
        view.update(cx, |view, _| {
            view.states.scroll.scroll_to_item(ix);
        });
    }
}

fn focus_node(shared: &Shared, node_id: i64, cx: &mut App) {
    let Some(view) = shared.borrow().views.get(&node_id).cloned() else {
        return;
    };
    let Some(window_handle) = cx.windows().first().copied() else {
        eprintln!("lui-gpui: focus on node {node_id}: no window");
        return;
    };
    let _ = window_handle.update(cx, move |_, window, cx| {
        view.update(cx, |view, cx| {
            // Focusable component states own FocusHandles; generic nodes
            // have no focusable element until the editor surface lands.
            let handle = if let Some(input) = &view.states.input {
                Some(input.read(cx).focus_handle(cx))
            } else {
                view.states
                    .textarea
                    .as_ref()
                    .map(|textarea| textarea.read(cx).focus_handle(cx))
            };
            match handle {
                Some(handle) => handle.focus(window, cx),
                None => {
                    eprintln!("lui-gpui: focus on node {node_id}: no focusable state")
                }
            }
        });
    });
}

fn dump_tree(shared: &Shared) {
    let shared = shared.borrow();
    fn walk(shared: &LuiSharedGuard<'_>, id: i64, depth: usize, out: &mut String) {
        let Some(node) = shared.store.node(id) else {
            return;
        };
        let kind = node.identity.label();
        let bounds = shared
            .node_bounds
            .get(&id)
            .map(|b| {
                format!(
                    " [{},{} {}x{}]",
                    f32::from(b.origin.x),
                    f32::from(b.origin.y),
                    f32::from(b.size.width),
                    f32::from(b.size.height)
                )
            })
            .unwrap_or_default();
        out.push_str(&format!("{}{} #{id}{bounds}\n", "  ".repeat(depth), kind));
        for child in &node.children {
            walk(shared, *child, depth + 1, out);
        }
    }
    let mut out = String::new();
    if let Some(root) = shared.store.root {
        walk(&shared, root, 0, &mut out);
    }
    eprintln!("lui-gpui: frame dump\n{out}");
}

/// Borrow guard alias so `walk` reads from one borrow.
type LuiSharedGuard<'a> = std::cell::Ref<'a, crate::backend::LuiShared>;

/// Root node bounds come from the window (no parent records them).
pub fn note_root_bounds(shared: &Shared, width: f32, height: f32) {
    if let Some(root) = shared.borrow().store.root {
        shared.borrow_mut().node_bounds.insert(
            root,
            Bounds::new(
                gpui_kit::gpui::point(px(0.), px(0.)),
                gpui_kit::gpui::size(px(width), px(height)),
            ),
        );
    }
}
