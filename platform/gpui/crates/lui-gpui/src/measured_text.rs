//! Retain the same text layout used for drawing, without adding a layout box.

use crate::backend::Shared;
use gpui_kit::gpui::{
    App, Bounds, Element, ElementId, GlobalElementId, InspectorElementId, IntoElement, LayoutId,
    Pixels, StyledText, Window,
};

pub(crate) struct MeasuredText {
    inner: StyledText,
    node_id: i64,
    shared: Shared,
}

impl MeasuredText {
    pub(crate) fn new(text: String, node_id: i64, shared: Shared) -> Self {
        Self {
            inner: StyledText::new(text),
            node_id,
            shared,
        }
    }
}

impl IntoElement for MeasuredText {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl Element for MeasuredText {
    type RequestLayoutState = ();
    type PrepaintState = ();

    fn id(&self) -> Option<ElementId> {
        None
    }
    fn source_location(&self) -> Option<&'static std::panic::Location<'static>> {
        None
    }

    fn request_layout(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, ()) {
        self.inner.request_layout(id, inspector, window, cx)
    }

    fn prepaint(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        state: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        self.inner
            .prepaint(id, inspector, bounds, state, window, cx);
        self.shared
            .borrow_mut()
            .text_layouts
            .insert(self.node_id, self.inner.layout().clone());
    }

    fn paint(
        &mut self,
        id: Option<&GlobalElementId>,
        inspector: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        state: &mut (),
        prepaint: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) {
        self.inner
            .paint(id, inspector, bounds, state, prepaint, window, cx);
    }
}
