//! Desktop file selection through NSH's native open-dialog service.
use crate::{render::Event, store::Node};
use nsh_core::{
    file_dialog::{FileFilter, OpenDialog},
    prelude::*,
};
use serde_json::{Value, json};
use std::{
    cell::{Cell, RefCell},
    path::PathBuf,
    rc::Rc,
    sync::Arc,
};

fn dialog(node: &Node) -> Result<OpenDialog, String> {
    if !matches!(node.string("source"), "" | "files") {
        return Err("NSH FilePicker supports native file dialogs; photo-library and camera sources are not implemented".into());
    }
    if node.props.contains_key("completion") {
        return Err(
            "NSH FilePicker returns native paths without completion tokens or file leases".into(),
        );
    }
    let mut dialog = if node.boolean("directory", false) {
        OpenDialog::folders()
    } else {
        OpenDialog::files()
    }
    .multiple(node.boolean("multiple", false));
    if !dialog.picks_files() {
        return Ok(dialog);
    }
    for property in ["types", "accept"] {
        let authored = node.string(property).trim();
        if authored.is_empty() {
            continue;
        }
        let extensions = authored.split(',').map(str::trim).map(|extension| {
            let suffix = extension.strip_prefix("*.").or_else(|| extension.strip_prefix('.'));
            match suffix {
                Some(suffix) if !suffix.is_empty() && !suffix.contains(['/', '\\', '*']) && !suffix.chars().any(char::is_whitespace) => Ok(suffix),
                _ => Err(format!("NSH {property} takes comma-separated file extensions such as .md,.txt; MIME and UTI filters are not implemented")),
            }
        }).collect::<Result<Vec<_>, _>>()?;
        dialog = dialog.filter(FileFilter::new(authored, extensions));
    }
    Ok(dialog)
}

pub(crate) fn validate(node: &Node) -> Result<(), String> {
    if node.kind == "file-picker" {
        dialog(node)?;
    }
    Ok(())
}

fn picked(request: Value, result: Result<Option<Vec<PathBuf>>, String>) -> Option<String> {
    let paths = match result {
        Ok(None) => return None,
        Ok(Some(paths)) => serde_json::to_value(paths).map_err(|error| error.to_string()),
        Err(error) => Err(error),
    };
    Some(
        match paths {
            Ok(paths) => json!({"request":request, "paths":paths}),
            Err(error) => json!({"request":request, "paths":[], "error":error}),
        }
        .to_string(),
    )
}

/// Request tokens bridge a retained wire node to NSH's imperative native API.
/// The existing reactive owner cancels its task when this node is removed.
pub(crate) fn element(
    node: Signal<Arc<Node>>,
    children: AnyElement,
    emit: Rc<dyn Fn(Event)>,
) -> View {
    let owner = Owner::current();
    let busy = Rc::new(Cell::new(false));
    let last = Rc::new(RefCell::new(None));
    let request = computed(move || {
        let node = node.get();
        node.boolean("enabled", true)
            .then(|| node.props.get("request").cloned())
            .flatten()
    });
    effect(move || {
        let Some(request) = request.get() else { return };
        if busy.get() || last.borrow().as_ref() == Some(&request) {
            return;
        }
        busy.set(true);
        *last.borrow_mut() = Some(request.clone());
        let current = node.get_untracked();
        let id = current.id;
        let dialog = dialog(&current).expect("atomically validated native file dialog");
        let busy = busy.clone();
        let emit = emit.clone();
        // The task belongs to the retained node, rather than this effect's
        // request revision. Changing a token does not reopen a native dialog.
        owner.run(move || {
            let answer = pick_paths(dialog);
            spawn(async move {
                let result = picked(request, answer.await);
                busy.set(false);
                emit(match result {
                    Some(payload) => Event::Picked(id, payload),
                    None => Event::Dismiss(id),
                });
            });
        });
    });
    view().child(children)
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::{ffi::OsString, os::unix::ffi::OsStringExt};

    #[test]
    fn a_non_utf8_native_path_is_an_error_instead_of_a_lossy_file_name() {
        let path = PathBuf::from(OsString::from_vec(vec![b'/', 0xff]));
        let payload = picked(json!("native-request"), Ok(Some(vec![path]))).unwrap();
        let result: Value = serde_json::from_str(&payload).unwrap();
        assert_eq!(result["request"], "native-request");
        assert_eq!(result["paths"], json!([]));
        assert!(
            result["error"]
                .as_str()
                .is_some_and(|error| !error.is_empty())
        );
        assert!(!payload.contains('\u{fffd}'));
    }
}
