//! GPUI renderer for the LUI retained node tree, built entirely on gpui-kit
//! (`gpui_kit::component` / `gpui_kit::base`), never on raw gpui widgets.
//!
//! Rendering model — minimal granularity (hard requirement):
//! every LUI node maps to one [`Entity<LuiNodeView>`]. A view only re-renders
//! when its own `cx.notify()` fires; child views are embedded as entity
//! handles, so a parent redraw never re-renders unchanged subtrees (GPUI
//! reuses their prepaint via `window.dirty_views`). Patch application returns
//! the dirty node set, and we notify exactly those entities.

pub mod backend;
pub mod extension;
pub mod kinds;
pub mod node_view;
pub mod root;
pub mod style;

pub use backend::{apply_batch_json, drain_pending, fire, LuiShared, Shared};
pub use node_view::{LuiNodeView, NodeSnapshot};
pub use root::LuiRootView;
