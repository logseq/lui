//! `split-view` extension on gpui-base `DockArea`.
//!
//! The OCaml `Lui_split.Model` owns the split tree and emits it as extension
//! nodes: `split-view` → `split-branch` (orientation/ratio) → `split-pane`
//! (pane-id/selected) → `split-tab` (tab-id/title/closable + content). The
//! dock is a *view* of that tree: every render syncs the described layout in
//! via `DockArea::set_center` when the subtree signature changed. Gestures
//! inside the dock (tab clicks, closes, drags, edge drops, split resizes)
//! mutate the dock's own tree first; `DockEvent::LayoutChanged` then triggers
//! a `dump()` diff against the last synced summary, which is translated back
//! into the granular `split-pane`/`split-branch` extension events the model
//! understands (`tab-selected`, `tab-closed`, `tab-moved`, `split-drop`,
//! `pane-closed`, `ratio-changed`).

use std::collections::{BTreeSet, HashMap, HashSet};
use std::ffi::CStr;

use gpui_kit::base::dock::{Panel as BasePanel, PanelEvent, PanelInfo, PanelState};
use gpui_kit::component::dock::{DockArea, DockEvent, DockLayout, DockSkin, Panel};
use gpui_kit::gpui::{
    div, px, AnyElement, App, AppContext, Axis, Context, Entity, EventEmitter, FocusHandle,
    Focusable, InteractiveElement, IntoElement, ParentElement, Render, SharedString, Styled,
    Window,
};
use lui_core::store::{NodeIdentity, Store};
use lui_core::wire::Value;

use crate::backend::{LuiShared, Shared};
use crate::extension::fire_extension;
use crate::node_view::{LuiNodeView, NodeSnapshot};

/// A dock panel backed by a `split-tab` node: renders the tab's children and
/// reports `closable`/`title` from its extension props.
pub struct LuiPanel {
    shared: Shared,
    tab_node: i64,
    focus: FocusHandle,
}

impl LuiPanel {
    fn prop(&self, name: &str) -> Option<Value> {
        let shared = self.shared.borrow();
        shared
            .store
            .node(self.tab_node)
            .and_then(|n| n.extension_props.get(name))
            .cloned()
    }
}

impl EventEmitter<PanelEvent> for LuiPanel {}

impl Focusable for LuiPanel {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for LuiPanel {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let children = NodeSnapshot::snapshot(&self.shared.borrow().store, self.tab_node)
            .map(|n| n.children)
            .unwrap_or_default();
        let mut el = div().id(("lui-panel", self.tab_node as usize)).size_full();
        for child_id in children {
            if self.shared.borrow().store.node(child_id).is_some() {
                el = el.child(LuiShared::view_for(&self.shared, child_id, cx));
            }
        }
        el
    }
}

impl BasePanel for LuiPanel {
    fn panel_name(&self) -> &'static str {
        "lui-split-tab"
    }

    fn closable(&self, _cx: &App) -> bool {
        self.prop("closable").and_then(|v| v.as_bool()) == Some(true)
    }

    fn zoomable(&self, _cx: &App) -> bool {
        false
    }

    /// Carry the LUI node id inside the persisted leaf so `dump()` diffs can
    /// map panels back to `split-tab` nodes without a side table.
    fn dump(&self, _cx: &App) -> PanelState {
        PanelState {
            panel_name: self.panel_name().to_string(),
            children: Vec::new(),
            info: PanelInfo::Panel(serde_json::json!({ "tab": self.tab_node })),
        }
    }
}

impl Panel for LuiPanel {
    fn title(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let title = self
            .prop("title")
            .and_then(|v| v.as_str().map(str::to_string))
            .unwrap_or_default();
        div().text_sm().child(SharedString::from(title))
    }

    /// LUI children own their spacing; the tab group adds none.
    fn inner_padding(&self, _cx: &App) -> bool {
        false
    }
}

/// Semantic projection of `DockAreaState.center` — structure, tab identity
/// (LUI node ids recovered from the leaf `dump` payload) and resolved sizes.
/// `PanelId`/`NodeId` are dock-internal and unstable across `set_center`, so
/// comparisons run on this instead.
#[derive(Clone, Debug, PartialEq)]
enum SemNode {
    Stack {
        axis: Axis,
        sizes: Vec<f32>,
        kids: Vec<SemNode>,
    },
    Tabs {
        tabs: Vec<i64>,
        active: Option<i64>,
    },
}

/// Per-`split-view` dock state on [`ComponentStates`].
pub struct DockSync {
    pub area: Entity<DockArea>,
    /// Extension-subtree signature last pushed — the model is the source of
    /// truth, so only a signature change justifies a `set_center`.
    signature: String,
    /// Last known semantic tree — either what we pushed or a dump we already
    /// translated into events. LayoutChanged diffs against this.
    summary: Option<SemNode>,
    /// `split-tab` node id → panel entity (stable `PanelId`s across syncs).
    panels: HashMap<i64, Entity<LuiPanel>>,
}

fn snapshot_of(shared: &Shared, id: i64) -> Option<NodeSnapshot> {
    NodeSnapshot::snapshot(&shared.borrow().store, id)
}

fn identifier(node: &NodeSnapshot) -> &str {
    match &node.identity {
        NodeIdentity::Extension { identifier, .. } => identifier.as_str(),
        _ => "",
    }
}

fn ext_str(shared: &Shared, id: i64, name: &str) -> Option<String> {
    let shared = shared.borrow();
    shared
        .store
        .node(id)
        .and_then(|n| n.extension_props.get(name))
        .and_then(|v| v.as_str())
        .map(str::to_string)
}

fn signature(shared: &Shared, node: &NodeSnapshot) -> String {
    fn go(shared: &Shared, node: &NodeSnapshot, out: &mut String) {
        out.push_str(identifier(node));
        // extension_props is a BTreeMap — Debug order is deterministic.
        out.push_str(&format!("{:?}", node.extension_props));
        out.push('[');
        for child in &node.children {
            if let Some(child) = snapshot_of(shared, *child) {
                go(shared, &child, out);
            }
        }
        out.push(']');
    }
    let mut out = String::new();
    go(shared, node, &mut out);
    out
}

/// Tree shape without sizes/selection — used to decide whether last sync's
/// measured extents still line up with the model's branches.
fn shape(shared: &Shared, node: &NodeSnapshot) -> String {
    fn go(shared: &Shared, node: &NodeSnapshot, out: &mut String) {
        match identifier(node) {
            "split-branch" => out.push_str(
                if ext_of(node, "orientation").as_deref() == Some("horizontal") {
                    "H"
                } else {
                    "V"
                },
            ),
            "split-pane" => out.push('T'),
            _ => {}
        }
        for child in &node.children {
            if let Some(child) = snapshot_of(shared, *child) {
                go(shared, &child, out);
            }
        }
    }
    let mut out = String::new();
    go(shared, node, &mut out);
    out
}

fn ext_of(node: &NodeSnapshot, name: &str) -> Option<String> {
    node.extension_props
        .get(name)
        .and_then(|v| v.as_str())
        .map(str::to_string)
}

fn sem_shape(node: &SemNode) -> String {
    let mut out = String::new();
    fn go(node: &SemNode, out: &mut String) {
        match node {
            SemNode::Stack { axis, kids, .. } => {
                out.push_str(if *axis == Axis::Horizontal { "H" } else { "V" });
                for kid in kids {
                    go(kid, out);
                }
            }
            SemNode::Tabs { .. } => out.push('T'),
        }
    }
    go(node, &mut out);
    out
}

/// DFS stack extents (sum of resolved child sizes) from a summary — fed to
/// the next layout so `ratio` props land as pixels.
fn stack_extents(node: &SemNode, out: &mut Vec<f32>) {
    if let SemNode::Stack { sizes, kids, .. } = node {
        out.push(sizes.iter().copied().sum());
        for kid in kids {
            stack_extents(kid, out);
        }
    }
}

fn tab_of(state: &PanelState) -> Option<i64> {
    if let PanelInfo::Panel(info) = &state.info {
        info.get("tab").and_then(serde_json::Value::as_i64)
    } else {
        None
    }
}

fn summarize(state: &PanelState) -> SemNode {
    match &state.info {
        PanelInfo::Stack { sizes, axis } => SemNode::Stack {
            axis: if *axis == 0 {
                Axis::Horizontal
            } else {
                Axis::Vertical
            },
            sizes: sizes.iter().map(|p| f32::from(*p)).collect(),
            kids: state.children.iter().map(summarize).collect(),
        },
        PanelInfo::Tabs { active_index } => {
            let tabs: Vec<i64> = state.children.iter().filter_map(tab_of).collect();
            SemNode::Tabs {
                active: tabs.get(*active_index).copied(),
                tabs,
            }
        }
        // Bare panel leaf: treat as a single-tab group.
        PanelInfo::Panel(_) => SemNode::Tabs {
            tabs: tab_of(state).into_iter().collect(),
            active: tab_of(state),
        },
    }
}

fn panel_for(
    shared: &Shared,
    panels: &mut HashMap<i64, Entity<LuiPanel>>,
    tab_node: i64,
    cx: &mut Context<LuiNodeView>,
) -> Entity<LuiPanel> {
    if let Some(panel) = panels.get(&tab_node) {
        return panel.clone();
    }
    let panel = cx.new(|cx| LuiPanel {
        shared: shared.clone(),
        tab_node,
        focus: cx.focus_handle(),
    });
    panels.insert(tab_node, panel.clone());
    panel
}

/// Lower one `split-pane`/`split-branch` node into a `DockLayout`. `extents`
/// carries DFS-ordered stack extents from the previous summary so `ratio`
/// resolves to pixels once the dock has been measured; before that (or after
/// a shape change) slots stay `None` and the split flexes evenly.
fn layout_for(
    shared: &Shared,
    node: &NodeSnapshot,
    panels: &mut HashMap<i64, Entity<LuiPanel>>,
    extents: &[f32],
    extent_ix: &mut usize,
    cx: &mut Context<LuiNodeView>,
) -> DockLayout {
    match identifier(node) {
        "split-branch" => {
            let horizontal = ext_of(node, "orientation").as_deref() == Some("horizontal");
            let mut layout = if horizontal {
                DockLayout::h_split()
            } else {
                DockLayout::v_split()
            };
            let ratio = node
                .extension_props
                .get("ratio")
                .and_then(|v| v.as_float())
                .unwrap_or(0.5) as f32;
            let extent = extents.get(*extent_ix).copied();
            *extent_ix += 1;
            for (ix, child_id) in node.children.iter().enumerate() {
                let Some(child) = snapshot_of(shared, *child_id) else {
                    continue;
                };
                let size = match (ix, extent) {
                    (0, Some(extent)) => Some(px(ratio * extent)),
                    _ => None,
                };
                layout = layout.child(
                    layout_for(shared, &child, panels, extents, extent_ix, cx),
                    size,
                );
            }
            layout
        }
        _ => {
            // `split-pane` (and any fallback leaf): a tab group.
            let selected = ext_of(node, "selected");
            let mut layout = DockLayout::tabs();
            let mut active = 0;
            for (ix, child_id) in node.children.iter().enumerate() {
                let Some(tab) = snapshot_of(shared, *child_id) else {
                    continue;
                };
                if identifier(&tab) == "split-tab" {
                    if ext_of(&tab, "tab-id") == selected {
                        active = ix;
                    }
                    let panel = panel_for(shared, panels, *child_id, cx);
                    // `panel()` stores the bare entity; `panel_handle` wraps
                    // it so the tab bar recovers `title()` instead of
                    // falling back to `panel_name`.
                    layout = layout.panel_view(gpui_kit::component::dock::panel_handle(panel), cx);
                }
            }
            layout.active_index(active)
        }
    }
}

fn collect_tab_nodes(shared: &Shared, node: &NodeSnapshot, out: &mut HashSet<i64>) {
    if identifier(node) == "split-tab" {
        out.insert(node.id);
    }
    for child in &node.children {
        if let Some(child) = snapshot_of(shared, *child) {
            collect_tab_nodes(shared, &child, out);
        }
    }
}

fn build_layout(
    shared: &Shared,
    node: &NodeSnapshot,
    panels: &mut HashMap<i64, Entity<LuiPanel>>,
    extents: &[f32],
    cx: &mut Context<LuiNodeView>,
) -> DockLayout {
    let mut extent_ix = 0;
    let layout = match node
        .children
        .first()
        .and_then(|id| snapshot_of(shared, *id))
    {
        Some(child) => layout_for(shared, &child, panels, extents, &mut extent_ix, cx),
        None => DockLayout::tabs(),
    };
    // Panels for tabs that left the model tree are dropped.
    let mut used: HashSet<i64> = HashSet::new();
    collect_tab_nodes(shared, node, &mut used);
    panels.retain(|id, _| used.contains(id));
    layout
}

/// `split-view` extension renderer — the node mounts a `DockArea` and every
/// later render re-syncs the described center layout on signature change.
pub fn split_view(
    view: &mut LuiNodeView,
    node: &NodeSnapshot,
    window: &mut Window,
    cx: &mut Context<LuiNodeView>,
) -> AnyElement {
    if view.states.dock.is_none() {
        let (area, _skin) = DockSkin::dock_area(format!("lui-split-{}", node.id), None, window, cx);
        let subscription = cx.subscribe(&area, |view, _area, event, cx| {
            if matches!(event, DockEvent::LayoutChanged) {
                on_layout_changed(view, cx);
            }
        });
        view.states.subscriptions.push(subscription);
        view.states.dock = Some(DockSync {
            area,
            signature: String::new(),
            summary: None,
            panels: HashMap::new(),
        });
    }

    let shared = view.shared.clone();
    let signature = signature(&shared, node);
    let sync = view.states.dock.as_mut().unwrap();
    if signature != sync.signature {
        // Reuse measured extents only when the shape is unchanged; a
        // structural edit gets fresh even flex instead of shifted pixels.
        let mut extents = Vec::new();
        if let Some(summary) = &sync.summary {
            if sem_shape(summary) == shape(&shared, node) {
                stack_extents(summary, &mut extents);
            }
        }
        let layout = build_layout(&shared, node, &mut sync.panels, &extents, cx);
        sync.signature = signature;
        let area = sync.area.clone();
        area.update(cx, |dock, cx| dock.set_center(layout, window, cx));
        let dump = area.read(cx).dump(cx);
        sync.summary = Some(summarize(&dump.center));
    }
    let area = sync.area.clone();
    // The dock is embedded in LUI's content-sized column layout — give it a
    // concrete height so panes don't collapse to zero.
    div().w_full().h(px(300.)).child(area).into_any_element()
}

// ---- DockEvent::LayoutChanged → granular model events ----

struct DockEvt {
    node: i64,
    identifier: &'static CStr,
    name: &'static CStr,
    values: String,
}

fn on_layout_changed(view: &mut LuiNodeView, cx: &mut Context<LuiNodeView>) {
    let Some(sync) = view.states.dock.as_mut() else {
        return;
    };
    let dump = sync.area.read(cx).dump(cx);
    let new_summary = summarize(&dump.center);
    let Some(old_summary) = sync.summary.replace(new_summary.clone()) else {
        return;
    };
    if old_summary == new_summary {
        return;
    }
    let shared = view.shared.clone();
    for event in diff(&old_summary, &new_summary, &shared, view.id) {
        fire_extension(
            &shared,
            event.node,
            event.identifier,
            event.name,
            event.values,
            cx,
        );
    }
}

fn tabs_nodes(node: &SemNode) -> Vec<&SemNode> {
    fn go<'a>(node: &'a SemNode, path: &mut Vec<usize>, out: &mut Vec<(Vec<usize>, &'a SemNode)>) {
        match node {
            SemNode::Tabs { .. } => out.push((path.clone(), node)),
            SemNode::Stack { kids, .. } => {
                for (ix, kid) in kids.iter().enumerate() {
                    path.push(ix);
                    go(kid, path, out);
                    path.pop();
                }
            }
        }
    }
    let mut out = Vec::new();
    go(node, &mut Vec::new(), &mut out);
    out.into_iter().map(|(_, node)| node).collect()
}

fn tabs_with_paths(node: &SemNode) -> Vec<(Vec<usize>, &SemNode)> {
    fn go<'a>(node: &'a SemNode, path: &mut Vec<usize>, out: &mut Vec<(Vec<usize>, &'a SemNode)>) {
        match node {
            SemNode::Tabs { .. } => out.push((path.clone(), node)),
            SemNode::Stack { kids, .. } => {
                for (ix, kid) in kids.iter().enumerate() {
                    path.push(ix);
                    go(kid, path, out);
                    path.pop();
                }
            }
        }
    }
    let mut out = Vec::new();
    go(node, &mut Vec::new(), &mut out);
    out
}

fn tab_ids(node: &SemNode) -> &Vec<i64> {
    match node {
        SemNode::Tabs { tabs, .. } => tabs,
        _ => unreachable!("tabs_with_paths only yields Tabs"),
    }
}

fn active_of(node: &SemNode) -> Option<i64> {
    match node {
        SemNode::Tabs { active, .. } => *active,
        _ => None,
    }
}

fn all_tab_ids(node: &SemNode) -> BTreeSet<i64> {
    let mut out = BTreeSet::new();
    fn go(node: &SemNode, out: &mut BTreeSet<i64>) {
        match node {
            SemNode::Tabs { tabs, .. } => out.extend(tabs.iter().copied()),
            SemNode::Stack { kids, .. } => kids.iter().for_each(|k| go(k, out)),
        }
    }
    go(node, &mut out);
    out
}

/// The `split-pane` node a tab currently hangs under in the LUI store (the
/// model's tree — stale relative to the dock's, which is what we want: it
/// names the pane the model still believes owns the tab).
fn pane_node_of(store: &Store, tab_node: i64) -> Option<i64> {
    store.node(tab_node).and_then(|n| n.parent)
}

fn pane_id_of(shared: &Shared, pane_node: i64) -> String {
    ext_str(shared, pane_node, "pane-id").unwrap_or_default()
}

fn tab_id_of(shared: &Shared, tab_node: i64) -> String {
    ext_str(shared, tab_node, "tab-id").unwrap_or_default()
}

/// The pane a dock tab group represents: the model-side parent of a tab that
/// already lived there (a tab the new node shares with the old one — moved-in
/// tabs still name their old pane in the store).
fn resident_pane(old_tabs: &SemNode, new_tabs: &SemNode, shared: &Shared) -> Option<i64> {
    let store = &shared.borrow().store;
    let new_set: BTreeSet<i64> = tab_ids(new_tabs).iter().copied().collect();
    tab_ids(old_tabs)
        .iter()
        .copied()
        .filter(|tab| new_set.contains(tab))
        .find_map(|tab| pane_node_of(store, tab))
}

fn json_escape(text: &str) -> String {
    serde_json::to_string(text).unwrap_or_else(|_| "\"\"".into())
}

/// Two semantically-equal trees may still differ in stack sizes — each such
/// stack maps to a `split-branch` ratio change. `root` is the `split-view`
/// node id whose `split-branch` descendants pair with stacks in DFS order.
fn ratio_events(old: &SemNode, new: &SemNode, shared: &Shared, root: i64, out: &mut Vec<DockEvt>) {
    fn stacks<'a>(node: &'a SemNode, out: &mut Vec<&'a SemNode>) {
        if let SemNode::Stack { kids, .. } = node {
            out.push(node);
            for kid in kids {
                stacks(kid, out);
            }
        }
    }
    fn branches(shared: &Shared, id: i64, out: &mut Vec<i64>) {
        let Some(node) = snapshot_of(shared, id) else {
            return;
        };
        if identifier(&node) == "split-branch" {
            out.push(id);
        }
        for child in &node.children {
            branches(shared, *child, out);
        }
    }
    if sem_shape(old) != sem_shape(new) {
        return;
    }
    let mut old_stacks = Vec::new();
    stacks(old, &mut old_stacks);
    let mut new_stacks = Vec::new();
    stacks(new, &mut new_stacks);
    if old_stacks.len() != new_stacks.len() {
        return;
    }
    let mut branch_nodes = Vec::new();
    branches(shared, root, &mut branch_nodes);
    for (ix, (old_stack, new_stack)) in old_stacks.iter().zip(&new_stacks).enumerate() {
        let (
            SemNode::Stack {
                sizes: old_sizes, ..
            },
            SemNode::Stack {
                sizes: new_sizes, ..
            },
        ) = (old_stack, new_stack)
        else {
            continue;
        };
        if old_sizes == new_sizes || new_sizes.len() != 2 {
            continue;
        }
        let total = new_sizes[0] + new_sizes[1];
        if total <= 0. {
            continue;
        }
        let Some(branch) = branch_nodes.get(ix).copied() else {
            continue;
        };
        out.push(DockEvt {
            node: branch,
            identifier: c"split-branch",
            name: c"ratio-changed",
            values: format!("{{\"ratio\":{}}}", new_sizes[0] / total),
        });
    }
}

/// Child of `path[..-1]` — walk the summary to the parent stack, returning
/// (axis, index-of-node-in-parent, sibling subtree).
fn parent_slot<'a>(root: &'a SemNode, path: &[usize]) -> Option<(Axis, usize, &'a SemNode)> {
    let mut node = root;
    for &step in &path[..path.len().saturating_sub(1)] {
        let SemNode::Stack { kids, .. } = node else {
            return None;
        };
        node = kids.get(step)?;
    }
    let SemNode::Stack { axis, kids, .. } = node else {
        return None;
    };
    let ix = *path.last()?;
    kids.iter()
        .enumerate()
        .find_map(|(i, kid)| (i != ix).then_some((*axis, ix, kid)))
}

fn diff(old: &SemNode, new: &SemNode, shared: &Shared, root: i64) -> Vec<DockEvt> {
    let mut events = Vec::new();
    let old_tabs = tabs_nodes(old);
    let new_tabs = tabs_with_paths(new);
    let new_all = all_tab_ids(new);

    // Match new groups to old groups by maximum shared-tab overlap.
    let mut matched_old: HashSet<usize> = HashSet::new();
    let mut pairs: Vec<(usize, usize)> = Vec::new();
    let mut unmatched_new: Vec<usize> = Vec::new();
    for (ni, (_, nt)) in new_tabs.iter().enumerate() {
        let best = old_tabs
            .iter()
            .enumerate()
            .filter(|(oi, _)| !matched_old.contains(oi))
            .map(|(oi, ot)| {
                let shared_count = tab_ids(ot)
                    .iter()
                    .filter(|t| tab_ids(nt).contains(t))
                    .count();
                (oi, shared_count)
            })
            .filter(|(_, count)| *count > 0)
            .max_by_key(|(_, count)| *count);
        match best {
            Some((oi, _)) => {
                matched_old.insert(oi);
                pairs.push((oi, ni));
            }
            None => unmatched_new.push(ni),
        }
    }

    for (oi, ni) in &pairs {
        let ot = old_tabs[*oi];
        let (_, nt) = new_tabs[*ni];
        let Some(pane_node) = resident_pane(ot, nt, shared) else {
            continue;
        };
        // Tab moved in from elsewhere.
        for tab in tab_ids(nt) {
            if !tab_ids(ot).contains(tab) {
                let from_pane = pane_node_of(&shared.borrow().store, *tab)
                    .map(|p| pane_id_of(shared, p))
                    .unwrap_or_default();
                events.push(DockEvt {
                    node: pane_node,
                    identifier: c"split-pane",
                    name: c"tab-moved",
                    values: format!(
                        "{{\"tab\":{},\"index\":{},\"from-pane\":{}}}",
                        json_escape(&tab_id_of(shared, *tab)),
                        tab_ids(nt).iter().position(|t| t == tab).unwrap_or(0),
                        json_escape(&from_pane),
                    ),
                });
            }
        }
        // Tab closed outright (present in old group, nowhere in the tree).
        for tab in tab_ids(ot) {
            if !new_all.contains(tab) {
                events.push(DockEvt {
                    node: pane_node,
                    identifier: c"split-pane",
                    name: c"tab-closed",
                    values: format!("{{\"tab\":{}}}", json_escape(&tab_id_of(shared, *tab))),
                });
            }
        }
        // Selection changed on an unchanged tab set.
        if active_of(nt).is_some() && active_of(nt) != active_of(ot) {
            events.push(DockEvt {
                node: pane_node,
                identifier: c"split-pane",
                name: c"tab-selected",
                values: format!(
                    "{{\"tab\":{}}}",
                    json_escape(&tab_id_of(shared, active_of(nt).unwrap()))
                ),
            });
        }
    }

    // All-new groups come from edge-drop splits: the dragged tab(s) landed
    // beside a sibling subtree — the target pane — under a new split.
    for ni in unmatched_new {
        let (path, nt) = &new_tabs[ni];
        let Some((axis, ix, sibling)) = parent_slot(new, path) else {
            continue;
        };
        // A tab of the sibling subtree still parented to its model pane names
        // the drop target.
        let store = &shared.borrow().store;
        let Some(target_pane) = all_tab_ids(sibling)
            .iter()
            .find_map(|t| pane_node_of(store, *t))
        else {
            continue;
        };
        let edge = match (axis, ix) {
            (Axis::Horizontal, 0) => "left",
            (Axis::Horizontal, _) => "right",
            (Axis::Vertical, 0) => "top",
            (Axis::Vertical, _) => "bottom",
        };
        for tab in tab_ids(nt) {
            let from_pane = pane_node_of(store, *tab)
                .map(|p| pane_id_of(shared, p))
                .unwrap_or_default();
            events.push(DockEvt {
                node: target_pane,
                identifier: c"split-pane",
                name: c"split-drop",
                values: format!(
                    "{{\"tab\":{},\"from-pane\":{},\"edge\":{}}}",
                    json_escape(&tab_id_of(shared, *tab)),
                    json_escape(&from_pane),
                    json_escape(edge),
                ),
            });
        }
    }

    // An old group that no longer matches anything and lost every tab — the
    // pane itself is gone.
    for (oi, ot) in old_tabs.iter().enumerate() {
        if matched_old.contains(&oi) {
            continue;
        }
        if tab_ids(ot).iter().all(|t| !new_all.contains(t)) {
            if let Some(pane_node) = tab_ids(ot)
                .first()
                .and_then(|t| pane_node_of(&shared.borrow().store, *t))
            {
                events.push(DockEvt {
                    node: pane_node,
                    identifier: c"split-pane",
                    name: c"pane-closed",
                    values: "{}".into(),
                });
            }
        }
    }

    ratio_events(old, new, shared, root, &mut events);
    events
}
