//! One retained, explicitly inspected AppKit sheet; no desktop or SDK-private access.
use nsh_platform_macos::{
    objc2::{MainThreadMarker, Message, rc::Retained},
    objc2_app_kit::{NSAccessibility, NSApplication, NSButton, NSTextField, NSView, NSWindow},
    objc2_foundation::NSUUID,
};
use serde::Serialize;
use serde_json::{Value, json};

const SCAN_LIMIT: usize = 8192;
const SHEET_LIMIT: usize = 512;
const WINDOW_LIMIT: usize = 128;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
struct Button {
    label: String,
    enabled: bool,
    hidden: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
struct Description {
    texts: Vec<String>,
    buttons: Vec<Button>,
}
struct Contents {
    description: Description,
    views: Vec<Retained<NSView>>,
    buttons: Vec<Retained<NSButton>>,
}
struct Captured {
    token: String,
    identifier: String,
    owner: Retained<NSView>,
    window: Retained<NSWindow>,
    sheet: Retained<NSWindow>,
    contents: Contents,
}

#[derive(Default)]
pub(crate) struct State {
    captured: Option<Captured>,
}

fn same<T: ?Sized>(left: &T, right: &T) -> bool {
    std::ptr::eq(left, right)
}

fn descendants(root: Retained<NSView>, limit: usize) -> Result<Vec<Retained<NSView>>, String> {
    let mut pending = vec![root];
    let mut views = Vec::new();
    while let Some(view) = pending.pop() {
        if views.len() + pending.len() >= limit {
            return Err("native-dialog view scan exceeds its bound".into());
        }
        let children = view.subviews();
        if views.len() + pending.len() + children.len() >= limit {
            return Err("native-dialog view scan exceeds its bound".into());
        }
        pending.extend(children.iter());
        views.push(view);
    }
    Ok(views)
}

fn owner(identifier: &str, main: MainThreadMarker) -> Result<Retained<NSView>, String> {
    let windows = NSApplication::sharedApplication(main).windows();
    if windows.len() > WINDOW_LIMIT {
        return Err("native-dialog own-window scan exceeds its bound".into());
    }
    let mut found = None;
    let mut remaining = SCAN_LIMIT;
    for window in windows.iter() {
        if window.isSheet() {
            continue;
        }
        let Some(content) = window.contentView() else {
            continue;
        };
        let views = descendants(content, remaining)?;
        remaining = remaining.saturating_sub(views.len());
        for view in views {
            if view
                .accessibilityIdentifier()
                .is_some_and(|value| value.len() <= 1024 && value.to_string() == identifier)
            {
                if found.is_some() {
                    return Err("native-dialog native owner identifier is ambiguous".into());
                }
                found = Some(view);
            }
        }
    }
    found.ok_or_else(|| "native-dialog exact native owner is absent".into())
}

fn contents(sheet: &NSWindow) -> Result<Contents, String> {
    let root = sheet
        .contentView()
        .ok_or("native-dialog sheet has no content")?;
    let views = descendants(root, SHEET_LIMIT)?;
    let mut texts = Vec::new();
    let mut descriptions = Vec::new();
    let mut buttons = Vec::new();
    let mut text_bytes = 0;
    for view in &views {
        if let Some(button) = view.downcast_ref::<NSButton>() {
            let title = button.title();
            if descriptions.len() >= 32 || title.len() > 1024 {
                return Err("native-dialog button description exceeds its bound".into());
            }
            let label = title.to_string();
            if label.len() > 1024 {
                return Err("native-dialog button description exceeds its bound".into());
            }
            descriptions.push(Button {
                label,
                enabled: button.isEnabled(),
                hidden: button.isHiddenOrHasHiddenAncestor(),
            });
            buttons.push(button.retain());
        } else if let Some(field) = view.downcast_ref::<NSTextField>()
            && !field.isEditable()
            && !field.isHiddenOrHasHiddenAncestor()
        {
            let native = field.stringValue();
            if native.len() > 4096 {
                return Err("native-dialog text description exceeds its bound".into());
            }
            let value = native.to_string();
            text_bytes += value.len();
            if texts.len() >= 64 || value.len() > 4096 || text_bytes > 16 * 1024 {
                return Err("native-dialog text description exceeds its bound".into());
            }
            if !value.is_empty() {
                texts.push(value);
            }
        }
    }
    Ok(Contents {
        description: Description {
            texts,
            buttons: descriptions,
        },
        views,
        buttons,
    })
}

impl State {
    /// Every inspection invalidates the previous lease, even if no sheet is present now.
    pub(crate) fn inspect(
        &mut self,
        identifier: &str,
        main: MainThreadMarker,
    ) -> Result<Value, String> {
        self.captured.take();
        let owner = owner(identifier, main)?;
        let window = owner.window().ok_or("native-dialog owner is detached")?;
        if !window.isVisible() || window.isMiniaturized() || owner.isHiddenOrHasHiddenAncestor() {
            return Err("native-dialog owner window is not presented".into());
        }
        let Some(sheet) = window.attachedSheet() else {
            return Ok(Value::Null);
        };
        if !sheet.isSheet()
            || !sheet.isVisible()
            || sheet.attachedSheet().is_some()
            || sheet
                .sheetParent()
                .as_ref()
                .is_none_or(|parent| !same(&**parent, &*window))
        {
            return Err("native-dialog sheet is not currently attached to its owner".into());
        }
        let contents = contents(&sheet)?;
        let token = NSUUID::UUID().UUIDString().to_string();
        let result = json!({"token":token,"kind":"appkit-sheet",
            "window":window.windowNumber(),"sheet":sheet.windowNumber(),
            "texts":contents.description.texts,"buttons":contents.description.buttons});
        self.captured = Some(Captured {
            token,
            identifier: identifier.to_owned(),
            owner,
            window,
            sheet,
            contents,
        });
        Ok(result)
    }

    pub(crate) fn clear(&mut self) {
        self.captured.take();
    }

    /// Only the exact live, unmodified sheet and enabled native button can consume this lease.
    pub(crate) fn answer(&mut self, token: &str, label: &str) -> Result<(), String> {
        let captured = self
            .captured
            .as_ref()
            .ok_or("native-dialog lease is absent or consumed")?;
        if captured.token != token {
            return Err("native-dialog token is stale".into());
        }
        let attached = captured.window.attachedSheet();
        let parent = captured.sheet.sheetParent();
        if attached
            .as_ref()
            .is_none_or(|sheet| !same(&**sheet, &*captured.sheet))
            || parent
                .as_ref()
                .is_none_or(|window| !same(&**window, &*captured.window))
            || captured
                .owner
                .window()
                .as_ref()
                .is_none_or(|window| !same(&**window, &*captured.window))
            || captured
                .owner
                .accessibilityIdentifier()
                .as_ref()
                .map(|value| value.to_string())
                .as_deref()
                != Some(captured.identifier.as_str())
            || captured.owner.isHiddenOrHasHiddenAncestor()
            || !captured.window.isVisible()
            || captured.window.isMiniaturized()
            || !captured.sheet.isVisible()
            || captured.sheet.attachedSheet().is_some()
        {
            self.clear();
            return Err("native-dialog owner or sheet attachment changed".into());
        }
        let current = contents(&captured.sheet)?;
        if current.description != captured.contents.description
            || current.views.len() != captured.contents.views.len()
            || current
                .views
                .iter()
                .zip(&captured.contents.views)
                .any(|(a, b)| !same(&**a, &**b))
        {
            self.clear();
            return Err("native-dialog contents changed; inspect the current sheet again".into());
        }
        let mut found = current
            .description
            .buttons
            .iter()
            .zip(&current.buttons)
            .filter(|(button, _)| button.label == label);
        let (description, button) = found.next().ok_or("native-dialog button is absent")?;
        if found.next().is_some() {
            return Err("native-dialog button label is ambiguous".into());
        }
        if !description.enabled || description.hidden {
            return Err("native-dialog button is disabled or hidden".into());
        }
        let button = button.clone();
        // Consume before callbacks can schedule another dialog, preventing duplicate activation.
        let consumed = self.captured.take();
        // SAFETY: a checked NSButton of the exact retained live sheet, on AppKit's main thread.
        // None is the standard sender used by NSH's own native dialog controller.
        unsafe { button.performClick(None) };
        // The retired lease keeps the exact owner/window/sheet alive through native callbacks.
        drop(consumed);
        Ok(())
    }
}
