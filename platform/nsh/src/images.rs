//! Canonical Image values translated to the public native Image host.
use crate::store::Node;
use nsh_core::{ResizeMode, element::ImageSrc};

mod file_image;
pub(crate) use file_image::source as file_source;
pub(crate) use file_image::thumbnail;

pub(crate) fn source(node: &Node) -> ImageSrc {
    ImageSrc::from(node.string("url").to_owned())
}

pub(crate) fn fit(node: &Node) -> ResizeMode {
    match node.string("image-fit") {
        "fit" => ResizeMode::Contain,
        "fill" => ResizeMode::Cover,
        _ if node.kind == "file-image" => ResizeMode::Contain,
        // Ordinary LUI images stretch when both dimensions are authored.
        _ => ResizeMode::Stretch,
    }
}

pub(crate) fn label(node: &Node) -> String {
    let label = node.string("accessibility-label");
    if label.is_empty() {
        node.string("alt").to_owned()
    } else {
        label.to_owned()
    }
}

/// These native restrictions supplement the generated canonical validator.
pub(crate) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "file-image" {
        return file_image::validate(node);
    }
    if node.kind != "image" {
        return Ok(());
    }
    if node.props.contains_key("image") {
        return Err("NSH Image resource IDs are not implemented; use url".into());
    }
    if ["source-x", "source-y", "source-width", "source-height"]
        .iter()
        .any(|property| node.props.contains_key(*property))
    {
        return Err("NSH Image source rectangles are not implemented yet".into());
    }
    if node.string("loading") == "lazy" {
        return Err("NSH Image lazy loading is not implemented yet".into());
    }
    if node.props.contains_key("referrer-policy") {
        return Err("NSH Image referrer-policy is not implemented yet".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn canonical_url_fit_and_accessible_name_preserve_image_defaults() {
        let mut node = Node {
            kind: "image".into(),
            props: serde_json::from_value(json!({
                "url":"file:///tmp/canonical-image.png", "alt":"A landscape"
            }))
            .unwrap(),
            ..Default::default()
        };
        crate::contract::validate_node(&node).unwrap();
        validate(&node).unwrap();
        assert_eq!(
            source(&node),
            ImageSrc::from("file:///tmp/canonical-image.png")
        );
        assert_eq!(fit(&node), ResizeMode::Stretch);
        assert_eq!(label(&node), "A landscape");
        node.props.insert("image-fit".into(), json!("fit"));
        assert_eq!(fit(&node), ResizeMode::Contain);
        node.props.insert("image-fit".into(), json!("fill"));
        assert_eq!(fit(&node), ResizeMode::Cover);
        node.props
            .insert("accessibility-label".into(), json!("Preview"));
        assert_eq!(label(&node), "Preview");
        node.props
            .insert("url".into(), json!("https://example.com/new.png"));
        assert_eq!(source(&node), ImageSrc::from("https://example.com/new.png"));
    }
}
