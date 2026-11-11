use super::{Pixels, byte_len, check_cap, scaled};
use gdk_pixbuf::{PixbufLoader, glib, prelude::*};
use std::{cell::Cell, path::PathBuf, rc::Rc};

pub(super) fn documents() -> Result<PathBuf, String> {
    glib::user_special_dir(glib::UserDirectory::Documents)
        .ok_or_else(|| "Documents directory is unavailable".into())
}

pub(super) fn decode(bytes: &[u8], cap: u32) -> Result<Pixels, String> {
    check_cap(cap)?;
    let loader = PixbufLoader::new();
    let invalid = Rc::new(Cell::new(false));
    let check = invalid.clone();
    loader.connect_size_prepared(move |loader, width, height| {
        if let Ok((w, h)) = scaled(width.max(0) as u32, height.max(0) as u32, cap) {
            loader.set_size(w as i32, h as i32);
        } else {
            check.set(true);
            loader.set_size(1, 1);
        }
    });
    let written = loader.write(bytes).map_err(|e| e.to_string());
    let closed = loader.close().map_err(|e| e.to_string());
    written?;
    closed?;
    if invalid.get() {
        return Err("invalid local image dimensions".into());
    }
    let pixbuf = loader
        .pixbuf()
        .ok_or("native image decoder returned no pixels")?;
    let pixbuf = pixbuf
        .apply_embedded_orientation()
        .ok_or("invalid image orientation")?;
    let (width, height) = (pixbuf.width() as u32, pixbuf.height() as u32);
    let len = byte_len(width, height, cap)?;
    let channels = pixbuf.n_channels() as usize;
    if pixbuf.bits_per_sample() != 8 || !(3..=4).contains(&channels) {
        return Err("unsupported native thumbnail pixel format".into());
    }
    let data = pixbuf
        .pixel_bytes()
        .ok_or("native thumbnail has no pixel storage")?;
    let stride = usize::try_from(pixbuf.rowstride()).map_err(|_| "invalid native row stride")?;
    let mut rgba = vec![0; len];
    for y in 0..height as usize {
        let start = y.checked_mul(stride).ok_or("native row overflow")?;
        let row_len = width as usize * channels;
        let row = data
            .get(start..start.checked_add(row_len).ok_or("native row overflow")?)
            .ok_or("native thumbnail row is truncated")?;
        for (source, target) in row
            .chunks_exact(channels)
            .zip(rgba[y * width as usize * 4..].chunks_exact_mut(4))
        {
            target[..3].copy_from_slice(&source[..3]);
            target[3] = if channels == 4 { source[3] } else { 255 };
        }
    }
    Ok(Pixels {
        width,
        height,
        rgba,
    })
}
