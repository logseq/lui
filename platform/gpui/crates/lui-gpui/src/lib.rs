//! GPUI renderer for the LUI retained node tree, built entirely on gpui-kit
//! (`gpui_kit::component` / `gpui_kit::base`), never on raw gpui widgets.
//!
//! Every mounted LUI node has its own [`LuiNodeView`] entity. Patches notify
//! changed views without acquiring their update leases. GPUI caches explicitly
//! sized stateless leaves; content-sized and stateful nodes keep normal layout
//! measurement. Virtual lists only render visible rows and a focused row.

pub mod backend;
pub mod dock;
pub mod dom;
pub mod domops;
pub mod extension;
pub mod kinds;
pub mod node_view;
#[cfg(test)]
pub mod ocaml_stubs;
pub mod root;
pub mod scroll;
pub mod style;
pub mod theme;
mod virtual_list;
mod measured_text;

pub use backend::{apply_batch_json, drain_pending, fire, LuiShared, Shared};
pub use node_view::{LuiNodeView, NodeSnapshot};
pub use root::LuiRootView;
pub use theme::init;
