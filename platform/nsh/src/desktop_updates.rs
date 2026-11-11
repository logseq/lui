//! Application-owned update actions for the standalone root's native menu.
use crate::update::{Downloaded, ErrorCode, UpdateError, Updater, installed_configuration};
use nsh_base::alert_dialog;
use nsh_core::{
    desktop::MenuRole,
    element::desktop::{MenuItem, restart, set_application_menu},
    prelude::*,
};
use std::rc::Rc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Idle,
    Checking,
    Downloading,
    Prompt,
    Installing,
    Cancelling,
}

struct Actions {
    updater: Updater,
    phase: Signal<Phase>,
    downloaded: Signal<Option<Downloaded>>,
}

pub(crate) fn mount() {
    let updater = match bootstrap() {
        Ok(Some(updater)) => updater,
        Ok(None) => return,
        Err(error) => {
            eprintln!("desktop updates: {error}");
            set_application_menu(application_menu(
                MenuItem::new("Updates Unavailable…").on_select(move || {
                    let error = error.clone();
                    spawn(async move { show_error(error).await });
                }),
                None,
            ));
            cleanup(|| set_application_menu(None));
            return;
        }
    };
    let actions = Rc::new(Actions {
        updater,
        phase: signal(Phase::Idle),
        downloaded: signal(None),
    });
    let for_menu = actions.clone();
    effect(move || {
        let phase = for_menu.phase.get();
        let downloaded = for_menu.downloaded.get().is_some();
        let label = match phase {
            Phase::Idle if downloaded => "Install and Restart…",
            Phase::Idle => "Check for Updates…",
            Phase::Checking => "Checking for Updates…",
            Phase::Downloading => "Downloading Update…",
            Phase::Prompt => "Update Available…",
            Phase::Installing => "Installing Update…",
            Phase::Cancelling => "Cancelling Update…",
        };
        let selected = for_menu.clone();
        let primary = MenuItem::new(label)
            .disabled(phase != Phase::Idle)
            .on_select(move || selected.clone().start());
        let secondary = if matches!(phase, Phase::Checking | Phase::Downloading) {
            let cancelling = for_menu.clone();
            Some(MenuItem::new("Cancel Update").on_select(move || {
                cancelling.phase.set(Phase::Cancelling);
                cancelling.updater.cancel();
            }))
        } else if phase == Phase::Idle && downloaded {
            let checking = for_menu.clone();
            Some(MenuItem::new("Check for Updates…").on_select(move || {
                checking.downloaded.set(None);
                checking.clone().start();
            }))
        } else {
            None
        };
        set_application_menu(application_menu(primary, secondary));
    });
    cleanup(move || {
        actions.updater.cancel();
        set_application_menu(None);
    });
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
        if self.phase.get_untracked() != Phase::Idle {
            return;
        }
        let downloaded = self.downloaded.get_untracked().is_some();
        self.phase.set(if downloaded {
            Phase::Prompt
        } else {
            Phase::Checking
        });
        spawn(async move {
            let result = if downloaded {
                self.install().await
            } else {
                self.check().await
            };
            self.phase.set(Phase::Idle);
            if let Err(error) = result {
                show_error(error).await;
            }
        });
    }

    async fn check(&self) -> Result<(), String> {
        let Some(offer) = completed(self.updater.check().await)? else {
            return Ok(());
        };
        if self.phase.get_untracked() == Phase::Cancelling {
            return Ok(());
        }
        self.phase.set(Phase::Prompt);
        let Some(offer) = offer else {
            alert_dialog()
                .title("You're Up to Date")
                .description("The latest version is installed.")
                .action("done", "OK")
                .show()
                .await?;
            return Ok(());
        };
        let description = match offer.notes() {
            Some(notes) => format!(
                "Version {} is available.\n\n{}",
                offer.version(),
                notes.chars().take(4096).collect::<String>()
            ),
            None => format!("Version {} is available.", offer.version()),
        };
        let answer = alert_dialog()
            .title("Update Available")
            .description(description)
            .cancel("later", "Later")
            .action(
                "download",
                if offer.can_install() {
                    "Download"
                } else {
                    "Open Download Page"
                },
            )
            .show()
            .await?;
        if answer.action.as_deref() != Some("download") {
            return Ok(());
        }
        if !offer.can_install() {
            if !open_url(offer.url().to_owned()).await {
                return Err("The download page could not be opened".into());
            }
            return Ok(());
        }
        self.phase.set(Phase::Downloading);
        let Some(downloaded) = completed(self.updater.download(offer).await)? else {
            return Ok(());
        };
        if self.phase.get_untracked() == Phase::Cancelling {
            return Ok(());
        }
        self.downloaded.set(Some(downloaded));
        self.phase.set(Phase::Prompt);
        self.install().await
    }

    async fn install(&self) -> Result<(), String> {
        let Some(downloaded) = self.downloaded.get_untracked() else {
            return Ok(());
        };
        let answer = alert_dialog()
            .title("Update Ready")
            .description("The app will close and restart with the new version.")
            .cancel("later", "Later")
            .action("install", "Install and Restart")
            .show()
            .await?;
        if answer.action.as_deref() != Some("install") {
            return Ok(());
        }
        self.phase.set(Phase::Installing);
        match self.updater.install(downloaded).await {
            Ok(()) => {
                self.downloaded.set(None);
                restart();
                Ok(())
            }
            Err(error) => {
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

async fn show_error(error: String) {
    if let Err(dialog_error) = alert_dialog()
        .title("Update Could Not Be Completed")
        .description(error)
        .action("done", "OK")
        .show()
        .await
    {
        eprintln!("desktop update dialog: {dialog_error}");
    }
}

fn application_menu(primary: MenuItem, secondary: Option<MenuItem>) -> Vec<MenuItem> {
    let mut application = Vec::new();
    if cfg!(target_os = "macos") {
        application.extend([MenuItem::role(MenuRole::About), MenuItem::separator()]);
    }
    application.push(primary);
    application.extend(secondary);
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
