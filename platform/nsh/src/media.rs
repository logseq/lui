//! A native video host; NSH owns decoding, playback controls and audio.
use crate::store::Node;
use nsh_core::prelude::*;
use std::{rc::Rc, sync::Arc};

pub(crate) fn validate(node: &Node) -> Result<(), String> {
    if node.kind != "media-surface" {
        return Ok(());
    }
    if node.props.contains_key("surface") {
        return Err("NSH MediaSurface accepts native video URLs; foreign surface resource IDs are not implemented".into());
    }
    if node.string("url").trim().is_empty() {
        return Err("NSH MediaSurface requires a nonempty native video URL".into());
    }
    Ok(())
}

pub(crate) fn element(node: Signal<Arc<Node>>, failed: Rc<dyn Fn(String)>) -> Video {
    video(move || node.get().string("url").to_owned())
        .controls(true)
        .on_error(move |message: &str| failed(format!("Native video: {message}")))
}
