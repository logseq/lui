//! Application-owned SVG assets. NSH keeps ownership of decoding and drawing caches.
use crate::contract;
use nsh_core::{element::ImageSrc, prelude::*};
use serde_json::Value;
use std::{collections::BTreeMap, sync::Arc};

const MAX_TABLE_BYTES: usize = 32 * 1024 * 1024;
const MAX_ICON_BYTES: usize = 256 * 1024;
const MAX_ICONS: usize = 16_384;

/// A completely validated replacement table, prepared without native construction.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct IconTable(Arc<BTreeMap<String, ImageSrc>>);
impl IconTable {
    /// Names are unprefixed canonical application slugs; values are SVG markup.
    /// All entries are checked before a table can be installed.
    pub fn from_json(json: &str) -> Result<Self, String> {
        if json.len() > MAX_TABLE_BYTES {
            return Err("application icon table exceeds 32 MiB".into());
        }
        let value: Value =
            serde_json::from_str(json).map_err(|error| format!("application icons: {error}"))?;
        let object = value
            .as_object()
            .ok_or("application icons require an object of SVG strings")?;
        if object.len() > MAX_ICONS {
            return Err("application icon table exceeds 16384 entries".into());
        }
        let mut icons = BTreeMap::new();
        for (name, value) in object {
            contract::validate_value("icon", "name", &Value::String(format!("app:{name}")))?;
            let markup = value
                .as_str()
                .ok_or_else(|| format!("application icon {name} requires SVG markup"))?;
            if markup.len() > MAX_ICON_BYTES {
                return Err(format!("application icon {name} exceeds 256 KiB"));
            }
            let document = roxmltree::Document::parse(markup)
                .map_err(|error| format!("application icon {name}: {error}"))?;
            let root = document.root_element().tag_name();
            if root.name() != "svg"
                || root
                    .namespace()
                    .is_some_and(|namespace| namespace != "http://www.w3.org/2000/svg")
            {
                return Err(format!(
                    "application icon {name} requires an SVG document root"
                ));
            }
            icons.insert(name.clone(), ImageSrc::svg_markup(markup));
        }
        Ok(Self(Arc::new(icons)))
    }
}

/// Provide above `Desktop` once, then install app-icons before publishing its patches.
/// Signals and assets belong to that native root; there is no process-wide icon registry.
#[derive(Clone, Copy)]
pub struct IconRegistry {
    icons: Signal<Arc<BTreeMap<String, ImageSrc>>>,
}
impl Default for IconRegistry {
    fn default() -> Self {
        Self::new()
    }
}
impl IconRegistry {
    pub fn new() -> Self {
        Self {
            icons: signal(Arc::default()),
        }
    }
    /// Returns whether the table changed. Equal tables produce no native work.
    pub fn replace(&self, table: IconTable) -> bool {
        if self.icons.get_untracked() == table.0 {
            return false;
        }
        self.icons.set(table.0);
        true
    }
    /// Validates the whole message before replacing any currently visible asset.
    pub fn replace_json(&self, json: &str) -> Result<bool, String> {
        Ok(self.replace(IconTable::from_json(json)?))
    }
    /// Reactive lookup for an `app:` icon. Standard built-in names cannot be overridden.
    pub fn source(&self, name: &str) -> Option<ImageSrc> {
        let name = name.strip_prefix("app:")?;
        self.icons.get().get(name).cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_core::element::create_root;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use serde_json::json;
    use std::sync::{
        Mutex,
        atomic::{AtomicUsize, Ordering},
    };

    const SQUARE: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" d="M0 0h24v24H0z"/></svg>"#;
    const TRIANGLE: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" d="M0 0l24 24H0z"/></svg>"#;

    #[component]
    fn RegistryIsolation() -> impl IntoElement {
        let (first, ()) = create_root(|| {
            let registry = IconRegistry::new();
            assert!(
                registry
                    .replace_json(&json!({"sample":SQUARE}).to_string())
                    .unwrap()
            );
            let original = registry.source("app:sample").unwrap();
            assert!(
                !registry
                    .replace_json(&json!({"sample":SQUARE}).to_string())
                    .unwrap()
            );
            for invalid in [
                json!({"sample":TRIANGLE,"bad--name":SQUARE}),
                json!({"sample":TRIANGLE,"other":42}),
                json!({"sample":"<svg>"}),
                json!({"sample":"<div/>"}),
                json!({"sample":"<svg xmlns='urn:other'/>"}),
            ] {
                assert!(registry.replace_json(&invalid.to_string()).is_err());
                assert_eq!(registry.source("app:sample"), Some(original.clone()));
            }
            assert!(registry.source("sample").is_none());
            let (second, ()) = create_root(|| {
                let other = IconRegistry::new();
                assert!(other.source("app:sample").is_none());
                other
                    .replace_json(&json!({"sample":TRIANGLE}).to_string())
                    .unwrap();
                assert_ne!(other.source("app:sample"), Some(original.clone()));
            });
            second.dispose();
            assert_eq!(registry.source("app:sample"), Some(original));
        });
        first.dispose();
        text("Independent icon registries")
    }

    #[test]
    fn table_validation_is_atomic_and_registry_owners_are_independent() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<RegistryIsolation>())).unwrap();
        app.wait_for("Independent icon registries").unwrap();
    }

    #[component]
    fn LiveIcons() -> impl IntoElement {
        let registry = IconRegistry::new();
        provide_context(registry);
        registry
            .replace_json(&json!({"sample":SQUARE}).to_string())
            .unwrap();
        view()
            .child(crate::ui::icon("app:sample", px(20.0)).test_id("live-icon"))
            .child(crate::ui::icon("search", px(20.0)).test_id("builtin-icon"))
            .child(
                nsh_base::button()
                    .child(text("Replace icon"))
                    .on_press(move || {
                        registry
                            .replace_json(&json!({"sample":TRIANGLE}).to_string())
                            .unwrap();
                    }),
            )
            .child(
                nsh_base::button()
                    .child(text("Repeat icon"))
                    .on_press(move || {
                        assert!(
                            !registry
                                .replace_json(&json!({"sample":TRIANGLE}).to_string())
                                .unwrap()
                        );
                    }),
            )
    }
    #[test]
    fn changing_application_svg_updates_the_existing_native_canvas_only() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<LiveIcons>())).unwrap();
        app.wait_for("id:live-icon").unwrap();
        let nodes = app.screen().layout_nodes();
        let icon = nodes
            .iter()
            .find(|node| node.test_id.as_deref() == Some("live-icon"))
            .unwrap()
            .clone();
        let builtin = nodes
            .iter()
            .find(|node| node.test_id.as_deref() == Some("builtin-icon"))
            .unwrap()
            .id;
        let draws = Arc::new(AtomicUsize::new(0));
        let updates = draws.clone();
        let builtin_draws = Arc::new(Mutex::new(Vec::new()));
        let other = builtin_draws.clone();
        let id = icon.id;
        app.observe(move |_, batch| {
            for item in &batch.items {
                if let nsh_core::MountItem::Canvas { id: changed, .. } = item {
                    if *changed == id {
                        updates.fetch_add(1, Ordering::SeqCst);
                    }
                    if *changed == builtin {
                        other.lock().unwrap().push(*changed);
                    }
                }
            }
        });
        app.press("Replace icon").unwrap();
        assert!(draws.load(Ordering::SeqCst) > 0);
        assert!(builtin_draws.lock().unwrap().is_empty());
        let count = draws.load(Ordering::SeqCst);
        app.press("Repeat icon").unwrap();
        assert_eq!(draws.load(Ordering::SeqCst), count);
        let after = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("live-icon"))
            .unwrap();
        assert_eq!(after.id, icon.id);
        assert_eq!(after.bounds, icon.bounds);
    }
}
