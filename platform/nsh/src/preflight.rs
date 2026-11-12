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
            let failure = |error: &str| {
                format!(
                    "{} [{}]: {}: {error}",
                    site.location,
                    wire["mode"].as_str().expect("validated snapshot mode"),
                    site.kind
                )
            };
            // Reuse provider capability rules on the complete captured site.
            // Its dynamic/omitted text must stay at the runtime value boundary.
            if let Err(error) = crate::inputs::validate_capabilities(&node) {
                failures.push(failure(&error));
            }
            // An unresolved scoped variable in one field must not hide a
            // statically invalid grammar in another field on the same node.
            let candidates =
                std::iter::once(node.clone()).chain(site.props.iter().map(|(name, value)| Node {
                    kind: site.kind.clone(),
                    props: Map::from_iter([(name.clone(), value.clone())]),
                    ..Default::default()
                }));
            for candidate in candidates {
                if let Err(error) =
                    style::compile(&candidate, &theme, Size::new(px(1280.), px(800.)))
                {
                    if error.starts_with("NSH unresolved theme variable --") {
                        deferred += 1;
                    } else {
                        failures.push(failure(&error));
                    }
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
            validate_styles(&manifest(
                json!({"font-size":"var(--local-text-size)","cursor":"invalid-cursor"})
            ))
            .is_err()
        );
        assert!(
            validate_styles(&manifest(json!({"font-size":"var(--local-text-size)"})))
                .unwrap()
                .contains("deferred")
        );
    }

    #[test]
    fn time_capabilities_are_checked_without_parsing_unknown_text() {
        let manifest = |props| {
            json!({"themes":[{"mode":"light","vars":{}}],
                "sites":[{"location":"time_view.ml:7:4","kind":"input","props":props}]})
            .to_string()
        };
        assert!(validate_styles(&manifest(json!({"input-type":"time"}))).is_ok());
        for flag in [
            "read-only",
            "autofocus",
            "navigate-enabled",
            "dismiss-enabled",
        ] {
            let error =
                validate_styles(&manifest(json!({"input-type":"time",flag:true}))).unwrap_err();
            assert!(error.contains("time_view.ml:7:4"), "{error}");
            assert!(
                error.contains(&format!("NSH TimeField does not expose {flag}")),
                "{error}"
            );
            assert!(validate_styles(&manifest(json!({"input-type":"time",flag:false}))).is_ok());
            assert!(validate_styles(&manifest(json!({flag:true}))).is_ok());
        }
        assert!(
            validate_styles(&manifest(json!({"input-type":"time","placeholder":"Time"})))
                .unwrap_err()
                .contains("TimeField does not expose a placeholder")
        );
        assert!(
            validate_styles(&manifest(
                json!({"input-type":"time","dismiss-enabled":true,
                "font-size":"var(--local-size)"})
            ))
            .unwrap_err()
            .contains("TimeField does not expose dismiss-enabled")
        );
        assert!(
            validate_styles(&manifest(json!({"input-type":"color"})))
                .unwrap_err()
                .contains("input-type=color is not implemented")
        );
        let node = Node {
            kind: "input".into(),
            props: serde_json::from_value(json!({"input-type":"time","dismiss-enabled":true}))
                .unwrap(),
            ..Default::default()
        };
        assert!(
            crate::inputs::validate(&node)
                .unwrap_err()
                .contains("requires nonempty")
        );
    }
}
