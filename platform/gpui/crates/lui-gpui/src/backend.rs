//! Backend driver: wire batches -> store -> notify exactly the dirty views.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use gpui_kit::gpui::{App, AppContext, Bounds, Entity, Pixels};
use lui_core::bridge;
use lui_core::extension::{ExtensionRegistry, ExtensionSpec};
use lui_core::store::{Applied, BackendError, Store};
use lui_core::wire::{decode_batch, DecodeError};
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
    /// `LuiNodeView::bounds_recorder`. The `measure-node` dom-op reads
    /// this; entries are removed when a node drops.
    pub node_bounds: HashMap<i64, Bounds<Pixels>>,
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
/// notify exactly the entities whose node changed. This is the only place
/// views are notified — rendering is always per-dirty-node.
pub fn apply_batch_json(shared: &Shared, json: &str, cx: &mut App) -> Result<Applied, ApplyError> {
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
    }

    let mut dirty_views = Vec::with_capacity(applied.dirty.len());
    for &id in &applied.dirty {
        // Only notify views for nodes that still exist and are mounted
        // (a brand-new node is picked up by its parent's render).
        if shared.borrow().store.node(id).is_none() {
            continue;
        }
        dirty_views.push(LuiShared::view_for(shared, id, cx));
    }
    for view in dirty_views {
        view.update(cx, |_, cx| cx.notify());
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
