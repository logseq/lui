//! Backend driver: wire batches -> store -> notify exactly the dirty views.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use gpui_kit::gpui::{
    App, AppContext, Bounds, Entity, EntityId, FocusHandle, Pixels, Point, ScrollHandle, Window,
};
use lui_core::bridge;
use lui_core::extension::{ExtensionRegistry, ExtensionSpec};
use lui_core::store::{Applied, BackendError, Store};
use lui_core::wire::{decode_batch, decode_batch_value, Batch, DecodeError, Op};
use lui_core::EventKind;

use crate::extension::ExtensionRenderer;
use crate::node_view::{LuiNodeView, NodeSnapshot};

/// Everything every node view needs, shared behind one `Rc<RefCell<_>>`.
/// Mutations happen only inside [`apply_batch_json`]; renders only read.
pub struct LuiShared {
    pub store: Store,
    /// Removed popup trees remain visual-only until their exit completes.
    pub(crate) closing_nodes: HashMap<i64, NodeSnapshot>,
    pub(crate) closing_roots: Vec<i64>,
    /// Root views own the rendering session; the last root releases entities.
    pub(crate) root_owners: usize,
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
    /// Text layouts actually prepainted by the renderer. Hosts use these
    /// glyph positions for carets and hit testing, including inherited styles.
    pub text_layouts: HashMap<i64, gpui_kit::gpui::TextLayout>,
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
    /// Open dismissible overlays, in open order (topmost last). Overlay
    /// render arms register themselves so a host-side Escape can close
    /// the topmost layer — the gpui counterpart of the web backend's
    /// `lui_web_layers` key handlers (`modal_key_handler`). Stale
    /// entries (node dropped, or host open-state cleared) are pruned
    /// when the stack is read.
    pub overlay_stack: Vec<(i64, OverlayEntry)>,
    /// Open toast node ids in mount order. Each toast renders its own
    /// window layer pinned top-right — stacking them needs the open
    /// order plus each toast's painted height (toasts that arrived
    /// earlier sit above later ones).
    pub toasts: Vec<i64>,
    /// Painted surface height per open toast id — read to compute the
    /// vertical offset of every toast below it.
    pub toast_heights: HashMap<i64, f32>,
    /// Window-space bounds per open toast id, corrected out of the
    /// deferred layer's pre-offset prepaint space — hover-pause and
    /// swipe hit-testing (element events never reach the deferred layer).
    pub toast_bounds: HashMap<i64, Bounds<Pixels>>,
    /// Toast swipe-to-dismiss in flight: (toast id, press point).
    pub toast_drag: Option<(i64, Point<Pixels>)>,
    /// Toast ids the pointer rests on — auto-dismiss budgets stop
    /// ticking while hovered (web: pause on interaction).
    pub toast_paused: std::collections::HashSet<i64>,
    /// Milliseconds until each open toast auto-dismisses — a spawned
    /// timer task decrements it and fires `Dismiss` at zero.
    pub toast_remaining_ms: HashMap<i64, f64>,
    /// Toast ids with a running auto-dismiss timer task — guards
    /// re-registration across re-renders.
    pub toast_timers: std::collections::HashSet<i64>,
    /// Keyboard-highlighted menu item — roving focus for arrow-key
    /// navigation inside open menus (web menu keyboard parity).
    pub menu_highlight: Option<i64>,
    /// OCaml imperative-DOM overlay roots (`imperative-attach` dom-op),
    /// in attach order — body-appended floaters (pickers, property
    /// popups) materialize as orphaned `logseq-*` nodes that the root
    /// view mounts in a window-level deferred layer above declarative
    /// popups, so they paint over the surface that spawned them.
    pub imperative_roots: Vec<i64>,
    /// Entity of the `LuiRootView` hosting the imperative overlay
    /// layer — attach/detach ops notify it so the layer (un)mounts on
    /// the next frame. Registered from the root view's render.
    pub imperative_host_view: Option<EntityId>,
    /// Last imperative-subtree bounds frame reported to OCaml via the
    /// `imperative-rects` feed (node id -> l/t/r/b) — the feed diffs
    /// painted bounds against this map so unchanged frames stay quiet.
    pub imperative_rect_reported: HashMap<i64, (f32, f32, f32, f32)>,
    /// Effective `pointer-events` decision per painted node, resolved at
    /// prepaint (own explicit/implicit setting else the parent's effective
    /// value) — hit testing reads this map instead of walking ancestors
    /// and re-parsing `attrs`/`style-class` on every pointer event.
    pub hit_disabled: HashMap<i64, bool>,
    /// `scroll-token` values already consumed per list node — a repeated
    /// token (e.g. a re-render echo) is not a new scroll request.
    pub handled_scroll_tokens: HashMap<i64, i64>,
    /// `scroll-token` whose scroll was requested but not yet reported —
    /// waits for the target's bounds, then for one settled frame.
    pub pending_scrolls: HashMap<i64, crate::scroll::PendingScroll>,
    /// Last recorded scroll offset per scrollable container — gpui clamps
    /// offsets to a transiently-empty content size, so `scroll.rs` restores
    /// the last real offset once the content overflows again.
    pub scroll_offsets: HashMap<i64, gpui_kit::gpui::Pixels>,
    /// When each scrollable container last saw a wheel event — tells a
    /// genuine scroll-to-top apart from a clamp-to-zero reset.
    pub scroll_wheel_marks: HashMap<i64, std::time::Instant>,
    /// Last `visible_range` span reported per `track-visible-range` node.
    pub visible_ranges: HashMap<i64, (i64, i64)>,
    /// The ScrollHandle each scrollable container tracks, registered at
    /// render so scroll-request handling can drive it without touching
    /// the view entity.
    pub scroll_handles: HashMap<i64, ScrollHandle>,
    /// `image` nodes that already fired `load`.
    pub loaded_images: std::collections::HashSet<i64>,
}

/// How a host-side Escape closes one open overlay — pushed onto
/// [`LuiShared::overlay_stack`] by the render arm that owns the popup.
#[derive(Clone, Copy, Debug)]
pub enum OverlayEntry {
    /// Store-driven overlay (dialog/sheet/drawer/dropdown/popover): the
    /// node exists only while open, so Escape just fires `Dismiss` and
    /// the model drops it.
    Node,
    /// A list-item's right-click menu: `states.overlay` holds the open
    /// point; Escape clears it and fires `Dismiss` on the `context-menu`
    /// child, matching the popup's own press-outside path.
    ContextMenu,
    /// A menu-trigger's nested submenu: `states.menu_open` holds it;
    /// Escape clears it (and the owning menu's open-sub-menu slot) and
    /// fires `Dismiss` on the dropdown/context-menu child.
    Submenu,
    /// A tooltip bubble: `states.tooltip` holds it; Escape clears it —
    /// tooltips have no `Dismiss` event (web hides them host-side too).
    Tooltip,
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
            closing_nodes: HashMap::new(),
            closing_roots: Vec::new(),
            root_owners: 0,
            registry: ExtensionRegistry::default(),
            extension_renderers: HashMap::new(),
            app_icon_svg: None,
            views: HashMap::new(),
            last_errors: Vec::new(),
            node_bounds: HashMap::new(),
            text_layouts: HashMap::new(),
            virtual_lists: HashMap::new(),
            hit_disabled: HashMap::new(),
            handled_scroll_tokens: HashMap::new(),
            pending_scrolls: HashMap::new(),
            scroll_offsets: HashMap::new(),
            scroll_wheel_marks: HashMap::new(),
            visible_ranges: HashMap::new(),
            scroll_handles: HashMap::new(),
            loaded_images: std::collections::HashSet::new(),
            painting_lists: Vec::new(),
            viewport_watched: HashMap::new(),
            last_click_emit: None,
            focus_nodes: Vec::new(),
            overlay_stack: Vec::new(),
            toasts: Vec::new(),
            toast_heights: HashMap::new(),
            toast_bounds: HashMap::new(),
            toast_drag: None,
            toast_paused: std::collections::HashSet::new(),
            toast_remaining_ms: HashMap::new(),
            toast_timers: std::collections::HashSet::new(),
            menu_highlight: None,
            imperative_roots: Vec::new(),
            imperative_host_view: None,
            imperative_rect_reported: HashMap::new(),
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

    /// Drop the store mirror and every derived/render-side table — used
    /// before replaying a resync snapshot so no stale entity, overlay,
    /// focus, scroll, or hit-test state outlives the rebuilt tree.
    pub(crate) fn reset_render_state(&mut self) {
        self.store.reset();
        self.closing_nodes.clear();
        self.closing_roots.clear();
        self.views.clear();
        self.node_bounds.clear();
        self.text_layouts.clear();
        self.virtual_lists.clear();
        self.painting_lists.clear();
        self.hit_disabled.clear();
        self.handled_scroll_tokens.clear();
        self.pending_scrolls.clear();
        self.scroll_offsets.clear();
        self.scroll_wheel_marks.clear();
        self.visible_ranges.clear();
        self.scroll_handles.clear();
        self.loaded_images.clear();
        self.viewport_watched.clear();
        self.last_click_emit = None;
        self.focus_nodes.clear();
        self.overlay_stack.clear();
        self.toasts.clear();
        self.toast_heights.clear();
        self.toast_bounds.clear();
        self.toast_drag = None;
        self.toast_paused.clear();
        self.toast_remaining_ms.clear();
        self.toast_timers.clear();
        self.menu_highlight = None;
        self.imperative_roots.clear();
        self.imperative_rect_reported.clear();
    }

    /// Push `id` onto the open-overlay stack. An already-present entry
    /// keeps its position so re-renders never reorder the stack — order
    /// is always "first opened", and the topmost entry is the newest
    /// still-open overlay.
    pub fn push_overlay(&mut self, id: i64, entry: OverlayEntry) {
        if let Some(slot) = self
            .overlay_stack
            .iter_mut()
            .find(|(existing, _)| *existing == id)
        {
            *slot = (id, entry);
        } else {
            self.overlay_stack.push((id, entry));
        }
    }
}

/// Whether a stack entry's overlay is still open — the node must live,
/// and host-driven entries additionally check their owning view's open
/// state so closed popups prune themselves.
fn overlay_entry_open(shared: &Shared, id: i64, entry: OverlayEntry, cx: &App) -> bool {
    let shared = shared.borrow();
    if shared.store.node(id).is_none() {
        return false;
    }
    let Some(view) = shared.views.get(&id) else {
        return matches!(entry, OverlayEntry::Node);
    };
    let view = view.read(cx);
    match entry {
        OverlayEntry::Node => true,
        OverlayEntry::ContextMenu => view.states.overlay.get().is_some(),
        OverlayEntry::Submenu => view.states.menu_open.get(),
        OverlayEntry::Tooltip => view.states.tooltip.get(),
    }
}

/// Close the topmost open overlay for a host-side Escape — the gpui
/// counterpart of the web backend's modal/popup Escape handlers.
/// Prunes stale entries (closed popups keep their slot until read), then
/// dismisses the newest still-open entry: store-driven overlays get a
/// `Dismiss` event; host-driven open states are cleared on their view
/// first and then report `Dismiss` on their menu node, the same path
/// their press-outside handlers take. Returns whether an overlay was
/// dismissed.
pub fn dismiss_topmost_overlay(shared: &Shared, cx: &mut App) -> bool {
    let entry = loop {
        let top = shared.borrow().overlay_stack.last().copied();
        match top {
            Some((id, entry)) if overlay_entry_open(shared, id, entry, cx) => {
                break Some((id, entry));
            }
            Some(_) => {
                shared.borrow_mut().overlay_stack.pop();
            }
            None => break None,
        }
    };
    let Some((id, entry)) = entry else {
        return false;
    };
    match entry {
        OverlayEntry::Node => {
            fire(shared, id, EventKind::Dismiss, cx, || unsafe {
                bridge::lui_ocaml_dismiss(id)
            });
        }
        OverlayEntry::ContextMenu => {
            shared.borrow_mut().menu_highlight = None;
            if let Some(view) = shared.borrow().views.get(&id).cloned() {
                view.read(cx).states.overlay.set(None);
                cx.notify(view.entity_id());
            }
            // The `context-menu` child carries the Dismiss registration,
            // mirroring the popup's own press-outside handler.
            let menu_id = menu_child_id(shared, id);
            if let Some(menu_id) = menu_id {
                fire(shared, menu_id, EventKind::Dismiss, cx, || unsafe {
                    bridge::lui_ocaml_dismiss(menu_id)
                });
            }
        }
        OverlayEntry::Submenu => {
            // Clear the trigger's open flag plus the owning menu's
            // open-sub-menu slot, then Dismiss the menu child — the same
            // sequence the submenu's press-outside handler runs.
            let owner_slot = {
                let shared_ref = shared.borrow();
                shared_ref
                    .store
                    .node(id)
                    .and_then(|node| node.parent)
                    .and_then(|parent| shared_ref.views.get(&parent).cloned())
                    .map(|view| view.read(cx).states.open_submenu.clone())
            };
            if let Some(slot) = owner_slot {
                if slot.get() == Some(id) {
                    slot.set(None);
                }
            }
            if let Some(view) = shared.borrow().views.get(&id).cloned() {
                view.read(cx).states.menu_open.set(false);
                // The pointer may still rest on the trigger — disarm the
                // hover-open path until it leaves, like `close_host_menus`.
                view.read(cx).states.submenu_suppress.set(true);
                cx.notify(view.entity_id());
            }
            shared.borrow_mut().menu_highlight = None;
            let menu_id = menu_child_id(shared, id);
            if let Some(menu_id) = menu_id {
                fire(shared, menu_id, EventKind::Dismiss, cx, || unsafe {
                    bridge::lui_ocaml_dismiss(menu_id)
                });
            }
        }
        OverlayEntry::Tooltip => {
            if let Some(view) = shared.borrow().views.get(&id).cloned() {
                view.read(cx).states.tooltip.set(false);
                cx.notify(view.entity_id());
            }
        }
    }
    true
}

/// First `dropdown-menu`/`context-menu` child of `node_id` — the popup
/// menu a menu-trigger or context-menu host owns.
pub(crate) fn menu_child_id(shared: &Shared, node_id: i64) -> Option<i64> {
    let shared_ref = shared.borrow();
    shared_ref
        .store
        .node(node_id)
        .into_iter()
        .flat_map(|node| node.children.iter().copied())
        .find(|child| {
            matches!(
                shared_ref
                    .store
                    .node(*child)
                    .and_then(|n| n.identity.kind()),
                Some(lui_core::wire_schema::NodeKind::DropdownMenu)
                    | Some(lui_core::wire_schema::NodeKind::ContextMenu)
            )
        })
}

/// Topmost open menu for arrow-key navigation — its menu node id, plus
/// the menu-trigger id when it is a submenu (ArrowLeft collapses back
/// to the trigger). Scans the overlay stack newest-first: a non-menu
/// overlay (dialog, sheet) on top captures keys, so menus beneath it
/// are unreachable; tooltips float above without capturing. Returns
/// None when no menu is reachable.
pub(crate) fn topmost_menu(shared: &Shared, cx: &App) -> Option<(i64, Option<i64>)> {
    let stack: Vec<(i64, OverlayEntry)> = shared.borrow().overlay_stack.clone();
    for (id, entry) in stack.into_iter().rev() {
        if !overlay_entry_open(shared, id, entry, cx) {
            continue;
        }
        match entry {
            OverlayEntry::Tooltip => continue,
            OverlayEntry::Node => {
                let (kind, role) = {
                    let shared_ref = shared.borrow();
                    match shared_ref.store.node(id) {
                        Some(node) => (
                            node.identity.kind(),
                            node.string_prop(lui_core::wire_schema::Property::RoleValue)
                                .map(str::to_string),
                        ),
                        None => (None, None),
                    }
                };
                return match kind {
                    Some(lui_core::wire_schema::NodeKind::DropdownMenu)
                    | Some(lui_core::wire_schema::NodeKind::ContextMenu) => Some((id, None)),
                    // Model-owned popovers marked role=menu (context
                    // menus, dropdown lists) join keyboard nav too —
                    // their rows are `menu-item` nodes roving the same
                    // highlight.
                    Some(lui_core::wire_schema::NodeKind::Popover)
                        if role.as_deref() == Some("menu") =>
                    {
                        Some((id, None))
                    }
                    _ => None,
                };
            }
            OverlayEntry::ContextMenu => {
                return menu_child_id(shared, id).map(|menu_id| (menu_id, None));
            }
            OverlayEntry::Submenu => {
                return menu_child_id(shared, id).map(|menu_id| (menu_id, Some(id)));
            }
        }
    }
    None
}

/// Move the keyboard highlight to `id` — roving focus across menu
/// items — repainting the old and new highlighted rows.
pub(crate) fn set_menu_highlight(shared: &Shared, id: Option<i64>, cx: &mut App) {
    let entities = {
        let mut shared_ref = shared.borrow_mut();
        if shared_ref.menu_highlight == id {
            return;
        }
        let previous = shared_ref.menu_highlight;
        shared_ref.menu_highlight = id;
        // Entities to repaint: the previous and current items plus every
        // open menu's popup owner. Menu items inside the deferred popup
        // layer are not tracked by window invalidation (App::notify only
        // repaints tracked entities), so repainting the in-flow view that
        // builds the popup is what re-evaluates item `.when(highlight)`.
        let mut ids: Vec<i64> = [previous, id].into_iter().flatten().collect();
        for (owner, entry) in &shared_ref.overlay_stack {
            let owns_menu = match entry {
                OverlayEntry::Submenu | OverlayEntry::ContextMenu => true,
                OverlayEntry::Node => shared_ref
                    .store
                    .node(*owner)
                    .and_then(|n| n.identity.kind())
                    .is_some_and(|kind| {
                        matches!(
                            kind,
                            lui_core::wire_schema::NodeKind::DropdownMenu
                                | lui_core::wire_schema::NodeKind::ContextMenu
                        )
                    }),
                OverlayEntry::Tooltip => false,
            };
            if owns_menu {
                ids.push(*owner);
            }
        }
        ids.iter()
            .filter_map(|item| shared_ref.views.get(item).map(|v| v.entity_id()))
            .collect::<Vec<_>>()
    };
    for entity in entities {
        cx.notify(entity);
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
    apply_batch(shared, &batch, cx)
}

/// Apply one already-decoded batch: commit to the store, drop released
/// views, then notify changed entities without acquiring update leases.
/// Content-sized ancestors still participate in layout.
pub fn apply_batch(shared: &Shared, batch: &Batch, cx: &mut App) -> Result<Applied, ApplyError> {
    let closing = capture_closing_popups(shared, batch);
    let applied = {
        let mut shared_ref = shared.borrow_mut();
        shared_ref
            .store
            .apply(batch)
            .map_err(ApplyError::Backend)?
    };

    retain_closing_popups(shared, closing, &applied, cx);
    notify_applied(shared, batch, &applied, cx);
    Ok(applied)
}

/// Apply imperative host mutations without consuming a runtime generation.
pub(crate) fn apply_local_batch_json(
    shared: &Shared,
    json: &str,
    cx: &mut App,
) -> Result<Applied, ApplyError> {
    let batch = decode_batch(json).map_err(ApplyError::Decode)?;
    let closing = capture_closing_popups(shared, &batch);
    let applied = shared
        .borrow_mut()
        .store
        .apply_local(&batch.ops)
        .map_err(ApplyError::Backend)?;
    retain_closing_popups(shared, closing, &applied, cx);
    notify_applied(shared, &batch, &applied, cx);
    Ok(applied)
}

type ClosingPopup = (i64, Vec<NodeSnapshot>);

fn capture_closing_popups(shared: &Shared, batch: &Batch) -> Vec<ClosingPopup> {
    let guard = shared.borrow();
    let mut captured = std::collections::HashSet::new();
    let mut result = Vec::new();
    for operation in &batch.ops {
        let id = match operation {
            Op::DropNode { id } | Op::DetachSubtree { id } => *id,
            _ => continue,
        };
        let mut pending = vec![id];
        while let Some(id) = pending.pop() {
            if captured.contains(&id) {
                continue;
            }
            let Some(node) = guard.store.node(id) else {
                continue;
            };
            if node
                .identity
                .kind()
                .is_some_and(crate::kinds::animated_popup)
                && guard.node_bounds.contains_key(&id)
            {
                let mut nodes = Vec::new();
                let mut members = vec![id];
                while let Some(member) = members.pop() {
                    if !captured.insert(member) {
                        continue;
                    }
                    if let Some(snapshot) = NodeSnapshot::snapshot(&guard.store, member) {
                        members.extend(snapshot.children.iter().rev().copied());
                        nodes.push(snapshot);
                    }
                }
                result.push((id, nodes));
            } else {
                pending.extend(node.children.iter().rev().copied());
            }
        }
    }
    result
}

fn retain_closing_popups(
    shared: &Shared,
    closing: Vec<ClosingPopup>,
    applied: &Applied,
    cx: &mut App,
) {
    let dropped: std::collections::HashSet<_> = applied.dropped.iter().copied().collect();
    for (root, nodes) in closing {
        if !dropped.contains(&root) {
            continue;
        }
        let duration = crate::kinds::popup_duration(&nodes[0]);
        let mut members = Vec::new();
        {
            let mut guard = shared.borrow_mut();
            for mut node in nodes {
                if !dropped.contains(&node.id) {
                    continue;
                }
                node.children.retain(|id| dropped.contains(id));
                members.push(node.id);
                guard.closing_nodes.insert(node.id, node);
            }
            guard.closing_roots.push(root);
            if let Some(host) = guard.imperative_host_view {
                cx.notify(host);
            }
            if let Some(view) = guard.views.get(&root) {
                cx.notify(view.entity_id());
            }
        }
        let shared = shared.clone();
        cx.spawn(async move |cx| {
            cx.background_executor().timer(duration).await;
            let _ = cx.update(|cx| {
                let mut guard = shared.borrow_mut();
                guard.closing_roots.retain(|id| *id != root);
                let retired: std::collections::HashSet<_> = members.iter().copied().collect();
                guard.overlay_stack.retain(|(id, _)| !retired.contains(id));
                guard.focus_nodes.retain(|(id, _)| !retired.contains(id));
                for id in members {
                    guard.closing_nodes.remove(&id);
                    guard.views.remove(&id);
                    guard.node_bounds.remove(&id);
                    guard.text_layouts.remove(&id);
                    guard.virtual_lists.remove(&id);
                    guard.toast_heights.remove(&id);
                    guard.toast_bounds.remove(&id);
                }
                if let Some(host) = guard.imperative_host_view {
                    cx.notify(host);
                }
            });
        })
        .detach();
    }
}

fn notify_applied(shared: &Shared, batch: &Batch, applied: &Applied, cx: &mut App) {
    // Release entities for dropped subtrees first: a fresh node id reuse is
    // impossible (ids are monotonic), so removal order is safe.
    let mut cancelled_scrolls = Vec::new();
    for id in &applied.dropped {
        let mut shared_ref = shared.borrow_mut();
        let closing = shared_ref.closing_nodes.contains_key(id);
        if !closing {
            shared_ref.views.remove(id);
            shared_ref.node_bounds.remove(id);
            shared_ref.text_layouts.remove(id);
            shared_ref.toast_heights.remove(id);
            shared_ref.toast_bounds.remove(id);
            shared_ref.virtual_lists.remove(id);
            shared_ref.hit_disabled.remove(id);
            shared_ref.focus_nodes.retain(|(focus_id, _)| focus_id != id);
        }
        shared_ref.viewport_watched.remove(id);
        shared_ref.handled_scroll_tokens.remove(id);
        shared_ref.scroll_offsets.remove(id);
        shared_ref.scroll_wheel_marks.remove(id);
        shared_ref.visible_ranges.remove(id);
        shared_ref.scroll_handles.remove(id);
        shared_ref.loaded_images.remove(id);
        shared_ref.toasts.retain(|toast_id| *toast_id != *id);
        shared_ref.toast_paused.remove(id);
        shared_ref.toast_remaining_ms.remove(id);
        shared_ref.toast_timers.remove(id);
        if shared_ref.toast_drag.map(|(toast_id, _)| toast_id) == Some(*id) {
            shared_ref.toast_drag = None;
        }
        if shared_ref.menu_highlight == Some(*id) {
            shared_ref.menu_highlight = None;
        }
        shared_ref.imperative_roots.retain(|root| root != id);
        shared_ref.imperative_rect_reported.remove(id);
        if let Some(pending) = shared_ref.pending_scrolls.remove(id) {
            cancelled_scrolls.push((*id, pending.token));
        }
        // A dropped overlay node must not linger in the Escape-dismiss
        // stack — it would keep shadowing the layers below it.
        shared_ref
            .overlay_stack
            .retain(|(overlay_id, _)| overlay_id != id);
        drop(shared_ref);
    }
    // Dropped nodes never report their in-flight scroll — cancel so the
    // runtime isn't left waiting on a token that can never complete.
    for (id, token) in cancelled_scrolls {
        crate::scroll::scroll_completed(id, token, "cancelled", cx);
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
            if guard.virtual_lists.is_empty() {
                // No virtual lists: the parent walk only exists to remeasure them.
            } else {
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
        // A dirty node under an imperative overlay root that never
        // resolved a mounted ancestor paints on the host layer's next
        // frame instead — its parent chain ends at the orphan root.
        let (on_imperative_root, host_view) = {
            let guard = shared.borrow();
            (
                visited.iter().any(|nid| guard.imperative_roots.contains(nid)),
                guard.imperative_host_view,
            )
        };
        if on_imperative_root {
            if let Some(entity) = host_view {
                cx.notify(entity);
            }
        }
    }
    for view in dirty_views {
        cx.notify(view.entity_id());
    }
}

/// Apply a patch payload that may be either one batch object `{ops:[…]}`
/// or the stream form `[batch, batch, …]` (what `take_patches` returns in
/// hosts that fold event results into the sink).
fn note_rejected_batch(shared: &Shared, message: String, cx: &mut App) {
    eprintln!("lui-gpui: rejected batch: {message}");
    shared.borrow_mut().last_errors.push(message);
    // The runtime can rebuild the live tree at the current generation. Clear
    // the mirror only when that snapshot actually arrives, so a missing
    // resync export leaves the rolled-back store in place.
    let accepted = unsafe { bridge::lui_ocaml_resync() };
    if accepted == 0 {
        return;
    }
    let patches = bridge::take_patches();
    if patches.is_empty() {
        return;
    }
    {
        let mut guard = shared.borrow_mut();
        guard.reset_render_state();
    }
    for json in patches {
        if let Err(error) = apply_batch_json(shared, &json, cx) {
            let message = error.to_string();
            eprintln!("lui-gpui: resync batch rejected: {message}");
            shared.borrow_mut().last_errors.push(message);
        }
    }
}

pub fn apply_stream_json(shared: &Shared, json: &str, cx: &mut App) {
    let parsed = serde_json::from_str::<serde_json::Value>(json);
    match parsed {
        Ok(serde_json::Value::Array(batches)) => {
            for batch in batches {
                let result = decode_batch_value(&batch)
                    .map_err(ApplyError::Decode)
                    .and_then(|batch| apply_batch(shared, &batch, cx));
                if let Err(error) = result {
                    note_rejected_batch(shared, error.to_string(), cx);
                    // Everything left in the stream was generated against
                    // the pre-resync tree — replaying it can only produce
                    // more generation rejections.
                    break;
                }
            }
        }
        Ok(_) => {
            if let Err(error) = apply_batch_json(shared, json, cx) {
                note_rejected_batch(shared, error.to_string(), cx);
            }
        }
        Err(error) => {
            note_rejected_batch(shared, format!("decode: {error}"), cx);
        }
    }
}

/// Drain every queued batch from the OCaml bridge and apply it. Call after
/// `lui_ocaml_start` and after each `lui_ocaml_*` event returns — each call
/// synchronously pushed the next batch into the queue.
pub fn drain_pending(shared: &Shared, cx: &mut App) {
    let dump = std::env::var_os("LOGSEQ_GPUI_DUMP_PATCHES").is_some();
    for json in bridge::take_patches() {
        if dump {
            use std::io::Write;
            if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("/tmp/gpui-patches.jsonl")
            {
                let _ = f.write_all(json.as_bytes());
                let _ = f.write_all(b"\n");
            }
        }
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
