//! Native list cells own geometry and retention; this adapter only reports their
//! demand to LUI and associates the bounded committed row roots with native keys.
use crate::store::Node;
use nsh_core::{
    element::{ListViewport, Position, ViewableItems, VirtualList, after_answer},
    prelude::*,
};
use std::{
    cell::RefCell,
    collections::{BTreeMap, BTreeSet},
    rc::Rc,
    sync::Arc,
};

pub(crate) type RowIdentity = (u64, u64);

#[derive(Clone, Copy, Default, PartialEq, Eq)]
struct ScrollEpochs {
    ended: u64,
    dragged: u64,
}

/// Shared only by a real canonical Scroll and its Parent viewport lists.
/// The native Scroll controller remains the sole owner of motion and dragging.
#[derive(Clone, Copy)]
pub(crate) struct ScrollOwner {
    identity: RowIdentity,
    reference: ElementRef,
    vertical: bool,
    epochs: Signal<ScrollEpochs>,
}
impl ScrollOwner {
    pub(crate) fn new(identity: RowIdentity, reference: ElementRef, vertical: bool) -> Self {
        Self {
            identity,
            reference,
            vertical,
            epochs: signal(ScrollEpochs::default()),
        }
    }
    pub(crate) fn vertical(self) -> bool {
        self.vertical
    }
    pub(crate) fn ended(self) {
        self.epochs.update(|epochs| {
            epochs.ended = epochs
                .ended
                .checked_add(1)
                .expect("Scroll end epoch exhausted");
        });
    }
    pub(crate) fn dragged(self) {
        self.epochs.update(|epochs| {
            epochs.dragged = epochs
                .dragged
                .checked_add(1)
                .expect("Scroll drag epoch exhausted");
        });
    }
}

fn lower_viewport(value: crate::contract::VirtualViewportValue) -> ListViewport {
    use crate::contract::VirtualViewportValue;
    match value {
        VirtualViewportValue::Own => ListViewport::Own,
        VirtualViewportValue::Parent => ListViewport::Parent,
    }
}

fn viewport(node: &Node) -> Result<ListViewport, String> {
    use crate::contract::VirtualViewportValue;
    let value = match node.props.get("virtual-viewport") {
        None => VirtualViewportValue::Own,
        Some(value) => VirtualViewportValue::try_from(
            value.as_str().ok_or("virtual-viewport requires a string")?,
        )?,
    };
    Ok(lower_viewport(value))
}

pub(crate) fn owns_scroll(node: &Node) -> bool {
    matches!(node.kind.as_str(), "scroll" | "list")
        || (node.kind == "virtual-list" && matches!(viewport(node), Ok(ListViewport::Own)))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Window {
    pub generation: u64,
    pub first: usize,
    pub last: usize,
    pub pins: Vec<u64>,
}

pub(crate) enum Feedback {
    Window(Window),
    Visible(Option<(usize, usize)>),
    Scroll { token: u64, outcome: &'static str },
}

type TargetResolver = dyn Fn(&str) -> Option<usize>;

pub(crate) struct Callbacks {
    pub render: Rc<dyn Fn(RowIdentity) -> AnyElement>,
    pub resolve_target: Rc<TargetResolver>,
    pub row_ref: Rc<dyn Fn(RowIdentity) -> Option<ElementRef>>,
    pub scroll_owner: Rc<dyn Fn() -> Option<ScrollOwner>>,
    pub notify: Rc<dyn Fn(Feedback)>,
    pub failed: Rc<dyn Fn(String)>,
}

#[derive(Clone, PartialEq)]
struct Metadata {
    count: usize,
    generation: Option<u64>,
    indices: Vec<usize>,
    overscan: usize,
    extent: f32,
    track_visible: bool,
    scroll: Option<Scroll>,
}

#[derive(Clone, PartialEq)]
struct Scroll {
    token: u64,
    target: Option<usize>,
    requested: bool,
    anchor: f32,
    nearest: bool,
    animated: bool,
}
impl Metadata {
    fn parse(node: &Node) -> Result<Self, String> {
        let (count, generation, indices, scroll_index) =
            if let Some(sparse) = crate::contract::sparse_virtual(node)? {
                let count = usize::try_from(
                    u32::try_from(sparse.count)
                        .map_err(|_| "NSH virtual source exceeds u32::MAX rows")?,
                )
                .map_err(|_| "virtual source count exceeds this platform's address range")?;
                (
                    count,
                    Some(sparse.generation),
                    sparse.indices,
                    sparse.scroll_index,
                )
            } else {
                let count = node.children.len();
                if count > u32::MAX as usize {
                    return Err("NSH virtual source exceeds u32::MAX rows".into());
                }
                (count, None, (0..count).collect(), None)
            };
        Ok(Self {
            count,
            generation,
            indices,
            overscan: node
                .props
                .get("overscan")
                .and_then(|v| v.as_u64())
                .and_then(|n| usize::try_from(n).ok())
                .unwrap_or(5),
            extent: node.number("item-extent", 32.0) as f32,
            track_visible: node.boolean("track-visible-range", false),
            scroll: node
                .props
                .get("scroll-token")
                .and_then(|value| value.as_u64())
                .map(|token| Scroll {
                    token,
                    target: scroll_index.and_then(|index| usize::try_from(index).ok()),
                    requested: !node.string("scroll-target").is_empty(),
                    anchor: match node.string("scroll-anchor") {
                        "center" => 0.5,
                        "bottom" => 1.0,
                        _ => 0.0,
                    },
                    nearest: node.string("scroll-anchor") == "nearest",
                    animated: node.boolean("scroll-animated", true),
                }),
        })
    }
}

/// Adds the native count limit after canonical final-node validation.
pub(crate) fn validate(node: &Node) -> Result<(), String> {
    // Canonical metadata validation is owned by contract::validate_node.
    // NSH's public list builder accepts usize but its native count is u32.
    if node.kind == "virtual-list"
        && (node
            .props
            .get("virtual-total-count")
            .and_then(|value| value.as_u64())
            .is_some_and(|count| count > u32::MAX as u64)
            || node.children.len() > u32::MAX as usize)
    {
        return Err("NSH virtual source exceeds u32::MAX rows".into());
    }
    Ok(())
}

struct Model {
    metadata: Metadata,
    keys: Rc<Vec<u64>>,
    rows: BTreeMap<usize, RowIdentity>,
    by_key: BTreeMap<u64, RowIdentity>,
    next_key: u64,
}
impl Model {
    fn new(node: &Node, children: &[RowIdentity]) -> Result<Self, String> {
        let metadata = Metadata::parse(node)?;
        let mut model = Self {
            metadata: Metadata {
                count: 0,
                generation: None,
                indices: Vec::new(),
                overscan: 5,
                extent: 32.0,
                track_visible: false,
                scroll: None,
            },
            keys: Rc::default(),
            rows: BTreeMap::new(),
            by_key: BTreeMap::new(),
            next_key: 1,
        };
        model.update(metadata, children)?;
        Ok(model)
    }
    fn update(&mut self, metadata: Metadata, children: &[RowIdentity]) -> Result<bool, String> {
        let rows: BTreeMap<_, _> = metadata
            .indices
            .iter()
            .copied()
            .zip(children.iter().copied())
            .collect();
        let structural = metadata.generation != self.metadata.generation
            || metadata.count != self.metadata.count
            || (metadata.generation.is_none() && rows != self.rows);
        if structural {
            let retained: BTreeMap<_, _> = self
                .rows
                .iter()
                .map(|(index, identity)| (*identity, self.keys[*index]))
                .collect();
            let end = self
                .next_key
                .checked_add(metadata.count as u64)
                .ok_or("virtual list key space exhausted")?;
            let mut keys: Vec<_> = (self.next_key..end).collect();
            self.next_key = end;
            for (index, identity) in &rows {
                if let Some(key) = retained.get(identity) {
                    keys[*index] = *key;
                }
            }
            self.keys = Rc::new(keys);
        }
        self.by_key = rows
            .iter()
            .map(|(index, identity)| (self.keys[*index], *identity))
            .collect();
        self.rows = rows;
        self.metadata = metadata;
        Ok(structural)
    }
}

struct Cell {
    index: usize,
    count: usize,
    requested: bool,
    key: Option<u64>,
    row: Signal<Option<RowIdentity>>,
    materialized: Option<RowIdentity>,
}
struct PendingScroll {
    request: Scroll,
    generation: Option<u64>,
    ended: bool,
    revealed: bool,
    measuring: bool,
    command_issued: bool,
}
impl PendingScroll {
    fn new(request: Scroll, generation: Option<u64>) -> Self {
        Self {
            request,
            generation,
            ended: false,
            revealed: false,
            measuring: false,
            command_issued: false,
        }
    }
}

struct NativeState {
    model: Model,
    cells: BTreeMap<u64, Cell>,
    next_cell: u64,
    visible: Option<(usize, usize)>,
    last_window: Option<Window>,
    last_visible: Option<Option<(usize, usize)>>,
    owner: Owner,
    queued: bool,
    alive: bool,
    notify: Rc<dyn Fn(Feedback)>,
    reference: ElementRef,
    scroll_owner: Option<ScrollOwner>,
    parent_viewport: bool,
    row_ref: Rc<dyn Fn(RowIdentity) -> Option<ElementRef>>,
    handled_token: Option<u64>,
    pending_scroll: Option<PendingScroll>,
}
#[derive(Clone)]
struct NativeRows(Rc<RefCell<NativeState>>);
impl NativeRows {
    fn schedule(&self) {
        let owner = {
            let mut state = self.0.borrow_mut();
            if !state.alive || state.queued {
                return;
            }
            state.queued = true;
            state.owner
        };
        let rows = self.clone();
        owner.run(|| after_answer(move || rows.flush()));
    }

    fn flush(&self) {
        let (updates, feedback, notify, command, reveal) = {
            let mut state = self.0.borrow_mut();
            if !state.alive {
                return;
            }
            state.queued = false;
            let mut updates = Vec::new();
            let NativeState { model, cells, .. } = &mut *state;
            for cell in cells.values_mut() {
                cell.key = (cell.requested && cell.index < cell.count)
                    .then(|| model.keys.get(cell.index).copied())
                    .flatten();
                updates.push((
                    cell.row,
                    cell.key.and_then(|key| model.by_key.get(&key).copied()),
                ));
            }
            let mut feedback = Vec::new();
            let mut command = None;
            let mut reveal = None;
            let request = state.model.metadata.scroll.clone();
            let generation = state.model.metadata.generation;
            if let Some(request) = request {
                if state.handled_token != Some(request.token) {
                    if let Some(previous) = state.pending_scroll.take() {
                        feedback.push(Feedback::Scroll {
                            token: previous.request.token,
                            outcome: "cancelled",
                        });
                    }
                    state.handled_token = Some(request.token);
                    if request.requested {
                        if request.target.is_some() {
                            command = Some(request.clone());
                            state.pending_scroll = Some(PendingScroll::new(request, generation));
                        } else {
                            feedback.push(Feedback::Scroll {
                                token: request.token,
                                outcome: "missing-target",
                            });
                        }
                    }
                } else if let Some(pending) = state.pending_scroll.as_ref() {
                    if request.target.is_none() {
                        feedback.push(Feedback::Scroll {
                            token: request.token,
                            outcome: "missing-target",
                        });
                        state.pending_scroll = None;
                    } else if pending.request != request || pending.generation != generation {
                        command = Some(request.clone());
                        state.pending_scroll = Some(PendingScroll::new(request, generation));
                    }
                }
            }
            if let Some(pending) = state.pending_scroll.as_ref()
                && pending.request.nearest
                && !pending.revealed
                && !pending.measuring
                && let Some(index) = pending.request.target
            {
                let materialized = state.model.rows.get(&index).filter(|identity| {
                    state.cells.values().any(|cell| {
                        cell.requested
                            && cell.index == index
                            && cell.materialized == Some(**identity)
                    })
                });
                if let Some(reference) =
                    materialized.and_then(|identity| (state.row_ref)(*identity))
                {
                    reveal = Some((reference, pending.request.clone(), pending.generation));
                    command = None;
                    let pending = state
                        .pending_scroll
                        .as_mut()
                        .expect("checked nearest scroll");
                    pending.measuring = true;
                } else if state
                    .visible
                    .is_some_and(|(first, last)| first <= index && index <= last)
                {
                    // The native cell already asks for this row. Wait for its
                    // real root before resolving nearest from native geometry.
                    command = None;
                }
            }
            if command.is_some()
                && let Some(pending) = state.pending_scroll.as_mut()
            {
                pending.command_issued = true;
            }
            if command.is_none()
                && reveal.is_none()
                && state.pending_scroll.as_ref().is_some_and(|pending| {
                    let Some(index) = pending.request.target else {
                        return false;
                    };
                    let visible = state
                        .visible
                        .is_some_and(|(first, last)| first <= index && index <= last);
                    let row = state.model.rows.get(&index);
                    visible
                        && (!pending.request.nearest || pending.revealed)
                        && (!pending.request.animated || pending.ended)
                        && row.is_some_and(|row| {
                            state.cells.values().any(|cell| {
                                cell.requested
                                    && cell.index == index
                                    && cell.materialized == Some(*row)
                            })
                        })
                })
            {
                let pending = state.pending_scroll.take().expect("checked pending scroll");
                feedback.push(Feedback::Scroll {
                    token: pending.request.token,
                    outcome: "succeeded",
                });
            }
            if let Some(window) = demanded_window(
                &state.model,
                state
                    .cells
                    .values()
                    .filter(|cell| cell.requested)
                    .map(|cell| cell.index),
                state.visible,
            ) && state.last_window.as_ref() != Some(&window)
            {
                state.last_window = Some(window.clone());
                feedback.push(Feedback::Window(window));
            }
            if state.model.metadata.track_visible {
                if state.last_visible != Some(state.visible) {
                    state.last_visible = Some(state.visible);
                    feedback.push(Feedback::Visible(state.visible));
                }
            } else {
                state.last_visible = None;
            }
            (
                updates,
                feedback,
                state.notify.clone(),
                command.map(|mut request| {
                    if request.nearest {
                        request.anchor = if state.visible.is_some_and(|(first, _)| {
                            request.target.is_some_and(|index| index < first)
                        }) {
                            0.0
                        } else {
                            1.0
                        };
                    }
                    (state.reference, request)
                }),
                reveal,
            )
        };
        batch(|| {
            for (signal, row) in updates {
                if signal.get_untracked() != row {
                    signal.set(row);
                }
            }
        });
        if let Some((reference, request)) = command
            && let Some(index) = request.target
        {
            reference.scroll_to_index(
                index as u32,
                percentage(request.anchor),
                px(0.0),
                request.animated,
            );
            self.schedule();
        }
        if let Some((reference, request, generation)) = reveal {
            self.reveal_nearest(reference, request, generation);
        }
        for event in feedback {
            notify(event);
        }
    }
    fn reveal_nearest(&self, reference: ElementRef, request: Scroll, generation: Option<u64>) {
        let (list, viewport, viewport_identity, owner) = {
            let state = self.0.borrow();
            if state.parent_viewport && state.scroll_owner.is_none() {
                return;
            }
            (
                state.reference,
                state
                    .scroll_owner
                    .map_or(state.reference, |owner| owner.reference),
                state.scroll_owner.map(|owner| owner.identity),
                state.owner,
            )
        };
        let rows = self.clone();
        owner.run(|| {
            spawn(async move {
                // Measure before issuing a command: an already satisfied animated
                // request has no native animation and therefore no scroll-end.
                let row = reference.measure();
                let viewport = viewport.measure();
                let row = row.await;
                let viewport = viewport.await;
                let anchor = row
                    .zip(viewport)
                    .and_then(|(row, viewport)| nearest_anchor(&row, &viewport));
                let no_op = anchor.is_none();
                {
                    let mut state = rows.0.borrow_mut();
                    if !state.alive
                        || state.scroll_owner.map(|owner| owner.identity) != viewport_identity
                    {
                        return;
                    }
                    let Some(pending) = state.pending_scroll.as_mut().filter(|pending| {
                        pending.request == request && pending.generation == generation
                    }) else {
                        return;
                    };
                    pending.measuring = false;
                    if row.is_none() || viewport.is_none() {
                        return;
                    }
                    pending.revealed = true;
                    if no_op {
                        // An offscreen jump may still animate after its row
                        // materializes. An unissued no-op has no scroll-end.
                        if !pending.command_issued {
                            pending.ended = true;
                        }
                    } else {
                        pending.command_issued = true;
                        pending.ended = false;
                    }
                }
                if let Some(anchor) = anchor
                    && let Some(index) = request.target
                {
                    // Reveal intentionally excludes List ancestors. The native
                    // list owns the measured row offsets used by this command.
                    list.scroll_to_index(
                        index as u32,
                        percentage(anchor),
                        px(0.0),
                        request.animated,
                    );
                }
                rows.schedule();
            });
        });
    }
    fn scroll_ended(&self) {
        if let Some(pending) = self.0.borrow_mut().pending_scroll.as_mut() {
            pending.ended = true;
        }
        self.schedule();
    }
    fn scroll_dragged(&self) {
        let (pending, notify) = {
            let mut state = self.0.borrow_mut();
            (state.pending_scroll.take(), state.notify.clone())
        };
        if let Some(pending) = pending {
            notify(Feedback::Scroll {
                token: pending.request.token,
                outcome: "cancelled",
            });
        }
    }
    fn parent_owner(&self, next: Option<ScrollOwner>) {
        let mut state = self.0.borrow_mut();
        if state.scroll_owner.map(|owner| owner.identity) == next.map(|owner| owner.identity) {
            return;
        }
        state.scroll_owner = next;
        // A pending command now belongs to a different viewport. Retry the
        // same token there; an old owner's completion must not finish it.
        if state.pending_scroll.take().is_some() {
            state.handled_token = None;
        }
        drop(state);
        self.schedule();
    }
    fn materialized(&self, slot: u64, identity: RowIdentity) {
        if let Some(cell) = self.0.borrow_mut().cells.get_mut(&slot)
            && cell.row.get_untracked() == Some(identity)
        {
            cell.materialized = Some(identity);
        }
        self.schedule();
    }
    fn position(&self, slot: u64, index: usize, count: usize, requested: bool) {
        let update = {
            let mut state = self.0.borrow_mut();
            let key = (requested && index < count)
                .then(|| state.model.keys.get(index).copied())
                .flatten();
            let row = key.and_then(|key| state.model.by_key.get(&key).copied());
            state.cells.get_mut(&slot).map(|cell| {
                cell.index = index;
                cell.count = count;
                cell.requested = requested;
                cell.key = key;
                if cell.row.get_untracked() != row {
                    cell.materialized = None;
                }
                (cell.row, row)
            })
        };
        if let Some((signal, row)) = update
            && signal.get_untracked() != row
        {
            signal.set(row);
        }
        self.schedule();
    }
    fn update(
        &self,
        metadata: Metadata,
        children: &[RowIdentity],
        keys: Signal<Rc<Vec<u64>>>,
        count: Signal<usize>,
        extent: Signal<f32>,
    ) -> Result<(), String> {
        let (structural, next_keys, next_count, next_extent, updates) = {
            let mut state = self.0.borrow_mut();
            let structural = state.model.update(metadata, children)?;
            let updates: Vec<_> = state
                .cells
                .values()
                .map(|cell| {
                    (
                        cell.row,
                        cell.key
                            .and_then(|key| state.model.by_key.get(&key).copied()),
                    )
                })
                .collect();
            (
                structural,
                state.model.keys.clone(),
                state.model.metadata.count,
                state.model.metadata.extent,
                updates,
            )
        };
        batch(|| {
            if structural {
                keys.set(next_keys);
                if count.get_untracked() != next_count {
                    count.set(next_count);
                }
            }
            if extent.get_untracked() != next_extent {
                extent.set(next_extent);
            }
            // Associate an existing cell by its native key while NSH moves its
            // Position. Reading a new source by its old numeric position here
            // would replace the editor before the keyed move reaches it.
            for (signal, row) in updates {
                if signal.get_untracked() != row {
                    signal.set(row);
                }
            }
        });
        self.schedule();
        Ok(())
    }
}

fn nearest_anchor(row: &nsh_core::Measurement, viewport: &nsh_core::Measurement) -> Option<f32> {
    let start = row.page.y.0;
    let end = start + row.frame.size.height.0;
    let top = viewport.page.y.0;
    let bottom = top + viewport.frame.size.height.0;
    if ![start, end, top, bottom]
        .iter()
        .all(|value| value.is_finite())
        || (start >= top && end <= bottom)
        || (start <= top && end >= bottom)
    {
        None
    } else if (start < top) == (end - start <= bottom - top) {
        Some(0.0)
    } else {
        Some(1.0)
    }
}

fn demanded_window(
    model: &Model,
    demanded: impl Iterator<Item = usize>,
    visible: Option<(usize, usize)>,
) -> Option<Window> {
    let generation = model.metadata.generation?;
    let count = model.metadata.count;
    let mut indices: Vec<_> = demanded.filter(|index| *index < count).collect();
    indices.sort_unstable();
    indices.dedup();
    let mut clusters: Vec<(usize, usize)> = Vec::new();
    for index in indices.iter().copied() {
        if let Some((_, last)) = clusters.last_mut()
            && *last == index
        {
            *last += 1;
        } else {
            clusters.push((index, index + 1));
        }
    }
    let anchor = visible.map_or(0, |(first, _)| first);
    let (mut first, mut last) = clusters
        .into_iter()
        .min_by_key(|(first, last)| {
            if anchor < *first {
                *first - anchor
            } else {
                anchor.saturating_sub(last.saturating_sub(1))
            }
        })
        .unwrap_or((0, 0));
    if let Some((visible_first, visible_last)) = visible
        && visible_first < count
    {
        first = first.min(visible_first.saturating_sub(model.metadata.overscan));
        last = last.max(
            visible_last
                .saturating_add(1)
                .saturating_add(model.metadata.overscan)
                .min(count),
        );
    }
    let pins: BTreeSet<_> = indices
        .into_iter()
        .filter(|index| *index < first || *index >= last)
        .filter_map(|index| model.rows.get(&index).map(|identity| identity.0))
        .collect();
    Some(Window {
        generation,
        first,
        last,
        pins: pins.into_iter().collect(),
    })
}

struct Keys {
    values: Rc<Vec<u64>>,
    index: usize,
}
impl Iterator for Keys {
    type Item = u64;
    fn next(&mut self) -> Option<Self::Item> {
        let value = self.values.get(self.index).copied();
        self.index += usize::from(value.is_some());
        value
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let left = self.values.len() - self.index;
        (left, Some(left))
    }
}
impl ExactSizeIterator for Keys {}

pub(crate) fn element(
    node: Signal<Arc<Node>>,
    children: Signal<Vec<RowIdentity>>,
    reference: ElementRef,
    callbacks: Callbacks,
) -> VirtualList {
    let initial = node.get_untracked();
    let parent_viewport = matches!(
        viewport(&initial).expect("validated virtual viewport"),
        ListViewport::Parent
    );
    let model = Model::new(&initial, &children.get_untracked()).expect("validated virtual source");
    let keys = signal(model.keys.clone());
    let count = signal(model.metadata.count);
    let extent = signal(model.metadata.extent);
    let callbacks = Rc::new(callbacks);
    let rows = NativeRows(Rc::new(RefCell::new(NativeState {
        model,
        cells: BTreeMap::new(),
        next_cell: 0,
        visible: None,
        last_window: None,
        last_visible: None,
        owner: Owner::current(),
        queued: false,
        alive: true,
        notify: callbacks.notify.clone(),
        reference,
        scroll_owner: None,
        parent_viewport,
        row_ref: callbacks.row_ref.clone(),
        handled_token: None,
        pending_scroll: None,
    })));
    let disposal = rows.clone();
    cleanup(move || {
        let mut state = disposal.0.borrow_mut();
        state.alive = false;
        state.cells.clear();
    });
    if parent_viewport {
        let parent_rows = rows.clone();
        let parent_callbacks = callbacks.clone();
        let previous = RefCell::new(None::<(RowIdentity, ScrollEpochs)>);
        effect(move || {
            let owner = (parent_callbacks.scroll_owner)();
            let epochs = owner.map(|owner| owner.epochs.get());
            parent_rows.parent_owner(owner);
            let next = owner
                .zip(epochs)
                .map(|(owner, epochs)| (owner.identity, epochs));
            let old = previous.replace(next);
            match (old, next) {
                (Some((old_id, old)), Some((id, next))) if old_id == id => {
                    // Drag wins when both are coalesced in one reactive turn.
                    if next.dragged != old.dragged {
                        parent_rows.scroll_dragged();
                    } else if next.ended != old.ended {
                        parent_rows.scroll_ended();
                    }
                }
                (_, None) => (parent_callbacks.failed)(
                    "NSH Parent virtual-list requires an ancestor Scroll".into(),
                ),
                _ => {}
            }
        });
    }
    let updating = rows.clone();
    let previous = RefCell::new(None::<Arc<Node>>);
    let metadata_callbacks = callbacks.clone();
    effect(move || {
        let node = node.get();
        children.with(|_| ());
        // A container style edit must not copy its literal child sequence or
        // rebuild list identity maps. Structural parent patches and snapshots
        // replace the shared sequence when child identities can change.
        if previous.borrow().as_ref().is_some_and(|previous| {
            Arc::ptr_eq(&previous.children, &node.children)
                && [
                    "virtual-total-count",
                    "virtual-generation",
                    "virtual-indices",
                    "virtual-scroll-index",
                    "overscan",
                    "item-extent",
                    "track-visible-range",
                    "scroll-target",
                    "scroll-token",
                    "scroll-anchor",
                    "scroll-animated",
                ]
                .iter()
                .all(|name| previous.props.get(*name) == node.props.get(*name))
        }) {
            return;
        }
        *previous.borrow_mut() = Some(node.clone());
        let children = children.get_untracked();
        if let Err(error) = Metadata::parse(&node).and_then(|mut metadata| {
            if metadata.generation.is_none()
                && let Some(scroll) = metadata.scroll.as_mut()
            {
                scroll.target = (metadata_callbacks.resolve_target)(node.string("scroll-target"));
            }
            updating.update(metadata, &children, keys, count, extent)
        }) {
            (metadata_callbacks.failed)(error);
        }
    });
    let cells = rows.clone();
    let render = callbacks.render.clone();
    let list = virtual_list(
        move || count.get(),
        move |position: Position| {
            let index = untracked(|| position.index());
            let total = untracked(|| position.count());
            let requested = untracked(|| position.is_requested());
            let (slot, row) = {
                let mut state = cells.0.borrow_mut();
                let slot = state.next_cell;
                state.next_cell += 1;
                let key = requested
                    .then(|| state.model.keys.get(index).copied())
                    .flatten();
                let row = signal(key.and_then(|key| state.model.by_key.get(&key).copied()));
                state.cells.insert(
                    slot,
                    Cell {
                        index,
                        count: total,
                        requested,
                        key,
                        row,
                        materialized: None,
                    },
                );
                (slot, row)
            };
            let positioning = cells.clone();
            effect(move || {
                positioning.position(
                    slot,
                    position.index(),
                    position.count(),
                    position.is_requested(),
                )
            });
            let disposing = cells.clone();
            cleanup(move || {
                disposing.0.borrow_mut().cells.remove(&slot);
                disposing.schedule();
            });
            let render = render.clone();
            let materializing = cells.clone();
            dynamic(move || match row.get() {
                Some(identity) => {
                    let materializing = materializing.clone();
                    after_answer(move || materializing.materialized(slot, identity));
                    render(identity)
                }
                None => view().h(move || px(extent.get())).into_element(),
            })
        },
    )
    .viewport(viewport(&initial).expect("validated virtual viewport"))
    .element_ref(&reference)
    .keys(move || Keys {
        values: keys.get(),
        index: 0,
    })
    .estimated_item_size(move || px(extent.get()))
    .row_gap(move || px(node.get().number("gap", 0.0) as f32))
    .columns(move || {
        node.get()
            .props
            .get("columns")
            .and_then(|value| value.as_u64())
            .unwrap_or(1)
            .clamp(1, u32::MAX as u64) as u32
    });
    let native_owner = (!parent_viewport)
        .then(|| untracked(|| (callbacks.scroll_owner)()))
        .flatten();
    let observing = rows.clone();
    let ending = rows.clone();
    let interrupting = rows;
    list.on_viewable_items_change(move |event: &ViewableItems| {
        observing.0.borrow_mut().visible = event.viewable;
        observing.schedule();
    })
    .on_scroll_end(move |_: &Point<Points>| {
        if !parent_viewport {
            ending.scroll_ended();
            if let Some(owner) = native_owner {
                owner.ended();
            }
        }
    })
    .on_scroll_drag_start(move |_: &Point<Points>| {
        if !parent_viewport {
            interrupting.scroll_dragged();
            if let Some(owner) = native_owner {
                owner.dragged();
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn node(count: usize, generation: u64, rows: &[(usize, u64)]) -> Node {
        let mut node = Node {
            kind: "virtual-list".into(),
            children: Arc::new(rows.iter().map(|row| row.1).collect()),
            ..Default::default()
        };
        node.props
            .insert("virtual-total-count".into(), json!(count));
        node.props
            .insert("virtual-generation".into(), json!(generation));
        node.props.insert(
            "virtual-indices".into(),
            json!(
                serde_json::to_string(&rows.iter().map(|row| row.0).collect::<Vec<_>>()).unwrap()
            ),
        );
        node
    }
    #[test]
    fn native_keys_follow_retained_row_identities_without_source_work_on_window_updates() {
        let first = node(100_000, 1, &[(2, 20), (99_990, 30)]);
        let mut model = Model::new(&first, &[(20, 1), (30, 1)]).unwrap();
        let keys = model.keys.clone();
        let edited_key = keys[2];
        let window = node(100_000, 1, &[(2, 20), (99_991, 40)]);
        assert!(
            !model
                .update(Metadata::parse(&window).unwrap(), &[(20, 1), (40, 1)])
                .unwrap()
        );
        assert!(Rc::ptr_eq(&keys, &model.keys));
        let reordered = node(100_000, 2, &[(3, 40), (99_999, 20)]);
        assert!(
            model
                .update(Metadata::parse(&reordered).unwrap(), &[(40, 1), (20, 1)])
                .unwrap()
        );
        assert_eq!(model.keys[99_999], edited_key);
        assert_eq!(model.by_key[&edited_key], (20, 1));
        assert_eq!(model.rows.len(), 2);
    }
    #[test]
    fn distant_native_cell_demand_is_a_row_pin_not_a_source_spanning_window() {
        let source = node(100_000, 1, &[(2, 20), (99_999, 30)]);
        let model = Model::new(&source, &[(20, 1), (30, 1)]).unwrap();
        let window = demanded_window(
            &model,
            std::iter::once(2).chain(99_980..100_000),
            Some((99_990, 99_999)),
        )
        .unwrap();
        assert_eq!((window.first, window.last), (99_980, 100_000));
        assert_eq!(window.pins, [20]);
        let first =
            demanded_window(&model, (0..23).chain(std::iter::once(99_999)), Some((0, 9))).unwrap();
        assert_eq!((first.first, first.last), (0, 23));
        assert_eq!(first.pins, [30]);
        let empty = node(0, 2, &[]);
        let empty = Model::new(&empty, &[]).unwrap();
        let window = demanded_window(&empty, [0, 2, 99_999].into_iter(), None).unwrap();
        assert_eq!((window.first, window.last), (0, 0));
        assert!(window.pins.is_empty());
    }
    #[test]
    fn invalid_sparse_metadata_and_native_count_truncation_are_rejected() {
        assert!(crate::contract::validate_node(&node(10, 1, &[(2, 2), (2, 3)])).is_err());
        assert!(crate::contract::validate_node(&node(10, 1, &[(10, 2)])).is_err());
        let mut invalid = node(10, 1, &[(2, 2)]);
        invalid
            .props
            .insert("virtual-indices".into(), json!("[ 2 ]"));
        assert!(Metadata::parse(&invalid).is_err());
        invalid.props.insert("virtual-indices".into(), json!("[]"));
        assert!(Metadata::parse(&invalid).is_err());
        let invalid = node(u32::MAX as usize + 1, 1, &[]);
        assert!(Metadata::parse(&invalid).is_err());
    }
    #[derive(Default)]
    struct NativeProbe {
        window: Option<Window>,
    }
    struct NativeContext(Arc<std::sync::Mutex<NativeProbe>>);
    struct ParentViewport;
    #[component]
    fn NativeFixture() -> impl IntoElement {
        let probe = nsh_core::element::engine_context::<NativeContext>().unwrap();
        let committed: Vec<_> = (0..23)
            .chain(std::iter::once(99_999))
            .map(|index| (index, index as u64 + 100))
            .collect();
        let mut source = node(100_000, 1, &committed);
        source
            .props
            .insert("track-visible-range".into(), json!(true));
        let parent_viewport = engine_context::<ParentViewport>().is_some();
        let parent_reference = element_ref();
        let parent_owner = ScrollOwner::new((1, 1), parent_reference, true);
        if parent_viewport {
            source
                .props
                .insert("virtual-viewport".into(), json!("parent"));
        }
        let source = signal(Arc::new(source));
        let children = signal(committed.iter().map(|(_, id)| (*id, 1)).collect());
        let draft = signal("Row 2".to_owned());
        on_key_with(
            "f7",
            nsh_core::element::KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                source.update(|source| {
                    let source = Arc::make_mut(source);
                    source.props.insert("scroll-token".into(), json!(1));
                    source.props.insert("scroll-target".into(), json!("last"));
                    source.props.insert("scroll-animated".into(), json!(false));
                    source
                        .props
                        .insert("virtual-scroll-index".into(), json!(99_999));
                });
            },
        );
        on_key_with(
            "f6",
            nsh_core::element::KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| dismiss_keyboard(),
        );
        let list = element(
            source,
            children,
            element_ref(),
            Callbacks {
                render: Rc::new(move |(id, _)| {
                    let index = id - 100;
                    nsh_base::input()
                        .h(px(32.0))
                        .label(format!("Row {index}"))
                        .value(move || {
                            if index == 2 {
                                draft.get()
                            } else {
                                format!("Row {index}")
                            }
                        })
                        .on_change(move |value: &str| {
                            if index == 2 {
                                draft.set(value.into());
                            }
                        })
                        .into_element()
                }),
                resolve_target: Rc::new(|_| None),
                row_ref: Rc::new(|_| None),
                notify: Rc::new(move |event| {
                    if let Feedback::Window(window) = event {
                        probe.0.lock().unwrap().window = Some(window);
                    }
                }),
                scroll_owner: Rc::new(move || parent_viewport.then_some(parent_owner)),
                failed: Rc::new(|error| panic!("{error}")),
            },
        )
        .w(px(400.0));
        if parent_viewport {
            scroll()
                .element_ref(&parent_reference)
                .on_scroll_end(move |_: &Point<Points>| parent_owner.ended())
                .on_scroll_drag_start(move |_: &Point<Points>| parent_owner.dragged())
                .h(px(320.0))
                .w(px(400.0))
                .test_id("shared-scroll-viewport")
                .child(
                    view()
                        .flex_col()
                        .child(text("Shared header").h(px(64.0)))
                        .child(list),
                )
                .into_element()
        } else {
            list.h(px(320.0)).into_element()
        }
    }
    #[test]
    fn native_cell_feedback_releases_distant_focus_without_scrolling_again() -> Result<(), String> {
        exercise_native_cell_feedback(false)
    }
    #[test]
    fn parent_viewport_reuses_outer_scroll_and_retains_distant_editor_with_bounded_cells()
    -> Result<(), String> {
        exercise_native_cell_feedback(true)
    }
    fn exercise_native_cell_feedback(parent: bool) -> Result<(), String> {
        use nsh_core::platform::{Idiom, Os};
        use nsh_engine::{EngineConfig, EngineContext, Environment, Root};
        use nsh_testing::Headless;
        use std::time::Duration;
        let probe = Arc::new(std::sync::Mutex::new(NativeProbe::default()));
        let mut context = EngineContext::default().with(NativeContext(probe.clone()));
        if parent {
            context = context.with(ParentViewport);
        }
        let mut app = Headless::start(EngineConfig {
            environment: Environment {
                os: Os::Linux,
                idiom: Idiom::Desktop,
                ..Default::default()
            },
            context,
            ..EngineConfig::new(Root::of::<NativeFixture>())
        })
        .unwrap();
        app.wait_for("label:Row 2")?;
        if parent {
            assert!(
                app.screen().layout_nodes().len() < 200,
                "parent viewport mounted source-sized native cells"
            );
        }
        app.type_text("label:Row 2", "!")?;
        app.press_key("f7")?;
        app.wait_for("label:Row 99999")?;
        if parent {
            assert!(
                app.screen().layout_nodes().len() < 200,
                "far jump mounted source-sized native cells"
            );
        }
        app.wait_until("distant editor retained", Duration::from_secs(3), |_| {
            probe
                .lock()
                .unwrap()
                .window
                .as_ref()
                .is_some_and(|window| window.last == 100_000 && window.pins.contains(&102))
        })?;
        app.press_key("f6")?;
        let result = app.wait_until(
            "released focus stops pinning row 2",
            Duration::from_secs(3),
            |_| {
                probe
                    .lock()
                    .unwrap()
                    .window
                    .as_ref()
                    .is_some_and(|window| window.last == 100_000 && window.pins.is_empty())
            },
        );
        if result.is_err() {
            eprintln!("window after blur: {:?}", probe.lock().unwrap().window);
        }
        result
    }
    #[derive(Default)]
    struct ScrollProbe {
        outcomes: Vec<(u64, String)>,
        target_ready: bool,
        scroll_ends: usize,
        press: Option<u32>,
        list: Option<u32>,
        offset: Point<Points>,
        applied: u32,
        errors: Vec<String>,
    }
    struct ScrollContext(Arc<std::sync::Mutex<ScrollProbe>>);
    #[component]
    fn ScrollFixture() -> impl IntoElement {
        let probe = nsh_core::element::engine_context::<ScrollContext>().unwrap();
        let source = signal(Arc::new(Node {
            kind: "virtual-list".into(),
            children: Arc::new((100..130).collect()),
            ..Default::default()
        }));
        let children = signal((100..130).map(|id| (id, 1)).collect());
        let references = Rc::new(RefCell::new(BTreeMap::<RowIdentity, ElementRef>::new()));
        for (key, token, target, animated) in [
            ("f7", 1, "row-2", false),
            ("f8", 2, "row-2", true),
            ("f6", 3, "missing", false),
            ("f5", 4, "row-29", true),
        ] {
            on_key_with(
                key,
                nsh_core::element::KeyOptions {
                    when: nsh_core::keymap::When::Always,
                    ..Default::default()
                },
                move |_| {
                    source.update(|source| {
                        let source = Arc::make_mut(source);
                        source.props.insert("scroll-token".into(), json!(token));
                        source.props.insert("scroll-target".into(), json!(target));
                        source
                            .props
                            .insert("scroll-anchor".into(), json!("nearest"));
                        source
                            .props
                            .insert("scroll-animated".into(), json!(animated));
                    })
                },
            );
        }
        let render_references = references.clone();
        let rendering_probe = probe.clone();
        let row_ref = references;
        let ending_probe = probe.clone();
        let list = element(
            source,
            children,
            element_ref(),
            Callbacks {
                render: Rc::new(move |identity| {
                    let reference = element_ref();
                    render_references.borrow_mut().insert(identity, reference);
                    let index = identity.0 - 100;
                    if index == 29 {
                        let probe = rendering_probe.clone();
                        after_answer(move || probe.0.lock().unwrap().target_ready = true);
                    }
                    nsh_base::input()
                        .element_ref(&reference)
                        .test_id(&format!("scroll-row-{index}"))
                        .label(format!("Row {index}"))
                        .value(format!("Row {index}"))
                        .h(px(if index == 2 { 64.0 } else { 32.0 }))
                        .into_element()
                }),
                resolve_target: Rc::new(|target| {
                    target
                        .strip_prefix("row-")
                        .and_then(|index| index.parse::<usize>().ok())
                        .filter(|index| *index < 30)
                }),
                row_ref: Rc::new(move |identity| {
                    row_ref
                        .borrow()
                        .get(&identity)
                        .copied()
                        .filter(|reference| reference.node().is_some())
                }),
                notify: Rc::new(move |event| {
                    if let Feedback::Scroll { token, outcome } = event {
                        probe
                            .0
                            .lock()
                            .unwrap()
                            .outcomes
                            .push((token, outcome.into()));
                    }
                }),
                scroll_owner: Rc::new(|| None),
                failed: Rc::new(|error| panic!("{error}")),
            },
        )
        .h(px(96.0))
        .w(px(400.0))
        .test_id("scroll-fixture-list")
        .on_scroll_end(move |_: &Point<Points>| ending_probe.0.lock().unwrap().scroll_ends += 1);
        view()
            .flex_1()
            .on_press(move || {
                source.update(|source| {
                    let source = Arc::make_mut(source);
                    source.props.insert("scroll-token".into(), json!(4));
                    source.props.insert("scroll-target".into(), json!("row-29"));
                    source
                        .props
                        .insert("scroll-anchor".into(), json!("nearest"));
                    source.props.insert("scroll-animated".into(), json!(true));
                })
            })
            .child(list)
    }
    #[test]
    fn eager_nearest_uses_native_root_geometry_and_reports_each_token_once() -> Result<(), String> {
        use nsh_core::platform::{Idiom, Os};
        use nsh_engine::{EngineConfig, EngineContext, Environment, Root};
        use nsh_testing::Headless;
        use std::time::Duration;
        let probe = Arc::new(std::sync::Mutex::new(ScrollProbe::default()));
        let mut app = Headless::start(EngineConfig {
            environment: Environment {
                os: Os::Linux,
                idiom: Idiom::Desktop,
                ..Default::default()
            },
            context: EngineContext::default().with(ScrollContext(probe.clone())),
            ..EngineConfig::new(Root::of::<ScrollFixture>())
        })
        .unwrap();
        app.wait_for("label:Row 2")?;
        let bounds = |app: &Headless, id: &str| {
            app.screen()
                .layout_nodes()
                .into_iter()
                .find(|node| node.test_id.as_deref() == Some(id))
                .unwrap()
                .bounds
        };
        assert!(
            bounds(&app, "scroll-row-2").bottom() > bounds(&app, "scroll-fixture-list").bottom(),
            "fixture row must start partially clipped"
        );
        app.press_key("f7")?;
        app.wait_until(
            "eager nearest target succeeds",
            Duration::from_secs(3),
            |_| {
                probe
                    .lock()
                    .unwrap()
                    .outcomes
                    .contains(&(1, "succeeded".into()))
            },
        )?;
        let row = bounds(&app, "scroll-row-2");
        let viewport = bounds(&app, "scroll-fixture-list");
        assert!(
            row.origin.y >= viewport.origin.y && row.bottom() <= viewport.bottom(),
            "nearest did not fully reveal actual variable-height row: row={row:?}, viewport={viewport:?}"
        );
        app.press_key("f8")?;
        app.wait_until(
            "already visible animated nearest needs no animation-end event",
            Duration::from_secs(3),
            |_| {
                probe
                    .lock()
                    .unwrap()
                    .outcomes
                    .contains(&(2, "succeeded".into()))
            },
        )?;
        app.press_key("f6")?;
        app.wait_until(
            "unknown eager target is missing",
            Duration::from_secs(3),
            |_| {
                probe
                    .lock()
                    .unwrap()
                    .outcomes
                    .contains(&(3, "missing-target".into()))
            },
        )?;
        app.press_key("f6")?;
        assert_eq!(
            probe.lock().unwrap().outcomes.len(),
            3,
            "repeated same token emitted twice"
        );
        app.press_key("f5")?;
        app.wait_for("label:Row 29")?;
        assert!(
            !probe
                .lock()
                .unwrap()
                .outcomes
                .iter()
                .any(|(token, _)| *token == 4),
            "animated command completed before native scroll-end"
        );
        app.scroll("id:scroll-fixture-list", px(-10.0))?;
        app.wait_until(
            "a user scroll cancels the pending animated target",
            Duration::from_secs(3),
            |_| {
                probe
                    .lock()
                    .unwrap()
                    .outcomes
                    .contains(&(4, "cancelled".into()))
            },
        )?;
        assert_eq!(probe.lock().unwrap().outcomes.len(), 4);
        Ok(())
    }
    struct AnimatedPlatform {
        probe: Arc<std::sync::Mutex<ScrollProbe>>,
        control: Arc<std::sync::OnceLock<nsh_engine::EngineControl>>,
    }
    impl nsh_engine::MountSink for AnimatedPlatform {
        fn submit(&self, batch: nsh_core::MountBatch) {
            for item in batch.items {
                let mut report = None;
                {
                    let mut probe = self.probe.lock().unwrap();
                    match item {
                        nsh_core::MountItem::Create {
                            id,
                            kind: nsh_core::ViewKind::Scroll,
                        } => probe.list = Some(id),
                        nsh_core::MountItem::Events { id, events }
                            if events.contains(nsh_core::EventKind::Press) =>
                        {
                            probe.press = Some(id)
                        }
                        nsh_core::MountItem::Command {
                            id,
                            command: nsh_core::Command::ScrollTo { x, y, .. },
                        } => {
                            probe.applied += 1;
                            probe.offset = point(x, y);
                            report = Some((id, probe.offset, probe.applied));
                        }
                        nsh_core::MountItem::ScrollBy { id, dx, dy } => {
                            probe.applied += 1;
                            probe.offset = point(probe.offset.x + dx, probe.offset.y + dy);
                            report = Some((id, probe.offset, probe.applied));
                        }
                        _ => {}
                    }
                }
                if let Some((id, offset, applied)) = report {
                    self.control.get().unwrap().scroll(id, offset, applied);
                }
            }
        }
        fn report_error(&self, message: &str) {
            self.probe.lock().unwrap().errors.push(message.into());
        }
        fn request_frame(&self) {
            self.control.get().unwrap().frame();
        }
    }
    fn await_probe(
        probe: &Arc<std::sync::Mutex<ScrollProbe>>,
        description: &str,
        done: impl Fn(&ScrollProbe) -> bool,
    ) {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
        loop {
            {
                let probe = probe.lock().unwrap();
                assert!(probe.errors.is_empty(), "{:?}", probe.errors);
                if done(&probe) {
                    return;
                }
            }
            assert!(
                std::time::Instant::now() < deadline,
                "{description} did not converge"
            );
            std::thread::sleep(std::time::Duration::from_millis(2));
        }
    }
    #[test]
    fn animated_scroll_success_waits_for_the_native_end_event_and_ignores_duplicates() {
        use nsh_core::platform::{Idiom, Os};
        use nsh_core::{EventKind, EventPayload};
        use nsh_engine::{Engine, EngineConfig, EngineContext, Environment, Root};
        // Headless applies ScrollTo immediately without a programmatic end
        // event. Drive the public platform boundary to test that distinction.
        let probe = Arc::new(std::sync::Mutex::new(ScrollProbe::default()));
        let control = Arc::new(std::sync::OnceLock::new());
        let setup = control.clone();
        let engine = Engine::start_with(
            EngineConfig {
                viewport: nsh_core::Size::new(px(400.0), px(96.0)),
                environment: Environment {
                    os: Os::Linux,
                    idiom: Idiom::Desktop,
                    ..Default::default()
                },
                context: EngineContext::default().with(ScrollContext(probe.clone())),
                content_culling: false,
                ..EngineConfig::new(Root::of::<ScrollFixture>())
            },
            || nsh_core::ApproxTextEngine,
            AnimatedPlatform {
                probe: probe.clone(),
                control,
            },
            move |control| {
                assert!(
                    setup.set(control.clone()).is_ok(),
                    "platform control is installed once"
                );
            },
        )
        .unwrap();
        await_probe(&probe, "native fixture root", |probe| probe.press.is_some());
        engine.control().dispatch_event(
            probe.lock().unwrap().press.unwrap(),
            EventKind::Press,
            EventPayload::None,
        );
        await_probe(&probe, "animated destination mounted", |probe| {
            probe.target_ready && probe.applied > 0
        });
        assert!(
            probe.lock().unwrap().outcomes.is_empty(),
            "merely materializing the animated target completed its token"
        );
        let (list, offset) = {
            let probe = probe.lock().unwrap();
            (probe.list.unwrap(), probe.offset)
        };
        engine
            .control()
            .dispatch_event(list, EventKind::ScrollEnd, EventPayload::Scroll(offset));
        await_probe(&probe, "native end completes requested token", |probe| {
            probe.outcomes == [(4, "succeeded".into())]
        });
        engine
            .control()
            .dispatch_event(list, EventKind::ScrollEnd, EventPayload::Scroll(offset));
        await_probe(&probe, "both native end events handled", |probe| {
            probe.scroll_ends == 2
        });
        assert_eq!(probe.lock().unwrap().outcomes, [(4, "succeeded".into())]);
    }
}
