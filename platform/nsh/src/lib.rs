//! NSH desktop renderer for LUI's retained patch protocol.
pub mod app;
pub mod contract;
mod controls;
mod desktop_updates;
mod events;
mod headings;
mod images;
mod inputs;
pub mod render;
pub mod runtime;
pub mod store;
mod style;
mod ui;
pub mod update;
mod virtual_rows;
pub mod wire;

pub use app::{Desktop, DesktopProps};
use nsh_core::prelude::*;

/// Standalone desktop application with optional packaged update actions.
/// Embedded applications can use `Desktop` to retain their own menu ownership.
#[component]
pub fn DesktopApp() -> impl IntoElement {
    desktop_updates::mount();
    app::desktop()
}

/// The Rust application root, also described to NSH's runner generator.
#[native_module("lui/nsh")]
fn native(registry: &mut Registry) {
    registry.register::<Desktop>();
    registry.register::<DesktopApp>();
}
mod agent;
