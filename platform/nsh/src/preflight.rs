//! Validate statically captured application presentation through its real provider.
//! The target build supplies encoded properties and its own computed theme values.
use crate::{application_theme::ThemeSnapshot, store::Node, style};
use nsh_core::{
    element::Tokens,
    geometry::{Size, px},
};
use serde::Deserialize;
use serde_json::{Map, Value};
use std::sync::Arc;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    themes: Vec<Value>,
    sites: Vec<Site>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Site {
    location: String,
    kind: String,
    props: Map<String, Value>,
}

/// Checks the compiled target's literal presentation sites before opening a window.
/// Uses the same theme resolver and style compiler as Renderer; it does not keep
/// another property grammar. Unresolved scoped theme variables remain dynamic.
/// This gate does not prove event routing, arbitrary dynamic values or layout.
pub fn validate_styles(encoded: &str) -> Result<String, String> {
    let manifest: Manifest = serde_json::from_str(encoded)
        .map_err(|error| format!("invalid native style manifest: {error}"))?;
    if manifest.sites.is_empty() {
        return Err("native style preflight captured no literal presentation sites".into());
    }
    if manifest.themes.is_empty() {
        return Err("native style preflight requires application theme snapshots".into());
    }
    let mut failures = Vec::new();
    let mut deferred = 0;
    for wire in &manifest.themes {
        let snapshot = ThemeSnapshot::from_json(&wire.to_string())?;
        let dark = wire["mode"] == "dark";
        let theme = snapshot.overlay(
            style::ThemeView::new(Arc::new(Tokens::default()), dark, false),
            Some(dark),
        )?;
        for site in &manifest.sites {
            let node = Node {
                kind: site.kind.clone(),
                props: site.props.clone(),
                ..Default::default()
            };
            if let Err(error) = style::compile(&node, &theme, Size::new(px(1280.), px(800.))) {
                if error.starts_with("NSH unresolved theme variable --") {
                    deferred += 1;
                } else {
                    failures.push(format!(
                        "{} [{}]: {}: {error}",
                        site.location,
                        wire["mode"].as_str().expect("validated snapshot mode"),
                        site.kind
                    ));
                }
            }
        }
    }
    failures.sort();
    failures.dedup();
    if !failures.is_empty() {
        return Err(failures.join("\n"));
    }
    Ok(format!(
        "PASS native style preflight: {} literal sites, {} themes, {deferred} scoped-variable checks deferred to runtime",
        manifest.sites.len(),
        manifest.themes.len()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn actual_provider_rejects_bad_literals_and_keeps_scoped_values_dynamic() {
        let manifest = |props| {
            json!({"themes":[{"mode":"light","vars":{}}],
            "sites":[{"location":"view.ml:12:3","kind":"column","props":props}]})
            .to_string()
        };
        assert!(
            validate_styles(&manifest(json!({"cursor":"invalid-cursor"})))
                .unwrap_err()
                .contains("view.ml:12:3")
        );
        assert!(validate_styles(&manifest(json!({"overflow":"auto"}))).is_err());
        assert!(validate_styles(&manifest(json!({"opacity":0.5,"font-size":"16px"}))).is_ok());
        assert!(
            validate_styles(&manifest(json!({"font-size":"var(--local-text-size)"})))
                .unwrap()
                .contains("deferred")
        );
    }
}
