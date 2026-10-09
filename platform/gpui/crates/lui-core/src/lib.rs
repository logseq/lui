//! Portable LUI wire-protocol core for the GPUI backend.
//!
//! Consumes JSON `patch_batch` objects emitted by the OCaml runtime over the
//! `platform/native` C bridge and maintains the retained node tree. UI-layer
//! crates (lui-gpui) read this tree; nothing here depends on GPUI.

pub mod bridge;
pub mod event;
pub mod extension;
mod order;
mod protocol_rules;
pub mod store;
mod validation;
pub mod wire;
pub mod wire_schema;

pub use event::{event_allowed, event_supported, EventKind};
pub use extension::{ExtensionRegistry, ExtensionSpec};
pub use store::{Applied, BackendError, Node, NodeIdentity, Store};
pub use wire::{decode_batch, Batch, Op, Value};
pub use wire_schema::{kind_extra_properties, kind_property_matrix, NodeKind, Property};
