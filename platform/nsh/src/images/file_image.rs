//! Bounded local thumbnails fed to the retained NSH Image, without another cache.
use crate::store::Node;
use nsh_core::{
    element::ImageSrc,
    image::loader::{Priority, loader},
    prelude::*,
};
use std::{
    future::Future,
    io::Read,
    path::{Path, PathBuf},
    sync::Arc,
};

#[cfg(target_os = "linux")]
#[path = "file_image/linux.rs"]
mod native;
#[cfg(target_os = "macos")]
#[path = "file_image/macos.rs"]
mod native;
#[cfg(target_os = "windows")]
#[path = "file_image/windows.rs"]
mod native;

const DEFAULT_CAP: u32 = 1024;
const MAX_CAP: u32 = 4096;
const MAX_ENCODED_BYTES: u64 = 64 << 20;

#[derive(Clone, Debug, PartialEq, Eq)]
struct Request {
    path: String,
    cap: u32,
}
impl Request {
    fn read(node: &Node) -> Self {
        Self {
            path: node.string("path").to_owned(),
            cap: node.number("max-pixel-size", DEFAULT_CAP as f64) as u32,
        }
    }
}

pub(super) fn validate(node: &Node) -> Result<(), String> {
    let request = Request::read(node);
    check_cap(request.cap)?;
    local_path(&request.path)?;
    Ok(())
}

fn check_cap(cap: u32) -> Result<(), String> {
    if cap == 0 || cap > MAX_CAP {
        return Err(format!(
            "NSH FileImage max-pixel-size must be between 1 and {MAX_CAP}"
        ));
    }
    Ok(())
}

/// Path parsing stays pure; filesystem access and Documents lookup run off-thread.
fn local_path(path: &str) -> Result<PathBuf, String> {
    if path.is_empty() {
        return Err("NSH FileImage requires a local path".into());
    }
    let literal = Path::new(path);
    if literal.is_absolute() {
        return Ok(literal.into());
    }
    if let Ok(url) = url::Url::parse(path) {
        return url
            .to_file_path()
            .map_err(|_| "NSH FileImage accepts only local file paths or file URLs".into());
    }
    Ok(literal.into())
}

struct Pixels {
    width: u32,
    height: u32,
    rgba: Vec<u8>,
}
impl Pixels {
    fn source(self, cap: u32) -> Result<ImageSrc, String> {
        if self.rgba.len() != byte_len(self.width, self.height, cap)? {
            return Err("native thumbnail returned an invalid RGBA stride".into());
        }
        Ok(ImageSrc::rgba(self.width, self.height, self.rgba))
    }
}

fn byte_len(width: u32, height: u32, cap: u32) -> Result<usize, String> {
    if cap == 0 || cap > MAX_CAP || width == 0 || height == 0 || width > cap || height > cap {
        return Err("native thumbnail exceeds its pixel bound".into());
    }
    (width as usize)
        .checked_mul(height as usize)
        .and_then(|n| n.checked_mul(4))
        .ok_or_else(|| "native thumbnail byte count overflow".into())
}

#[cfg(any(test, target_os = "linux", target_os = "windows"))]
fn scaled(width: u32, height: u32, cap: u32) -> Result<(u32, u32), String> {
    if width == 0 || height == 0 || cap == 0 || cap > MAX_CAP {
        return Err("invalid native thumbnail dimensions".into());
    }
    let longest = width.max(height);
    if longest <= cap {
        return Ok((width, height));
    }
    let side = |n: u32| (u64::from(n) * u64::from(cap) / u64::from(longest)).max(1) as u32;
    Ok((side(width), side(height)))
}

fn read_file(path: &Path) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    std::fs::File::open(path)
        .map_err(|e| e.to_string())?
        .take(MAX_ENCODED_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > MAX_ENCODED_BYTES {
        return Err("FileImage encoded file exceeds 64 MiB".into());
    }
    Ok(bytes)
}

async fn load(request: Request) -> Result<ImageSrc, String> {
    check_cap(request.cap)?;
    let (send, receive) = tokio::sync::oneshot::channel();
    let ticket = loader().decode(Priority::Visible, move || {
        let result = (|| {
            let path = local_path(&request.path)?;
            let path = if path.is_absolute() {
                path
            } else {
                native::documents()?.join(path)
            };
            native::decode(&read_file(&path)?, request.cap)?.source(request.cap)
        })();
        let _ = send.send(result);
    });
    let result = receive
        .await
        .map_err(|_| "FileImage decode cancelled".to_owned());
    drop(ticket);
    result?
}

/// Shared by local preview surfaces; NSH owns scheduling and the displayed image.
pub(crate) async fn thumbnail(path: String, cap: u32) -> Result<ImageSrc, String> {
    load(Request { path, cap }).await
}

pub(crate) fn source(node: Signal<Arc<Node>>) -> impl Fn() -> ImageSrc {
    source_with(node, |request| super::thumbnail(request.path, request.cap))
}

fn source_with<F, Fut>(node: Signal<Arc<Node>>, fetch: F) -> impl Fn() -> ImageSrc
where
    F: Fn(Request) -> Fut + 'static,
    Fut: Future<Output = Result<ImageSrc, String>> + 'static,
{
    let request = computed(move || Request::read(&node.get()));
    let image = resource(
        move || Some(request.get()),
        move |request, _| fetch(request),
    );
    move || {
        // Resource retains its previous value while loading and on failure.
        // Never show the previous file under a newly authored path.
        if image.loading() || image.error().is_some() {
            ImageSrc::from("")
        } else {
            image.get().unwrap_or_else(|| ImageSrc::from(""))
        }
    }
}

#[cfg(test)]
mod tests;
