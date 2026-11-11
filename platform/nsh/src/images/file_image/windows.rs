use super::{Pixels, byte_len, check_cap, scaled};
use std::path::PathBuf;
use windows::{
    Win32::{
        Graphics::Imaging::{
            CLSID_WICImagingFactory, GUID_WICPixelFormat32bppRGBA, IWICBitmapFrameDecode,
            IWICBitmapSource, IWICImagingFactory, WICBitmapInterpolationModeFant,
            WICBitmapTransformFlipHorizontal, WICBitmapTransformFlipVertical,
            WICBitmapTransformOptions, WICBitmapTransformRotate0, WICBitmapTransformRotate90,
            WICBitmapTransformRotate180, WICBitmapTransformRotate270, WICConvertBitmapSource,
            WICDecodeMetadataCacheOnDemand,
        },
        System::Com::{
            CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED, CoCreateInstance, CoInitializeEx,
            CoTaskMemFree,
            StructuredStorage::{PROPVARIANT, PropVariantClear, PropVariantToUInt32},
        },
        UI::Shell::{FOLDERID_Documents, KF_FLAG_DEFAULT, SHGetKnownFolderPath},
    },
    core::{Interface, w},
};

pub(super) fn documents() -> Result<PathBuf, String> {
    // SAFETY: the shell returns an owned UTF-16 path; it is copied before its
    // COM allocation is released with CoTaskMemFree.
    unsafe {
        let path = SHGetKnownFolderPath(&FOLDERID_Documents, KF_FLAG_DEFAULT, None)
            .map_err(|e| e.to_string())?;
        let text = path.to_string().map_err(|e| e.to_string());
        CoTaskMemFree(Some(path.0.cast()));
        text.map(PathBuf::from)
    }
}

thread_local! {
    static WIC: Option<IWICImagingFactory> = {
        // SAFETY: NSH decode threads live for the process; COM belongs to each
        // thread. An already initialized apartment is retained as configured.
        let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
        unsafe { CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER) }.ok()
    };
}

pub(super) fn decode(bytes: &[u8], cap: u32) -> Result<Pixels, String> {
    check_cap(cap)?;
    WIC.with(|wic| {
        let wic = wic.as_ref().ok_or("WIC factory unavailable")?;
        let error = |e: windows::core::Error| e.to_string();
        // SAFETY: COM objects remain on their decode thread; the source bytes
        // outlive the stream and CopyPixels receives checked bounded storage.
        unsafe {
            let stream = wic.CreateStream().map_err(error)?;
            stream.InitializeFromMemory(bytes).map_err(error)?;
            let decoder = wic
                .CreateDecoderFromStream(&stream, std::ptr::null(), WICDecodeMetadataCacheOnDemand)
                .map_err(error)?;
            let frame = decoder.GetFrame(0).map_err(error)?;
            let source: IWICBitmapSource = frame.cast().map_err(error)?;
            let (mut width, mut height) = (0, 0);
            source.GetSize(&mut width, &mut height).map_err(error)?;
            let (width, height) = scaled(width, height, cap)?;
            let scaler = wic.CreateBitmapScaler().map_err(error)?;
            scaler
                .Initialize(&source, width, height, WICBitmapInterpolationModeFant)
                .map_err(error)?;
            let mut source: IWICBitmapSource = scaler.cast().map_err(error)?;
            let transform = orientation(&frame);
            if transform != WICBitmapTransformRotate0 {
                let rotated = wic.CreateBitmapFlipRotator().map_err(error)?;
                rotated.Initialize(&source, transform).map_err(error)?;
                source = rotated.cast().map_err(error)?;
            }
            let source =
                WICConvertBitmapSource(&GUID_WICPixelFormat32bppRGBA, &source).map_err(error)?;
            let (mut width, mut height) = (width, height);
            source.GetSize(&mut width, &mut height).map_err(error)?;
            let mut rgba = vec![0; byte_len(width, height, cap)?];
            source
                .CopyPixels(std::ptr::null(), width * 4, &mut rgba)
                .map_err(error)?;
            Ok(Pixels {
                width,
                height,
                rgba,
            })
        }
    })
}

// ImageIO and GdkPixbuf apply embedded orientation; WIC exposes it as metadata.
fn orientation(frame: &IWICBitmapFrameDecode) -> WICBitmapTransformOptions {
    // SAFETY: metadata is queried through typed WIC interfaces; PROPVARIANT is
    // converted by the system and cleared on every successful query.
    let value = unsafe {
        frame
            .GetMetadataQueryReader()
            .ok()
            .and_then(|reader| {
                for key in [w!("/app1/ifd/{ushort=274}"), w!("/ifd/{ushort=274}")] {
                    let mut value = PROPVARIANT::default();
                    let read = reader.GetMetadataByName(key, &mut value);
                    let orientation = read.ok().and_then(|_| PropVariantToUInt32(&value).ok());
                    let _ = PropVariantClear(&mut value);
                    if orientation.is_some() {
                        return orientation;
                    }
                }
                None
            })
            .unwrap_or(1)
    };
    match value {
        2 => WICBitmapTransformFlipHorizontal,
        3 => WICBitmapTransformRotate180,
        4 => WICBitmapTransformFlipVertical,
        5 => WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal,
        6 => WICBitmapTransformRotate90,
        7 => WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal,
        8 => WICBitmapTransformRotate270,
        _ => WICBitmapTransformRotate0,
    }
}
