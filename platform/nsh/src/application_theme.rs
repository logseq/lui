//! Computed application theme snapshots over the existing scoped LUI resolver.
use crate::{store::Node, style::ThemeView};
use nsh_core::{element::Tokens, prelude::*};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{collections::BTreeMap, sync::Arc};

const ROLES: &[&str] = &[
    "background",
    "foreground",
    "card",
    "card-foreground",
    "primary",
    "primary-foreground",
    "secondary",
    "secondary-foreground",
    "accent",
    "accent-foreground",
    "muted",
    "muted-foreground",
    "destructive",
    "destructive-foreground",
    "input",
    "ring",
    "border",
    "success",
    "success-foreground",
    "warning",
    "warning-foreground",
    "error",
    "error-foreground",
];
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Mode {
    #[default]
    System,
    Light,
    Dark,
}
impl Mode {
    fn parse(mode: &str) -> Result<Self, String> {
        match mode {
            "" | "system" => Ok(Self::System),
            "light" => Ok(Self::Light),
            "dark" => Ok(Self::Dark),
            _ => Err("application theme mode requires system, light or dark".into()),
        }
    }
    fn dark(self, system: bool) -> bool {
        match self {
            Self::System => system,
            Self::Light => false,
            Self::Dark => true,
        }
    }
}

/// A producer-computed snapshot. Native code does not rebuild CSS cascade layers.
#[derive(Clone, Debug, PartialEq)]
pub struct ThemeSnapshot {
    dark: bool,
    encoded: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SnapshotWire {
    mode: String,
    vars: BTreeMap<String, String>,
}
impl ThemeSnapshot {
    /// Validates the payload and known native tokens before the registry changes.
    pub fn from_json(json: &str) -> Result<Self, String> {
        let wire: SnapshotWire =
            serde_json::from_str(json).map_err(|error| format!("theme snapshot: {error}"))?;
        let dark = match wire.mode.as_str() {
            "light" => false,
            "dark" => true,
            _ => return Err("theme snapshot requires light or dark mode".into()),
        };
        for name in wire.vars.keys() {
            if !name.starts_with("--")
                || name.len() <= 2
                || name.chars().any(|c| c.is_whitespace() || "(),".contains(c))
            {
                return Err(format!("invalid theme custom property {name}"));
            }
        }
        let mut values: serde_json::Map<String, Value> = wire
            .vars
            .into_iter()
            .map(|(name, value)| (name, Value::String(value)))
            .collect();
        for role in ROLES {
            let app = format!("--lui-{role}");
            let css = format!("--{role}");
            let value = if values.contains_key(&app) {
                Some(format!("var({app})"))
            } else if values.contains_key(&css) {
                Some(format!("hsl(var({css}))"))
            } else {
                None
            };
            if let Some(value) = value {
                values.insert((*role).into(), Value::String(value));
            }
        }
        for name in ["--lui-radius", "--radius"] {
            if values.contains_key(name) {
                values.insert("radius".into(), Value::String(format!("var({name})")));
                break;
            }
        }
        let snapshot = Self {
            dark,
            encoded: Value::Object(values).to_string(),
        };
        // The same resolver validates aliases, colors, radius and typography here
        // and resolves authored scoped values during native rendering.
        let theme = snapshot.overlay(
            ThemeView::new(Arc::new(Tokens::default()), dark, false),
            Some(dark),
        )?;
        for role in ROLES {
            if theme.has_value(role) {
                theme.color(role)?;
            }
        }
        theme.typography()?;
        Ok(snapshot)
    }
    fn overlay(&self, theme: ThemeView, mode: Option<bool>) -> Result<ThemeView, String> {
        let mut node = Node::default();
        node.props
            .insert("theme".into(), Value::String(self.encoded.clone()));
        if let Some(mode) = mode {
            node.props.insert(
                "theme-mode".into(),
                json!(if mode { "dark" } else { "light" }),
            );
        }
        theme.overlay(&node)
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
struct State {
    snapshots: [Option<Arc<ThemeSnapshot>>; 2],
    mode: Mode,
}
/// Create once under the app owner and provide above `Desktop`.
/// Appearance selection does not change NSH's real operating-system appearance.
#[derive(Clone, Copy)]
pub struct ThemeRegistry {
    state: Signal<Arc<State>>,
}
impl Default for ThemeRegistry {
    fn default() -> Self {
        Self::new()
    }
}
impl ThemeRegistry {
    pub fn new() -> Self {
        Self {
            state: signal(Arc::default()),
        }
    }
    pub fn install(&self, snapshot: ThemeSnapshot) -> bool {
        let state = self.state.get_untracked();
        let index = usize::from(snapshot.dark);
        if state.snapshots[index].as_deref() == Some(&snapshot) {
            return false;
        }
        let mut next = (*state).clone();
        next.snapshots[index] = Some(Arc::new(snapshot));
        self.state.set(Arc::new(next));
        true
    }
    pub fn install_snapshot_json(&self, json: &str) -> Result<bool, String> {
        Ok(self.install(ThemeSnapshot::from_json(json)?))
    }
    /// Pass `data.theme` from the existing ui-state message; absent/empty means system.
    pub fn set_mode(&self, mode: &str) -> Result<bool, String> {
        let mode = Mode::parse(mode)?;
        let state = self.state.get_untracked();
        if mode == state.mode {
            return Ok(false);
        }
        let mut next = (*state).clone();
        next.mode = mode;
        self.state.set(Arc::new(next));
        Ok(true)
    }
    /// Optional whole-surface NSH token projection for a standalone application.
    /// The caller owns `set_tokens`; embedding roots should use scoped rendering instead.
    pub fn native_tokens(
        &self,
        base: &Tokens,
        system_dark: bool,
        reduced_motion: bool,
    ) -> Result<Tokens, String> {
        let theme = self.apply(
            ThemeView::new(Arc::new(base.clone()), system_dark, reduced_motion),
            system_dark,
        )?;
        let mut next = base.clone();
        for role in ROLES {
            if theme.has_value(role) {
                next.set_color(role, theme.color(role)?);
            }
        }
        if theme.has_value("radius") {
            next.set_number("radius", theme.radius()?.0);
        }
        if let (Some(family), _) = theme.typography()? {
            next.set_font("font-sans", family);
        }
        Ok(next)
    }
    pub(crate) fn apply(&self, theme: ThemeView, system_dark: bool) -> Result<ThemeView, String> {
        let state = self.state.get();
        let mode = match state.mode {
            Mode::System => None,
            mode => Some(mode.dark(system_dark)),
        };
        if let Some(snapshot) = &state.snapshots[usize::from(state.mode.dark(system_dark))] {
            snapshot.overlay(theme, mode)
        } else if let Some(mode) = mode {
            let node = Node {
                props: json!({"theme-mode":if mode {"dark"} else {"light"}})
                    .as_object()
                    .unwrap()
                    .clone(),
                ..Node::default()
            };
            theme.overlay(&node)
        } else {
            Ok(theme)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        render::{Event, Renderer},
        wire::Batch,
    };
    use nsh_core::{Color, element::create_root};
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use std::{cell::Cell, rc::Rc};

    fn color(value: &str) -> nsh_core::element::AdaptiveColor {
        Color::parse(value).unwrap().into()
    }
    fn base(dark: bool) -> ThemeView {
        ThemeView::new(Arc::new(Tokens::default()), dark, false)
    }
    fn snapshot(mode: &str, color: &str) -> String {
        json!({"mode":mode,"vars":{
        "--lui-background":color,"--lui-foreground":"#121212","--lui-radius":"8px",
        "--lx-font-stack":"Inter, sans-serif","--lx-root-text-size":"16px",
        "--ls-primary-background-color":color}})
        .to_string()
    }
    #[component]
    fn SnapshotValidation() -> impl IntoElement {
        let (owner, ()) = create_root(|| {
            let registry = ThemeRegistry::new();
            registry
                .install_snapshot_json(&snapshot("light", "#ffffff"))
                .unwrap();
            registry
                .install_snapshot_json(&snapshot("dark", "#101010"))
                .unwrap();
            assert!(
                !registry
                    .install_snapshot_json(&snapshot("light", "#ffffff"))
                    .unwrap()
            );
            assert_eq!(
                registry
                    .apply(base(false), false)
                    .unwrap()
                    .color("background")
                    .unwrap()
                    .light,
                color("#ffffff").light
            );
            assert_eq!(
                registry
                    .apply(base(true), true)
                    .unwrap()
                    .color("background")
                    .unwrap()
                    .light,
                color("#101010").light
            );
            registry.set_mode("light").unwrap();
            let theme = registry.apply(base(true), true).unwrap();
            assert_eq!(
                theme.color("background").unwrap().dark,
                color("#ffffff").light
            );
            assert_eq!(
                theme.text("var(--ls-primary-background-color)").unwrap(),
                "#ffffff"
            );
            assert_eq!(
                theme.typography().unwrap(),
                (Some("Inter, sans-serif".into()), Some(px(16.0)))
            );
            for bad in [
                json!({"mode":"system","vars":{}}),
                json!({"mode":"light","vars":{"invalid":"red"}}),
                json!({"mode":"light","vars":{"--x":1}}),
                json!({"mode":"light","vars":{"--lui-background":"invalid"}}),
                json!({"mode":"light","vars":{"--lx-root-text-size":"0px"}}),
                json!({"mode":"light","vars":{"--bad(":"red"}}),
            ] {
                assert!(registry.install_snapshot_json(&bad.to_string()).is_err());
                assert_eq!(registry.apply(base(true), true).unwrap(), theme);
            }
            assert!(registry.set_mode("other").is_err());
            let native = registry
                .native_tokens(&Tokens::default(), true, false)
                .unwrap();
            assert_eq!(
                native.color("background").unwrap().dark,
                color("#ffffff").light
            );
            assert_eq!(
                native.font("font-sans").unwrap().as_ref(),
                "Inter, sans-serif"
            );
        });
        owner.dispose();
        text("Snapshots validated")
    }
    #[test]
    fn computed_snapshots_preserve_mode_atomicity_aliases_and_os_appearance() {
        Headless::start(EngineConfig::new(Root::of::<SnapshotValidation>()))
            .unwrap()
            .wait_for("Snapshots validated")
            .unwrap();
    }
    #[component]
    fn ScopedValidation() -> impl IntoElement {
        let (owner, ()) = create_root(|| {
            let registry = ThemeRegistry::new();
            registry.install_snapshot_json(r#"{"mode":"light","vars":{"--background":"0 0% 100%","--lui-primary":"var(--absent, #ff0000)"}}"#).unwrap();
            let theme = registry.apply(base(false), false).unwrap();
            assert_eq!(
                theme.color("background").unwrap().light,
                color("#ffffff").light
            );
            assert_eq!(
                theme.color("primary").unwrap().light,
                color("#ff0000").light
            );
            let scoped = Node {
                props: json!({"theme":"{\"primary\":\"#00ff00\"}"})
                    .as_object()
                    .unwrap()
                    .clone(),
                ..Node::default()
            };
            assert_eq!(
                theme
                    .overlay(&scoped)
                    .unwrap()
                    .color("primary")
                    .unwrap()
                    .light,
                color("#00ff00").light
            );
            registry.set_mode("dark").unwrap();
            let missing = registry.apply(base(false), false).unwrap();
            assert!(!missing.has_value("primary"));
            assert_eq!(
                missing.color("primary").unwrap().light,
                base(true).color("primary").unwrap().dark
            );
            let other = ThemeRegistry::new();
            assert!(
                !other
                    .apply(base(false), false)
                    .unwrap()
                    .has_value("primary")
            );
        });
        owner.dispose();
        text("Scoped theme validated")
    }
    #[test]
    fn css_channel_fallback_scoped_override_and_missing_snapshot_use_existing_resolver() {
        Headless::start(EngineConfig::new(Root::of::<ScopedValidation>()))
            .unwrap()
            .wait_for("Scoped theme validated")
            .unwrap();
    }
    fn patch(generation: u64, ops: Value) -> Batch {
        Batch::decode(&json!({"generation":generation,"ops":ops}).to_string()).unwrap()
    }
    #[component]
    fn ThemeSwitch() -> impl IntoElement {
        let registry = ThemeRegistry::new();
        provide_context(registry);
        registry
            .install_snapshot_json(&snapshot("light", "#ffffff"))
            .unwrap();
        registry
            .install_snapshot_json(&snapshot("dark", "#101010"))
            .unwrap();
        registry.set_mode("light").unwrap();
        let generation = Rc::new(Cell::new(1));
        let next = generation.clone();
        let renderer = Renderer::new(move |event, renderer| {
            if let Event::Text(id, text) = event {
                let generation = next.get() + 1;
                renderer
                    .apply(patch(
                        generation,
                        json!([{"op":"set-prop","id":id,"property":"text","value":text}]),
                    ))
                    .unwrap();
                next.set(generation);
            }
        });
        renderer
            .apply(patch(
                1,
                json!([
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"set-prop","id":1,"property":"background","value":"background"},
            {"op":"create-node","id":2,"kind":"text-field"},
            {"op":"set-prop","id":2,"property":"text","value":"retained"},
            {"op":"set-prop","id":2,"property":"change-enabled","value":true},
            {"op":"insert-child","parent":1,"child":2,"index":0}]),
            ))
            .unwrap();
        renderer.set_root(1).unwrap();
        on_key_with(
            "f7",
            KeyOptions {
                when: nsh_core::keymap::When::Always,
                ..Default::default()
            },
            move |_| {
                registry.set_mode("dark").unwrap();
            },
        );
        renderer.element()
    }
    #[test]
    fn changing_application_mode_preserves_native_editor_and_draft_focus() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<ThemeSwitch>())).unwrap();
        app.wait_for("id:lui-2").unwrap();
        let before = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("lui-2"))
            .unwrap();
        app.type_text("id:lui-2", " draft").unwrap();
        let edited = app
            .screen()
            .input_text("id:lui-2")
            .unwrap()
            .unwrap()
            .to_owned();
        app.press_key("f7").unwrap();
        app.press_key("x").unwrap();
        let after = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("lui-2"))
            .unwrap();
        assert_eq!(before.id, after.id);
        let continued = app.screen().input_text("id:lui-2").unwrap().unwrap();
        assert_eq!(continued.len(), edited.len() + 1);
        assert_eq!(continued.replace('x', ""), edited.replace('x', ""));
    }
}
