//! Public AppKit/Core Animation conversion, including existing layer transforms.
use nsh_platform_macos::{objc2::rc::Retained, objc2_app_kit::NSView, objc2_foundation::NSPoint};

pub(super) fn content_bounds(view: &NSView, content: &NSView) -> Result<[f64; 4], String> {
    const ANCESTOR_LIMIT: usize = 64;
    let mut chain = Vec::new();
    let mut current = Some(Retained::from(view));
    while let Some(view) = current {
        if chain
            .iter()
            .any(|previous: &Retained<NSView>| std::ptr::eq(&**previous, &*view))
        {
            return Err("native bounds ancestry contains a cycle".into());
        }
        let reached = std::ptr::eq(&*view, content);
        // SAFETY: callers inspect retained views on AppKit's main thread.
        current = if reached {
            None
        } else {
            unsafe { view.superview() }
        };
        chain.push(view);
        if reached {
            break;
        }
        if chain.len() == ANCESTOR_LIMIT {
            return Err("native bounds ancestry exceeds its conversion budget".into());
        }
    }
    if !chain
        .last()
        .is_some_and(|view| std::ptr::eq(&**view, content))
    {
        return Err("native bounds target is outside the content view".into());
    }
    // Unlayered children keep AppKit's ordinary local geometry. Bridge only the
    // existing layer-backed span so a live sublayer scroll is applied once.
    let first = chain
        .iter()
        .find_map(|view| view.layer().map(|layer| (view, layer)));
    let last = chain
        .iter()
        .rev()
        .find_map(|view| view.layer().map(|layer| (view, layer)));
    if let (Some((_, source)), Some((_, target))) = (&first, &last) {
        let mut current = Some(source.clone());
        let mut visited = std::collections::HashSet::new();
        let mut connected = false;
        while let Some(layer) = current {
            if !visited.insert(std::ptr::from_ref(&*layer)) {
                return Err("native bounds layer ancestry contains a cycle".into());
            }
            if std::ptr::eq(&*layer, &**target) {
                connected = true;
                break;
            }
            if visited.len() == ANCESTOR_LIMIT {
                return Err("native bounds layer ancestry exceeds its conversion budget".into());
            }
            current = layer.superlayer();
        }
        if !connected {
            return Err("native bounds backing layers are disconnected".into());
        }
    }
    let bounds = view.bounds();
    let (mut min_x, mut min_y, mut max_x, mut max_y) = (
        f64::INFINITY,
        f64::INFINITY,
        f64::NEG_INFINITY,
        f64::NEG_INFINITY,
    );
    for (dx, dy) in [
        (0.0, 0.0),
        (bounds.size.width, 0.0),
        (0.0, bounds.size.height),
        (bounds.size.width, bounds.size.height),
    ] {
        let point = NSPoint::new(bounds.origin.x + dx, bounds.origin.y + dy);
        let point = match (&first, &last) {
            (Some((source, source_layer)), Some((target, target_layer))) => {
                let local = source.convertPoint_fromView(point, Some(view));
                let local = source.convertPointToLayer(local);
                let mapped = source_layer.convertPoint_toLayer(local, Some(target_layer));
                target.convertPoint_toView(target.convertPointFromLayer(mapped), Some(content))
            }
            _ => view.convertPoint_toView(point, Some(content)),
        };
        if !point.x.is_finite() || !point.y.is_finite() {
            return Err("native bounds transform produced a nonfinite point".into());
        }
        min_x = min_x.min(point.x);
        min_y = min_y.min(point.y);
        max_x = max_x.max(point.x);
        max_y = max_y.max(point.y);
    }
    Ok([min_x, min_y, max_x - min_x, max_y - min_y])
}
