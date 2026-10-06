//! Host theme bootstrap for the LUI gpui backend.
//!
//! `gpui_kit::init` installs gpui-component's registered default theme
//! (light), the semantic token layer (`Theme::semantic_tokens`) and the
//! scrollbar projection into `gpui-base`. On top of that LUI tracks the
//! system appearance: the light/dark theme the app should present is the
//! OS one, so init starts from the system appearance and [`LuiRootView`]
//! re-syncs when the window appearance changes.

use gpui_kit::component::theme::Theme;
use gpui_kit::gpui::{App, Window};

/// Initialize the gpui-kit + gpui-component stack and sync the theme to
/// the system appearance. Call once inside `app.run` before opening any
/// LUI window (replaces a bare `gpui_kit::init` call).
pub fn init(cx: &mut App) {
    gpui_kit::init(cx);
    Theme::sync_system_appearance(None, cx);
}

/// Re-apply the registered theme for a window appearance change.
/// `LuiRootView` calls this from its appearance subscription.
pub(crate) fn sync_window_appearance(window: &mut Window, cx: &mut App) {
    Theme::sync_system_appearance(Some(window), cx);
}
