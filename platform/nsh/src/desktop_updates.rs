//! Application-owned update actions for the standalone root's native menu.
use crate::update::{Downloaded, ErrorCode, UpdateError, Updater, installed_configuration};
use nsh_base::alert_dialog;
use nsh_core::{
    desktop::MenuRole,
    element::desktop::{MenuItem, restart, set_application_menu},
    prelude::*,
};
use serde::Deserialize;
use std::{cell::RefCell, rc::Rc};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Phase {
    Idle,
    Checking,
    Downloading,
    Prompt,
    Installing,
    Cancelling,
}

/// Translated update menu/dialog text. Construct once from the application's
/// translation owner; generic DesktopApp uses the existing English defaults.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
pub struct UpdateLabels {
    pub menu_check: String,
    pub menu_install: String,
    pub menu_checking: String,
    pub menu_downloading: String,
    pub menu_prompt: String,
    pub menu_installing: String,
    pub menu_cancelling: String,
    pub menu_cancel: String,
    pub menu_unavailable: String,
    pub current_title: String,
    pub current_description: String,
    pub done: String,
    pub available_title: String,
    pub version_available: String,
    pub version_notes: String,
    pub later: String,
    pub download: String,
    pub open_download: String,
    pub ready_title: String,
    pub ready_description: String,
    pub install: String,
    pub error_title: String,
}
impl Default for UpdateLabels {
    fn default() -> Self {
        Self {
            menu_check: "Check for Updates…".into(),
            menu_install: "Install and Restart…".into(),
            menu_checking: "Checking for Updates…".into(),
            menu_downloading: "Downloading Update…".into(),
            menu_prompt: "Update Available…".into(),
            menu_installing: "Installing Update…".into(),
            menu_cancelling: "Cancelling Update…".into(),
            menu_cancel: "Cancel Update".into(),
            menu_unavailable: "Updates Unavailable…".into(),
            current_title: "You're Up to Date".into(),
            current_description: "The latest version is installed.".into(),
            done: "OK".into(),
            available_title: "Update Available".into(),
            version_available: "Version {version} is available.".into(),
            version_notes: "Version {version} is available.\n\n{notes}".into(),
            later: "Later".into(),
            download: "Download".into(),
            open_download: "Open Download Page".into(),
            ready_title: "Update Ready".into(),
            ready_description: "The app will close and restart with the new version.".into(),
            install: "Install and Restart".into(),
            error_title: "Update Could Not Be Completed".into(),
        }
    }
}
impl UpdateLabels {
    /// Rejects an incomplete translation payload before replacing native menus.
    pub fn validate(&self) -> Result<(), String> {
        if [
            &self.menu_check,
            &self.menu_install,
            &self.menu_checking,
            &self.menu_downloading,
            &self.menu_prompt,
            &self.menu_installing,
            &self.menu_cancelling,
            &self.menu_cancel,
            &self.menu_unavailable,
            &self.current_title,
            &self.current_description,
            &self.done,
            &self.available_title,
            &self.version_available,
            &self.version_notes,
            &self.later,
            &self.download,
            &self.open_download,
            &self.ready_title,
            &self.ready_description,
            &self.install,
            &self.error_title,
        ]
        .iter()
        .any(|label| label.trim().is_empty())
        {
            return Err("update actions require nonempty translated labels".into());
        }
        for (text, token) in [
            (&self.version_available, "{version}"),
            (&self.version_notes, "{version}"),
            (&self.version_notes, "{notes}"),
        ] {
            if !text.contains(token) {
                return Err(format!("update label requires {token} placeholder"));
            }
        }
        Ok(())
    }
}

struct Actions {
    owner: Owner,
    updater: RefCell<Option<Updater>>,
    phase: Signal<Phase>,
    downloaded: Signal<Option<Downloaded>>,
    labels: RefCell<UpdateLabels>,
}

enum State {
    Disabled,
    Unavailable { owner: Owner, error: String },
    Ready(Rc<Actions>),
}

/// App-owned menu contribution over one existing updater worker. It never
/// replaces the application's menu. Create inside the application's owner;
/// cleanup cancels work and releases the worker even if old menus retain callbacks.
#[derive(Clone)]
pub struct UpdateActions(Rc<State>);
impl UpdateActions {
    /// Reads only the actual installed asset. No asset means no worker, cache,
    /// network or menu contribution. Invalid installed configuration contributes
    /// an explicit unavailable action using the same error dialog.
    pub fn installed() -> Self {
        match bootstrap() {
            Ok(Some(updater)) => Self::new(updater),
            Ok(None) => Self(Rc::new(State::Disabled)),
            Err(error) => {
                eprintln!("desktop updates: {error}");
                Self(Rc::new(State::Unavailable {
                    owner: Owner::current(),
                    error,
                }))
            }
        }
    }
    /// Uses an application-selected updater; its existing installation/root
    /// verification remains enforced by Updater. Clones share the same worker.
    pub fn new(updater: Updater) -> Self {
        let actions = Rc::new(Actions {
            owner: Owner::current(),
            updater: RefCell::new(Some(updater)),
            phase: signal(Phase::Idle),
            downloaded: signal(None),
            labels: RefCell::new(UpdateLabels::default()),
        });
        let retiring = actions.clone();
        cleanup(move || {
            if let Some(updater) = retiring.updater.borrow_mut().take() {
                updater.cancel();
            }
        });
        Self(Rc::new(State::Ready(actions)))
    }
    /// Whether installed configuration exists, including an invalid asset.
    pub fn is_configured(&self) -> bool {
        !matches!(&*self.0, State::Disabled)
    }
    /// Read inside the existing menu owner's effect to track phase changes.
    /// Labels must already pass validate(); no new menu owner or polling starts.
    pub fn menu_items(&self, labels: UpdateLabels) -> Vec<MenuItem> {
        match &*self.0 {
            State::Disabled => Vec::new(),
            State::Unavailable { owner, error } => {
                if !owner.is_live() {
                    return Vec::new();
                }
                let owner = *owner;
                let error = error.clone();
                vec![
                    MenuItem::new(labels.menu_unavailable.clone()).on_select(move || {
                        if !owner.is_live() {
                            return;
                        }
                        let error = error.clone();
                        let labels = labels.clone();
                        owner.run(move || {
                            spawn(async move { show_error(error, &labels).await });
                        });
                    }),
                ]
            }
            State::Ready(actions) => {
                if !actions.owner.is_live() {
                    return Vec::new();
                }
                *actions.labels.borrow_mut() = labels.clone();
                let phase = actions.phase.get();
                let downloaded = actions.downloaded.get().is_some();
                let label = match phase {
                    Phase::Idle if downloaded => &labels.menu_install,
                    Phase::Idle => &labels.menu_check,
                    Phase::Checking => &labels.menu_checking,
                    Phase::Downloading => &labels.menu_downloading,
                    Phase::Prompt => &labels.menu_prompt,
                    Phase::Installing => &labels.menu_installing,
                    Phase::Cancelling => &labels.menu_cancelling,
                };
                let selected = actions.clone();
                let mut items = vec![
                    MenuItem::new(label.clone())
                        .disabled(phase != Phase::Idle)
                        .on_select(move || selected.clone().start()),
                ];
                if matches!(phase, Phase::Checking | Phase::Downloading) {
                    let cancelling = actions.clone();
                    items.push(MenuItem::new(labels.menu_cancel).on_select(move || {
                        if cancelling.owner.is_live() {
                            cancelling.phase.set(Phase::Cancelling);
                            if let Some(updater) = cancelling.updater.borrow().as_ref() {
                                updater.cancel();
                            }
                        }
                    }));
                } else if phase == Phase::Idle && downloaded {
                    let checking = actions.clone();
                    items.push(MenuItem::new(labels.menu_check).on_select(move || {
                        if checking.owner.is_live() {
                            checking.downloaded.set(None);
                            checking.clone().start();
                        }
                    }));
                }
                items
            }
        }
    }
}

pub(crate) fn mount() {
    let updates = UpdateActions::installed();
    if !updates.is_configured() {
        return;
    }
    effect(move || {
        set_application_menu(application_menu(
            updates.menu_items(UpdateLabels::default()),
        ))
    });
    cleanup(|| set_application_menu(None));
}

fn bootstrap() -> Result<Option<Updater>, String> {
    let executable = std::env::current_exe().map_err(|error| error.to_string())?;
    let Some(configuration) =
        installed_configuration(&executable).map_err(|error| error.to_string())?
    else {
        return Ok(None);
    };
    let cache = data_dir()
        .ok_or("The application has no writable data directory for updates")?
        .join("updates");
    Updater::open(&configuration, &executable, &cache)
        .map(Some)
        .map_err(|error| error.to_string())
}

impl Actions {
    fn start(self: Rc<Self>) {
        if !self.owner.is_live() || self.phase.get_untracked() != Phase::Idle {
            return;
        }
        let Some(updater) = self.updater.borrow().as_ref().cloned() else {
            return;
        };
        let downloaded = self.downloaded.get_untracked().is_some();
        self.phase.set(if downloaded {
            Phase::Prompt
        } else {
            Phase::Checking
        });
        let owner = self.owner;
        owner.run(move || {
            spawn(async move {
                let result = if downloaded {
                    self.install(&updater).await
                } else {
                    self.check(&updater).await
                };
                if !self.owner.is_live() {
                    return;
                }
                self.phase.set(Phase::Idle);
                if let Err(error) = result {
                    let labels = self.labels.borrow().clone();
                    show_error(error, &labels).await;
                }
            });
        });
    }

    async fn check(&self, updater: &Updater) -> Result<(), String> {
        let Some(offer) = completed(updater.check().await)? else {
            return Ok(());
        };
        if !self.owner.is_live() || self.phase.get_untracked() == Phase::Cancelling {
            return Ok(());
        }
        self.phase.set(Phase::Prompt);
        let labels = self.labels.borrow().clone();
        let Some(offer) = offer else {
            alert_dialog()
                .title(labels.current_title)
                .description(labels.current_description)
                .action("done", labels.done)
                .show()
                .await?;
            return Ok(());
        };
        let description = match offer.notes() {
            Some(notes) => labels
                .version_notes
                .replace("{version}", offer.version())
                .replace("{notes}", &notes.chars().take(4096).collect::<String>()),
            None => labels
                .version_available
                .replace("{version}", offer.version()),
        };
        let answer = alert_dialog()
            .title(labels.available_title)
            .description(description)
            .cancel("later", labels.later)
            .action(
                "download",
                if offer.can_install() {
                    labels.download
                } else {
                    labels.open_download
                },
            )
            .show()
            .await?;
        if !self.owner.is_live() || answer.action.as_deref() != Some("download") {
            return Ok(());
        }
        if !offer.can_install() {
            if !open_url(offer.url().to_owned()).await {
                return Err("The download page could not be opened".into());
            }
            return Ok(());
        }
        self.phase.set(Phase::Downloading);
        let Some(downloaded) = completed(updater.download(offer).await)? else {
            return Ok(());
        };
        if !self.owner.is_live() || self.phase.get_untracked() == Phase::Cancelling {
            return Ok(());
        }
        self.downloaded.set(Some(downloaded));
        self.phase.set(Phase::Prompt);
        self.install(updater).await
    }

    async fn install(&self, updater: &Updater) -> Result<(), String> {
        if !self.owner.is_live() {
            return Ok(());
        }
        let Some(downloaded) = self.downloaded.get_untracked() else {
            return Ok(());
        };
        let labels = self.labels.borrow().clone();
        let answer = alert_dialog()
            .title(labels.ready_title)
            .description(labels.ready_description)
            .cancel("later", labels.later)
            .action("install", labels.install)
            .show()
            .await?;
        if !self.owner.is_live() || answer.action.as_deref() != Some("install") {
            return Ok(());
        }
        self.phase.set(Phase::Installing);
        match updater.install(downloaded).await {
            Ok(()) => {
                if !self.owner.is_live() {
                    return Ok(());
                }
                self.downloaded.set(None);
                restart();
                Ok(())
            }
            Err(error) => {
                if !self.owner.is_live() {
                    return Ok(());
                }
                if matches!(error.code(), ErrorCode::Stale | ErrorCode::Verification) {
                    self.downloaded.set(None);
                }
                completed::<()>(Err(error)).map(|_| ())
            }
        }
    }
}

fn completed<T>(result: Result<T, UpdateError>) -> Result<Option<T>, String> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(error) if error.code() == ErrorCode::Cancelled => Ok(None),
        Err(error) => Err(error.to_string()),
    }
}

async fn show_error(error: String, labels: &UpdateLabels) {
    if let Err(dialog_error) = alert_dialog()
        .title(labels.error_title.clone())
        .description(error)
        .action("done", labels.done.clone())
        .show()
        .await
    {
        eprintln!("desktop update dialog: {dialog_error}");
    }
}

fn application_menu(updates: Vec<MenuItem>) -> Vec<MenuItem> {
    let mut application = Vec::new();
    if cfg!(target_os = "macos") {
        application.extend([MenuItem::role(MenuRole::About), MenuItem::separator()]);
    }
    application.extend(updates);
    application.push(MenuItem::separator());
    if cfg!(target_os = "macos") {
        application.extend([
            MenuItem::role(MenuRole::Hide),
            MenuItem::role(MenuRole::HideOthers),
            MenuItem::role(MenuRole::ShowAll),
            MenuItem::separator(),
        ]);
    }
    application.push(MenuItem::role(MenuRole::Quit));
    vec![
        MenuItem::submenu("Application", application),
        MenuItem::submenu(
            "Edit",
            [
                MenuItem::role(MenuRole::Undo),
                MenuItem::role(MenuRole::Redo),
                MenuItem::separator(),
                MenuItem::role(MenuRole::Cut),
                MenuItem::role(MenuRole::Copy),
                MenuItem::role(MenuRole::Paste),
                MenuItem::role(MenuRole::SelectAll),
            ],
        ),
        MenuItem::submenu(
            "Window",
            [
                MenuItem::role(MenuRole::Minimize),
                MenuItem::role(MenuRole::Zoom),
                MenuItem::role(MenuRole::ToggleFullScreen),
                MenuItem::role(MenuRole::Close),
            ],
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_base::button;
    use nsh_core::{Command, desktop::DesktopCommand};
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::{DialogAnswer, Headless};
    use std::time::Duration;

    #[derive(Clone, PartialEq, Props)]
    struct ActionProps {
        cancelled: Prop<bool>,
        verification_error: Prop<bool>,
    }

    #[component]
    fn ActionProbe(props: ActionProps) -> impl IntoElement {
        let (updater, operations) = crate::update::tests::menu_fixture(
            props.cancelled.get_untracked(),
            props
                .verification_error
                .get_untracked()
                .then_some(ErrorCode::Verification),
        );
        let contribution = UpdateActions::new(updater);
        let State::Ready(actions) = &*contribution.0 else {
            unreachable!()
        };
        let actions = actions.clone();
        let for_menu = contribution.clone();
        effect(move || {
            let updates = for_menu
                .menu_items(UpdateLabels::default())
                .into_iter()
                .enumerate()
                .map(|(index, item)| {
                    if index == 0 {
                        item.shortcut("f8")
                    } else {
                        item
                    }
                })
                .collect::<Vec<_>>();
            set_application_menu(vec![MenuItem::submenu("Host-owned menu", updates)]);
        });
        cleanup(|| set_application_menu(None));
        let selected = actions.clone();
        view()
            .flex_col()
            .child(
                button()
                    .on_press(move || selected.clone().start())
                    .child(text("Run update")),
            )
            .child(text(move || {
                format!(
                    "{:?} cached={} operations={:?}",
                    actions.phase.get(),
                    actions.downloaded.get().is_some(),
                    operations.lock().unwrap()
                )
            }))
    }

    fn start(cancelled: bool, verification_error: bool) -> Headless {
        let mut app = Headless::start(EngineConfig::new(Root::new::<ActionProbe>(move || {
            ActionProps {
                cancelled: Prop::new(cancelled),
                verification_error: Prop::new(verification_error),
            }
        })))
        .unwrap();
        app.answer_dialogs_myself();
        wait_status(&mut app, "Idle cached=false");
        app
    }

    fn wait_status(app: &mut Headless, expected: &str) {
        app.wait_until(expected, Duration::from_secs(3), |screen| {
            screen.texts().iter().any(|text| text.contains(expected))
        })
        .unwrap();
    }

    fn wait_dialog(app: &mut Headless) {
        let deadline = std::time::Instant::now() + Duration::from_secs(3);
        while app.pending_dialog().is_none() {
            assert!(
                std::time::Instant::now() < deadline,
                "update dialog missing"
            );
            app.wait(Duration::from_millis(10)).unwrap();
        }
    }

    fn download(app: &mut Headless) {
        app.press("text:Run update").unwrap();
        wait_dialog(app);
        app.answer_dialog(DialogAnswer::Press("Download".into()))
            .unwrap();
        wait_dialog(app);
    }

    fn restarted(app: &Headless) -> bool {
        app.screen().commands().iter().any(|(_, command)| {
            matches!(command, Command::Desktop(command) if matches!(&**command, DesktopCommand::Restart))
        })
    }

    #[test]
    fn later_retains_verified_download_and_success_restarts_only_after_confirmation() {
        let mut app = start(false, false);
        download(&mut app);
        assert!(!restarted(&app));
        app.answer_dialog(DialogAnswer::Press("Later".into()))
            .unwrap();
        wait_status(&mut app, "Idle cached=true");
        assert!(!restarted(&app));
        app.press("text:Run update").unwrap();
        wait_dialog(&mut app);
        app.answer_dialog(DialogAnswer::Press("Install and Restart".into()))
            .unwrap();
        wait_status(&mut app, "Idle cached=false");
        assert!(restarted(&app));
        assert!(
            app.screen()
                .texts()
                .iter()
                .any(|text| { text.contains("operations=[\"check\", \"download\", \"install\"]") })
        );
    }

    #[test]
    fn failed_archive_verification_clears_download_and_never_restarts() {
        let mut app = start(false, true);
        download(&mut app);
        app.answer_dialog(DialogAnswer::Press("Install and Restart".into()))
            .unwrap();
        wait_dialog(&mut app);
        assert!(!restarted(&app));
        app.answer_dialog(DialogAnswer::Press("OK".into())).unwrap();
        wait_status(&mut app, "Idle cached=false");
    }

    #[test]
    fn cancelled_check_returns_idle_without_an_error_dialog_or_restart() {
        let mut app = start(true, false);
        app.press("text:Run update").unwrap();
        wait_status(&mut app, "Idle cached=false operations=[\"check\"]");
        assert!(app.pending_dialog().is_none());
        assert!(!restarted(&app));
    }
    #[test]
    fn contribution_uses_the_host_menu_and_existing_update_confirmation() {
        let mut app = start(false, false);
        app.press_key("f8").unwrap();
        wait_dialog(&mut app);
        app.answer_dialog(DialogAnswer::Press("Later".into()))
            .unwrap();
        wait_status(&mut app, "Idle cached=false operations=[\"check\"]");
        assert!(!restarted(&app));
    }

    #[component]
    fn RetiredContribution() -> impl IntoElement {
        let (updater, operations) = crate::update::tests::menu_fixture(false, None);
        let (owner, updates) = create_root(|| UpdateActions::new(updater));
        let State::Ready(actions) = &*updates.0 else {
            unreachable!()
        };
        let actions = actions.clone();
        owner.dispose();
        assert!(actions.updater.borrow().is_none());
        actions.start();
        assert!(updates.menu_items(UpdateLabels::default()).is_empty());
        assert!(operations.lock().unwrap().is_empty());
        text("Retired update contribution is inert")
    }
    #[test]
    fn owner_cleanup_releases_worker_and_retained_callbacks_are_inert() {
        let mut app =
            Headless::start(EngineConfig::new(Root::of::<RetiredContribution>())).unwrap();
        app.wait_for("text:Retired update contribution is inert")
            .unwrap();
    }

    #[test]
    fn update_labels_require_complete_text_and_version_placeholders() {
        let mut labels = UpdateLabels::default();
        labels.menu_check = "检查更新…".into();
        assert!(labels.validate().is_ok());
        labels.version_notes = "Missing version and notes".into();
        assert!(labels.validate().is_err());
        labels = UpdateLabels::default();
        labels.menu_cancel.clear();
        assert!(labels.validate().is_err());
    }
}
