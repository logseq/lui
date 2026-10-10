//! Scroll requests (`scroll-target`/`scroll-anchor`/`scroll-token`),
//! `track-visible-range` reports, and `image` `load` events — the gpui
//! driver for wire contract pieces that need per-frame bookkeeping.
//! Outcome strings mirror the Apple backend's ScrollViewProxy driver so
//! OCaml sees the same vocabulary on every host: "succeeded",
//! "superseded", "missing-target", "cancelled".

use crate::backend::Shared;
use gpui_kit::gpui::{px, App};
use lui_core::wire_schema::{NodeKind, Property};

/// Per-frame bookkeeping for one painted node — called from the node's
/// prepaint once its bounds are fresh. Store reads and scroll-handle
/// writes stay inside one borrow; the FFI emissions are deferred past
/// the layout pass so applying their response batches can't mutate the
/// tree mid-paint (same reason `appear` defers).
pub(crate) fn tick(shared: &Shared, node_id: i64, window: &mut gpui_kit::gpui::Window, cx: &mut App) {
    // (visible-range span, completed scroll outcome, image load)
    let mut visible_span = None;
    let mut completed: Vec<(i64, &'static str)> = Vec::new();
    let mut load = false;
    {
        let mut guard = shared.borrow_mut();
        let Some(node) = guard.store.node(node_id) else {
            return;
        };
        match node.identity.kind() {
            Some(NodeKind::VirtualList | NodeKind::ListContainer) => {
                if node.flag(Property::TrackVisibleRange) {
                    // Report the first/last child index whose painted bounds
                    // intersect the list's viewport. Unpainted children
                    // (virtual rows outside the window) carry no bounds, so
                    // this works for both the virtual `list` and a fully
                    // laid out `list-container`/`virtual-list`.
                    if let Some(viewport) = guard.node_bounds.get(&node_id).copied() {
                        let mut first = i64::MAX;
                        let mut last = 0i64;
                        for (index, child) in node.children.iter().enumerate() {
                            if guard
                                .node_bounds
                                .get(child)
                                .is_some_and(|bounds| bounds.intersects(&viewport))
                            {
                                first = first.min(index as i64);
                                last = last.max(index as i64);
                            }
                        }
                        if first <= last
                            && guard.visible_ranges.get(&node_id) != Some(&(first, last))
                        {
                            guard.visible_ranges.insert(node_id, (first, last));
                            visible_span = Some((first, last));
                        }
                    }
                }
                scroll_request(&mut guard, node_id, &mut completed);
            }
            Some(NodeKind::Image) => {
                if !guard.loaded_images.contains(&node_id) {
                    // File paths gate on existence so a missing asset never
                    // reports success; url/image-id sources report when the
                    // element commits (gpui decodes off-thread, so the first
                    // painted frame is the closest honest signal here).
                    let ready = if let Some(path) = node.string_prop(Property::PathValue) {
                        std::path::Path::new(path).exists()
                    } else {
                        node.string_prop(Property::UrlValue).is_some()
                            || node.string_prop(Property::ImageIdValue).is_some()
                    };
                    if ready {
                        guard.loaded_images.insert(node_id);
                        load = true;
                    }
                }
            }
            _ => {}
        }
    }
    if visible_span.is_none() && completed.is_empty() && !load {
        return;
    }
    let shared = shared.clone();
    window.defer(cx, move |_, cx| {
        if let Some((first, last)) = visible_span {
            let accepted =
                unsafe { lui_core::bridge::lui_ocaml_visible_range(node_id, first, last) };
            if std::env::var_os("LUI_GPUI_DUMP_SCROLL").is_some() {
                eprintln!("visible-range node={node_id} first={first} last={last} rc={accepted}");
            }
            let _ = accepted;
        }
        for (token, outcome) in &completed {
            scroll_completed(node_id, *token, outcome, cx);
        }
        if load {
            let accepted = unsafe { lui_core::bridge::lui_ocaml_load(node_id) };
            if std::env::var_os("LUI_GPUI_DUMP_SCROLL").is_some() {
                eprintln!("load node={node_id} rc={accepted}");
            }
            let _ = accepted;
        }
        crate::backend::drain_pending(&shared, cx);
    });
}

/// `lui_ocaml_scroll_completed` with a borrowed outcome literal — the C
/// side does `strlen`, so hand it a real NUL-terminated buffer.
pub(crate) fn scroll_completed(node: i64, token: i64, outcome: &'static str, cx: &mut App) {
    let outcome_c = std::ffi::CString::new(outcome).expect("static outcome is NUL-free");
    let accepted = unsafe {
        lui_core::bridge::lui_ocaml_scroll_completed(node, token, outcome_c.as_ptr())
    };
    if std::env::var_os("LUI_GPUI_DUMP_SCROLL").is_some() {
        eprintln!("scroll-completed node={node} token={token} outcome={outcome} rc={accepted}");
    }
    let _ = accepted;
    let _ = cx;
}



/// `scroll-token` handling. A new token supersedes any scroll still in
/// flight; a resolved request reports "succeeded" on the next frame once
/// the offset has actually been applied by the scrollable element. Reads
/// and scroll-handle writes happen under the shared borrow; outcomes are
/// queued for the caller's FFI phase.
fn scroll_request(
    guard: &mut crate::backend::LuiShared,
    node_id: i64,
    completed: &mut Vec<(i64, &'static str)>,
) {
    let Some(node) = guard.store.node(node_id) else {
        return;
    };
    let token = node.int_prop(Property::ScrollToken);
    if let Some(pending) = guard.pending_scrolls.remove(&node_id) {
        if token == Some(pending) {
            // The requested offset was applied by the scrollable element
            // during this frame's layout pass — report completion.
            completed.push((pending, "succeeded"));
        } else {
            // A newer token arrived before the in-flight scroll reported.
            completed.push((pending, "superseded"));
        }
    }
    let Some(token) = token else {
        return;
    };
    if guard.handled_scroll_tokens.get(&node_id) == Some(&token) {
        return;
    }
    guard.handled_scroll_tokens.insert(node_id, token);
    // Resolve `scroll-target` against a child's `key` prop — the protocol's
    // scroll target is a row key, not a node id.
    let index = node
        .string_prop(Property::ScrollTarget)
        .and_then(|target| {
            node.children.iter().position(|child| {
                guard
                    .store
                    .node(*child)
                    .and_then(|row| row.string_prop(Property::KeyValue))
                    == Some(target)
            })
        });
    match index {
        None => completed.push((token, "missing-target")),
        Some(index) => {
            perform_scroll(guard, node_id, index);
            guard.pending_scrolls.insert(node_id, token);
        }
    }
}

/// Drive the node's scroll state toward `index`, honoring `scroll-anchor`
/// ("top" | "center" | "bottom"; unset → reveal, the web's
/// `scrollIntoView({block: "nearest"})` behavior).
fn perform_scroll(guard: &mut crate::backend::LuiShared, node_id: i64, index: usize) {
    let Some(node) = guard.store.node(node_id) else {
        return;
    };
    let anchor = node.string_prop(Property::ScrollAnchor).unwrap_or("");
    if node.identity.kind() == Some(NodeKind::VirtualList) {
        if let Some(list) = guard.virtual_lists.get(&node_id) {
            match anchor {
                "top" => list.state.scroll_to(gpui_kit::gpui::ListOffset {
                    item_ix: index,
                    offset_in_item: px(0.),
                }),
                // `bounds_for_item` only sees measured items at or below
                // the scroll top — land the item at the top first, then
                // nudge by its measured offset so the anchor is exact.
                "center" | "bottom" => {
                    list.state.scroll_to(gpui_kit::gpui::ListOffset {
                        item_ix: index,
                        offset_in_item: px(0.),
                    });
                    if let Some(item) = list.state.bounds_for_item(index) {
                        let viewport = list.state.viewport_bounds();
                        let delta = if anchor == "center" {
                            item.center().y - viewport.center().y
                        } else {
                            item.bottom() - viewport.bottom()
                        };
                        if delta != px(0.) {
                            list.state.scroll_by(delta);
                        }
                    }
                }
                _ => list.state.scroll_to_reveal_item(index),
            }
        }
        return;
    }
    // `list-container` scrolls a plain div whose ScrollHandle is tracked
    // at render time; gpui's ScrollHandle only offers top/first-visible
    // placement, so center and bottom anchors are resolved against
    // recorded child bounds.
    let Some(scroll) = guard.scroll_handles.get(&node_id).cloned() else {
        return;
    };
    match anchor {
        "center" | "bottom" => {
            let child = node.children.get(index).copied();
            let viewport = guard.node_bounds.get(&node_id).copied();
            let child_bounds = child.and_then(|id| guard.node_bounds.get(&id).copied());
            if let (Some(viewport), Some(child_bounds)) = (viewport, child_bounds) {
                let offset = scroll.offset();
                let target = if anchor == "center" {
                    viewport.center().y - child_bounds.center().y
                } else {
                    viewport.bottom() - child_bounds.bottom()
                };
                scroll.set_offset(gpui_kit::gpui::point(offset.x, target));
            } else {
                // Bounds not painted yet — fall back to reveal.
                scroll.scroll_to_item(index);
            }
        }
        "top" => scroll.scroll_to_top_of_item(index),
        _ => scroll.scroll_to_item(index),
    }
}
