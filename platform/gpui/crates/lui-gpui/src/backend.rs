//! Backend driver: wire batches -> store -> notify exactly the dirty views.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use gpui_kit::gpui::{App, AppContext, Bounds, Entity, FocusHandle, Pixels, Window};
use lui_core::bridge;
use lui_core::extension::{ExtensionRegistry, ExtensionSpec};
use lui_core::store::{Applied, BackendError, Store};
use lui_core::wire::{decode_batch, DecodeError, Op};
use lui_core::EventKind;

use crate::extension::ExtensionRenderer;
use crate::node_view::LuiNodeView;

/// Everything every node view needs, shared behind one `Rc<RefCell<_>>`.
/// Mutations happen only inside [`apply_batch_json`]; renders only read.
pub struct LuiShared {
    pub store: Store,
    /// Registered extension specs (`gpui-*` namespace + app extensions).
    pub registry: ExtensionRegistry,
    /// Specialized visual renderers per extension identifier.
    pub extension_renderers: HashMap<String, ExtensionRenderer>,
    /// Host hook resolving `app:<name>` icon names to full SVG markup
    /// (viewBox + children) when the name isn't a built-in IconName.
    /// Apps register their icon set (e.g. tabler) here; the `icon`
    /// kind rasterizes the SVG through the window's svg renderer.
    pub app_icon_svg: Option<Rc<dyn Fn(&str) -> Option<String>>>,
    /// node id -> view entity. Created lazily on first dirty/render touch,
    /// released on `drop-node` (GPUI then reclaims the view).
    pub views: HashMap<i64, Entity<LuiNodeView>>,
    /// Errors from the most recent batch applications (surfaced to the host).
    pub last_errors: Vec<String>,
    /// Most recently prepainted window-space bounds per node id, fed by
    /// each node's layout element. The `measure-node` dom-op reads
    /// this; entries are removed when a node drops.
    pub node_bounds: HashMap<i64, Bounds<Pixels>>,
    pub(crate) virtual_lists: HashMap<i64, crate::virtual_list::State>,
    pub(crate) painting_lists: Vec<i64>,
    /// Nodes that opted into a viewport-proximity dom-event through
    /// `events` (`lazy-mount` rows, `virt-end` list tails — the LUI
    /// native lazy contract). The per-frame sweep in `dom.rs` fires the
    /// event once the node's recorded bounds reach the viewport.
    pub viewport_watched: HashMap<i64, ViewportWatch>,
    /// Last `click` dom-event emission (target node, instant). The wired
    /// `on_click` handler and the root-level mouse-up monitor can both
    /// report the same click in one frame — emissions for the same
    /// target inside this window are dropped, mirroring OCaml's 60ms
    /// event coalescing so hosts see one event per click.
    pub last_click_emit: Option<(i64, std::time::Instant)>,
    /// Focusable element registry: node id -> the FocusHandle its
    /// rendered element tracks. The root-level keydown forwarder
    /// resolves `document.activeElement` parity through this — the
    /// dom-event's target must be the focused element's node so OCaml
    /// dispatch can route editing vs. browse mode. Entries whose node
    /// dropped are pruned on lookup.
    pub focus_nodes: Vec<(i64, FocusHandle)>,
}

/// A registered viewport-proximity watch: which dom-event to fire and
/// under which extension identifier (`dom_event` needs both).
pub struct ViewportWatch {
    pub event: &'static str,
    pub identifier: String,
    /// `virt-end` refires only when the list's last child changes
    /// (pagination appended a new tail).
    pub last_end_child: Option<i64>,
    /// `lazy-mount`: the `data-lazy-mount` uuid the OCaml latch is
    /// keyed on — hits batch per parent into a single dom-event.
    pub lazy_uuid: String,
}

pub type Shared = Rc<RefCell<LuiShared>>;

impl LuiShared {
    pub fn new() -> Shared {
        let shared = Rc::new(RefCell::new(LuiShared {
            store: Store::default(),
            registry: ExtensionRegistry::default(),
            extension_renderers: HashMap::new(),
            app_icon_svg: None,
            views: HashMap::new(),
            last_errors: Vec::new(),
            node_bounds: HashMap::new(),
            virtual_lists: HashMap::new(),
            painting_lists: Vec::new(),
            viewport_watched: HashMap::new(),
            last_click_emit: None,
            focus_nodes: Vec::new(),
        }));
        crate::extension::register_builtin_renderers(&shared);
        shared
    }

    pub fn with_extensions(
        self_: Shared,
        specs: impl IntoIterator<Item = ExtensionSpec>,
    ) -> Shared {
        {
            let mut shared = self_.borrow_mut();
            for spec in specs {
                shared.registry.register(spec);
            }
        }
        self_
    }

    /// Entity for `id`, creating it on demand. Every LUI node gets exactly
    /// one entity for its whole lifetime — the unit of minimal re-render.
    pub fn view_for(shared: &Shared, id: i64, cx: &mut App) -> Entity<LuiNodeView> {
        if let Some(view) = shared.borrow().views.get(&id) {
            return view.clone();
        }
        let view = cx.new(|_cx| LuiNodeView::new(id, shared.clone()));
        shared.borrow_mut().views.insert(id, view.clone());
        view
    }

    /// Register the FocusHandle a node's rendered element tracks so the
    /// root keydown forwarder can resolve the focused element's node.
    pub fn register_focus(&mut self, node_id: i64, handle: FocusHandle) {
        self.focus_nodes.retain(|(id, _)| *id != node_id);
        self.focus_nodes.push((node_id, handle));
    }

    /// The node whose element currently holds window focus, if any
    /// registered one does (prunes entries for dropped nodes).
    pub fn focused_node(&mut self, window: &Window) -> Option<i64> {
        let store = &self.store;
        self.focus_nodes.retain(|(id, _)| store.node(*id).is_some());
        self.focus_nodes
            .iter()
            .find(|(_, h)| h.is_focused(window))
            .map(|(id, _)| *id)
    }
}

#[derive(Debug)]
pub enum ApplyError {
    Decode(DecodeError),
    Backend(BackendError),
}

impl std::fmt::Display for ApplyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApplyError::Decode(error) => write!(f, "decode: {error}"),
            ApplyError::Backend(error) => write!(f, "backend: {error}"),
        }
    }
}

impl std::error::Error for ApplyError {}

/// Apply one JSON patch batch: commit to the store, drop released views, then
/// notify changed entities without acquiring update leases. Content-sized
/// ancestors still participate in layout.
pub fn apply_batch_json(shared: &Shared, json: &str, cx: &mut App) -> Result<Applied, ApplyError> {
    if std::env::var("LUI_GPUI_DUMP_BATCHES").is_ok() {
        use std::io::Write;
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open("/tmp/lui-batches.jsonl")
        {
            let _ = f.write_all(json.as_bytes());
            let _ = f.write_all(b"\n");
        }
    }
    let batch = decode_batch(json).map_err(ApplyError::Decode)?;
    let applied = {
        let mut shared_ref = shared.borrow_mut();
        shared_ref
            .store
            .apply(&batch)
            .map_err(ApplyError::Backend)?
    };

    // Release entities for dropped subtrees first: a fresh node id reuse is
    // impossible (ids are monotonic), so removal order is safe.
    for id in &applied.dropped {
        let mut shared_ref = shared.borrow_mut();
        shared_ref.views.remove(id);
        shared_ref.node_bounds.remove(id);
        shared_ref.viewport_watched.remove(id);
        shared_ref.virtual_lists.remove(id);
    }

    {
        let mut guard = shared.borrow_mut();
        for id in &applied.structural {
            if let Some(list) = guard.virtual_lists.get_mut(id) {
                list.children_dirty = true;
            }
        }
        for op in &batch.ops {
            let id = match op {
                Op::SetProp { id, .. }
                | Op::RemoveProp { id, .. }
                | Op::SetExtensionProp { id, .. }
                | Op::RemoveExtensionProp { id, .. } => id,
                _ => continue,
            };
            if let Some(list) = guard.virtual_lists.get(id) {
                list.state.remeasure();
            }
        }
    }

    let mut dirty_views = Vec::with_capacity(applied.dirty.len());
    let mut notified = std::collections::BTreeSet::new();
    for &id in &applied.dirty {
        // A changed descendant can change a row's measured height. Invalidate
        // the containing list without reading/updating its leased view entity.
        {
            let guard = shared.borrow();
            let mut child = id;
            while let Some(parent) = guard.store.node(child).and_then(|node| node.parent) {
                if let Some(list) = guard.virtual_lists.get(&parent) {
                    if let Some(&index) = list.indices.get(&child) {
                        list.state.remeasure_items(index..index + 1);
                    }
                    if let Some(view) = guard.views.get(&parent) {
                        cx.notify(view.entity_id());
                    }
                }
                child = parent;
            }
        }
        // Notify the nearest ancestor (self included) whose view has
        // actually painted (an entry in node_bounds). `views` also holds
        // entities created for nodes that never made it into a rendered
        // frame — notifying those is a no-op, so keep walking past them.
        let mut current = Some(id);
        let mut visited = std::collections::BTreeSet::new();
        while let Some(nid) = current {
            let mounted = {
                let guard = shared.borrow();
                guard.views.contains_key(&nid)
                    && (guard.node_bounds.contains_key(&nid)
                        || guard.store.root == Some(nid))
            };
            if mounted {
                if notified.insert(nid) {
                    dirty_views.push(LuiShared::view_for(shared, nid, cx));
                }
                break;
            }
            if !visited.insert(nid) {
                break; // parent cycle — never walk twice
            }
            current = shared
                .borrow()
                .store
                .node(nid)
                .and_then(|node| node.parent);
        }
    }
    for view in dirty_views {
        cx.notify(view.entity_id());
    }
    Ok(applied)
}

/// Apply a patch payload that may be either one batch object `{ops:[…]}`
/// or the stream form `[batch, batch, …]` (what `take_patches` returns in
/// hosts that fold event results into the sink).
pub fn apply_stream_json(shared: &Shared, json: &str, cx: &mut App) {
    let parsed = serde_json::from_str::<serde_json::Value>(json);
    match parsed {
        Ok(serde_json::Value::Array(batches)) => {
            for batch in batches {
                let batch = batch.to_string();
                if let Err(error) = apply_batch_json(shared, &batch, cx) {
                    let message = error.to_string();
                    eprintln!("lui-gpui: rejected batch: {message}");
                    shared.borrow_mut().last_errors.push(message);
                }
            }
        }
        Ok(_) => {
            if let Err(error) = apply_batch_json(shared, json, cx) {
                let message = error.to_string();
                eprintln!("lui-gpui: rejected batch: {message}");
                shared.borrow_mut().last_errors.push(message);
            }
        }
        Err(error) => {
            let message = format!("decode: {error}");
            eprintln!("lui-gpui: rejected batch: {message}");
            shared.borrow_mut().last_errors.push(message);
        }
    }
}

/// Drain every queued batch from the OCaml bridge and apply it. Call after
/// `lui_ocaml_start` and after each `lui_ocaml_*` event returns — each call
/// synchronously pushed the next batch into the queue.
pub fn drain_pending(shared: &Shared, cx: &mut App) {
    for json in bridge::take_patches() {
        apply_stream_json(shared, &json, cx);
    }
}

/// Fire one host→OCaml event: gate check, bridge call, drain + apply.
/// `call` performs the `unsafe` FFI entry-point call and returns `accepted`.
///
/// Always call through here — direct `lui_ocaml_*` calls without draining
/// leave the store stale.
pub fn fire<F>(shared: &Shared, node_id: i64, event: EventKind, cx: &mut App, call: F) -> i32
where
    F: FnOnce() -> i32,
{
    let allowed = {
        let shared_ref = shared.borrow();
        shared_ref
            .store
            .node(node_id)
            .map(|node| lui_core::event_allowed(node, event))
            .unwrap_or(false)
    };
    if !allowed {
        return 0;
    }
    let accepted = call();
    drain_pending(shared, cx);
    accepted
}
