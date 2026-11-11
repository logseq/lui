use super::{Pixels, byte_len, check_cap};
use objc2_core_foundation::{
    CFData, CFDictionary, CFNumber, CFString, CFType, CGPoint, CGRect, CGSize, kCFBooleanTrue,
};
use objc2_core_graphics::{
    CGBitmapContextCreate, CGColorSpace, CGContext, CGImage, CGImageAlphaInfo,
    CGImageByteOrderInfo, kCGColorSpaceSRGB,
};
use objc2_foundation::{
    NSSearchPathDirectory, NSSearchPathDomainMask, NSSearchPathForDirectoriesInDomains,
};
use objc2_image_io::{
    CGImageSource, kCGImageSourceCreateThumbnailFromImageAlways,
    kCGImageSourceCreateThumbnailWithTransform, kCGImageSourceShouldCacheImmediately,
    kCGImageSourceThumbnailMaxPixelSize,
};
use std::path::PathBuf;

pub(super) fn documents() -> Result<PathBuf, String> {
    objc2::rc::autoreleasepool(|_| {
        NSSearchPathForDirectoriesInDomains(
            NSSearchPathDirectory::DocumentDirectory,
            NSSearchPathDomainMask::UserDomainMask,
            true,
        )
        .firstObject()
        .map(|path| PathBuf::from(path.to_string()))
        .ok_or_else(|| "Documents directory is unavailable".into())
    })
}

pub(super) fn decode(bytes: &[u8], cap: u32) -> Result<Pixels, String> {
    check_cap(cap)?;
    let data = CFData::from_bytes(bytes);
    // SAFETY: ImageIO receives live CF data and an option dictionary with the
    // documented CFBoolean/CFNumber types. Only the first thumbnail is decoded.
    unsafe {
        let source = CGImageSource::with_data(&data, None).ok_or("unsupported local image")?;
        let yes: &CFType = kCFBooleanTrue.ok_or("CFBoolean unavailable")?;
        let limit = match nsh_core::image::Natural::of(bytes) {
            Some(nsh_core::image::Natural::Pixels(w, h)) => cap.min(w.max(h)),
            _ => cap,
        };
        let max = CFNumber::new_cgfloat(limit as f64);
        let keys: [&CFString; 4] = [
            kCGImageSourceCreateThumbnailFromImageAlways,
            kCGImageSourceCreateThumbnailWithTransform,
            kCGImageSourceShouldCacheImmediately,
            kCGImageSourceThumbnailMaxPixelSize,
        ];
        let values: [&CFType; 4] = [yes, yes, yes, &max];
        let options = CFDictionary::from_slices(&keys, &values);
        let image = source
            .thumbnail_at_index(0, Some(options.as_opaque()))
            .ok_or("cannot decode local thumbnail")?;
        let width =
            u32::try_from(CGImage::width(Some(&image))).map_err(|_| "thumbnail width overflow")?;
        let height = u32::try_from(CGImage::height(Some(&image)))
            .map_err(|_| "thumbnail height overflow")?;
        let mut rgba = vec![0; byte_len(width, height, cap)?];
        let space = CGColorSpace::with_name(Some(kCGColorSpaceSRGB)).ok_or("sRGB unavailable")?;
        let context = CGBitmapContextCreate(
            rgba.as_mut_ptr().cast(),
            width as usize,
            height as usize,
            8,
            width as usize * 4,
            Some(&space),
            CGImageAlphaInfo::PremultipliedLast.0 | CGImageByteOrderInfo::Order32Big.0,
        )
        .ok_or("cannot allocate thumbnail bitmap")?;
        CGContext::draw_image(
            Some(&context),
            CGRect::new(CGPoint::ZERO, CGSize::new(width as f64, height as f64)),
            Some(&image),
        );
        drop(context);
        // ImageSrc::rgba takes straight alpha; Quartz draws premultiplied RGBA.
        for pixel in rgba.chunks_exact_mut(4) {
            let alpha = u32::from(pixel[3]);
            if alpha > 0 && alpha < 255 {
                for channel in &mut pixel[..3] {
                    *channel = ((u32::from(*channel) * 255 + alpha / 2) / alpha).min(255) as u8;
                }
            }
        }
        Ok(Pixels {
            width,
            height,
            rgba,
        })
    }
}
