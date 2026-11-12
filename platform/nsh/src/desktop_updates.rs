//! Application-owned update actions for the standalone root's native menu.
use crate::update::{Downloaded, ErrorCode, UpdateError, Updater, installed_configuration};
use nsh_base::alert_dialog;
use nsh_core::{
    desktop::MenuRole,
    element::desktop::{MenuItem, restart, set_application_menu},
    prelude::*,
};
use serde::Deserialize;
use std::{cell::RefCell, future::Future, pin::Pin, rc::Rc};

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

/// Application preparation after the user's final confirmation. None cancels
/// without installing and retains the verified download for another attempt.
pub type InstallPreparation = Pin<Box<dyn Future<Output = Result<Option<InstallLease>, String>>>>;

/// Required application policy for saving/quiescing and safely relaunching.
/// The preparation future must release its own pending reservation if dropped
/// before it returns a lease. No worker or wire protocol is created here.
pub trait UpdateLifecycle {
    /// Save and quiesce application state, or cancel/refuse this installation.
    fn prepare(&self) -> InstallPreparation;
}

type AbortInstall = Box<dyn FnOnce()>;
type Relaunch = Box<dyn FnOnce() -> Result<(), String>>;

/// Owned quiescence lease for one confirmed installation. Before installation
/// is dispatched, dropping it aborts/resumes only while its owner lives.
/// A proven pre-replacement failure also aborts. Installation errors, lost
/// worker replies, cancellation after dispatch and restart failure never thaw
/// an application whose installed files may already have changed.
pub struct InstallLease {
    owner: Owner,
    abort_on_drop: bool,
    abort: Option<AbortInstall>,
    relaunch: Option<Relaunch>,
}
impl InstallLease {
    /// Construct under the application's live preparation owner. Callbacks
    /// must act only on that application/session, never an unrelated daemon.
    /// `abort` releases preparation before dispatch or after a proven
    /// pre-replacement failure; `relaunch` must enforce the app's
    /// exit/argv/environment/credential policy after installation.
    pub fn new(
        abort: impl FnOnce() + 'static,
        relaunch: impl FnOnce() -> Result<(), String> + 'static,
    ) -> Self {
        Self {
            owner: Owner::current(),
            abort_on_drop: true,
            abort: Some(Box::new(abort)),
            relaunch: Some(Box::new(relaunch)),
        }
    }
    fn dispatched(&mut self) {
        // An owned UI task can be cancelled while the installer worker is
        // still running. Its drop cannot prove that resuming writes is safe.
        self.abort_on_drop = false;
    }
    fn abort(&mut self) {
        if self.owner.is_live()
            && let Some(abort) = self.abort.take()
        {
            abort();
        }
    }
    fn restart(mut self) -> Result<(), String> {
        if !self.owner.is_live() {
            return Err("the installed update's application restart owner has retired".into());
        }
        self.relaunch.take().expect("one owned relaunch")()
    }
}
impl Drop for InstallLease {
    fn drop(&mut self) {
        if self.abort_on_drop {
            self.abort();
        }
    }
}

// Only the generic standalone root opts into the existing NSH restart policy.
// Embedded applications must make an explicit, application-owned choice.
struct StandaloneLifecycle;
impl UpdateLifecycle for StandaloneLifecycle {
    fn prepare(&self) -> InstallPreparation {
        Box::pin(async {
            Ok(Some(InstallLease::new(
                || {},
                || {
                    restart();
                    Ok(())
                },
            )))
        })
    }
}

struct Actions {
    owner: Owner,
    updater: RefCell<Option<Updater>>,
    phase: Signal<Phase>,
    downloaded: Signal<Option<Downloaded>>,
    labels: RefCell<UpdateLabels>,
    lifecycle: Rc<dyn UpdateLifecycle>,
}

enum State {
    Disabled,
    Unavailable {
        owner: Owner,
        error: String,
        busy: Signal<bool>,
    },
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
    /// An application must explicitly provide its save/relaunch policy:
    ///
    /// ```compile_fail,E0061
    /// use lui_nsh::desktop_updates::UpdateActions;
    /// let updates = UpdateActions::installed();
    /// ```
    pub fn installed(lifecycle: Rc<dyn UpdateLifecycle>) -> Self {
        match bootstrap() {
            Ok(Some(updater)) => Self::new(updater, lifecycle),
            Ok(None) => Self(Rc::new(State::Disabled)),
            Err(error) => {
                eprintln!("desktop updates: {error}");
                Self(Rc::new(State::Unavailable {
                    owner: Owner::current(),
                    error,
                    busy: signal(false),
                }))
            }
        }
    }
    /// Uses an application-selected updater; its existing installation/root
    /// verification remains enforced by Updater. Clones share the same worker.
    /// Omitting application lifecycle ownership is a compile error:
    ///
    /// ```compile_fail,E0061
    /// use lui_nsh::{desktop_updates::UpdateActions, update::Updater};
    /// fn embedded(updater: Updater) {
    ///     let updates = UpdateActions::new(updater);
    /// }
    /// ```
    pub fn new(updater: Updater, lifecycle: Rc<dyn UpdateLifecycle>) -> Self {
        let actions = Rc::new(Actions {
            owner: Owner::current(),
            updater: RefCell::new(Some(updater)),
            phase: signal(Phase::Idle),
            downloaded: signal(None),
            labels: RefCell::new(UpdateLabels::default()),
            lifecycle,
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
    /// Read in the app's existing effect to share its menu's busy state.
    /// This subscribes to the same phase signal; it creates no polling task.
    pub fn is_busy(&self) -> bool {
        match &*self.0 {
            State::Ready(actions) => actions.owner.is_live() && actions.phase.get() != Phase::Idle,
            State::Unavailable { owner, busy, .. } => owner.is_live() && busy.get(),
            State::Disabled => false,
        }
    }
    /// Check again from an application control using this same updater owner,
    /// translated dialogs and installation lifecycle. A retained downloaded
    /// archive is cleared, as with the menu's explicit Check action.
    /// Returns false for an unconfigured, busy or retired owner. Configuration
    /// errors use the existing native error dialog; invalid labels are rejected.
    pub fn check_for_updates(&self, labels: UpdateLabels) -> Result<bool, String> {
        labels.validate()?;
        match &*self.0 {
            State::Disabled => Ok(false),
            State::Unavailable { owner, error, busy } => {
                Ok(show_unavailable(*owner, *busy, error.clone(), labels))
            }
            State::Ready(actions) => {
                if !actions.owner.is_live() || actions.phase.get_untracked() != Phase::Idle {
                    return Ok(false);
                }
                *actions.labels.borrow_mut() = labels;
                Ok(actions.clone().start_check())
            }
        }
    }
    /// Read inside the existing menu owner's effect to track phase changes.
    /// Labels must already pass validate(); no new menu owner or polling starts.
    pub fn menu_items(&self, labels: UpdateLabels) -> Vec<MenuItem> {
        match &*self.0 {
            State::Disabled => Vec::new(),
            State::Unavailable { owner, error, busy } => {
                if !owner.is_live() {
                    return Vec::new();
                }
                let owner = *owner;
                let error = error.clone();
                let busy = *busy;
                vec![
                    MenuItem::new(labels.menu_unavailable.clone())
                        .disabled(busy.get())
                        .on_select(move || {
                            show_unavailable(owner, busy, error.clone(), labels.clone());
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
                        if cancelling.owner.is_live()
                            && matches!(
                                cancelling.phase.get_untracked(),
                                Phase::Checking | Phase::Downloading
                            )
                        {
                            cancelling.phase.set(Phase::Cancelling);
                            if let Some(updater) = cancelling.updater.borrow().as_ref() {
                                updater.cancel();
                            }
                        }
                    }));
                } else if phase == Phase::Idle && downloaded {
                    let checking = actions.clone();
                    items.push(MenuItem::new(labels.menu_check).on_select(move || {
                        checking.clone().start_check();
                    }));
                }
                items
            }
        }
    }
}

fn show_unavailable(owner: Owner, busy: Signal<bool>, error: String, labels: UpdateLabels) -> bool {
    if !owner.is_live() || busy.get_untracked() {
        return false;
    }
    busy.set(true);
    owner.run(move || {
        spawn(async move {
            show_error(error, &labels).await;
            if owner.is_live() {
                busy.set(false);
            }
        });
    });
    true
}

pub(crate) fn mount() {
    let updates = UpdateActions::installed(Rc::new(StandaloneLifecycle));
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
    fn start_check(self: Rc<Self>) -> bool {
        if !self.owner.is_live() || self.phase.get_untracked() != Phase::Idle {
            return false;
        }
        self.downloaded.set(None);
        self.start();
        true
    }
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
        let Some(mut lease) = self.lifecycle.prepare().await? else {
            return Ok(());
        };
        if !self.owner.is_live() || !lease.owner.is_live() {
            return Ok(());
        }
        lease.dispatched();
        match updater.install(downloaded).await {
            Ok(()) => {
                if !self.owner.is_live() {
                    return Ok(());
                }
                self.downloaded.set(None);
                lease.restart()
            }
            Err(error) => {
                // These categories can only precede NSH's filesystem replacement.
                // Installation may include a failed rollback; Stopped can mean
                // a lost reply after execution. Neither proves it is safe to thaw.
                if failed_before_replacement(error.code()) {
                    lease.abort();
                }
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

fn failed_before_replacement(code: ErrorCode) -> bool {
    match code {
        ErrorCode::Verification
        | ErrorCode::Stale
        | ErrorCode::Cancelled
        | ErrorCode::Transport
        | ErrorCode::Busy => true,
        ErrorCode::Configuration | ErrorCode::Installation | ErrorCode::Stopped => false,
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
    use nsh_core::{Command, desktop::DesktopCommand, element::create_root};
    use nsh_engine::{EngineConfig, EngineContext, Root};
    use nsh_testing::{DialogAnswer, Headless};
    use std::{
        sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        },
        time::Duration,
    };

    #[derive(Clone, Copy)]
    enum Preparation {
        Ready,
        Error,
        Cancel,
        Retired,
        RestartError,
    }
    #[derive(Clone)]
    struct HookFixture {
        preparation: Preparation,
        install_error: Option<ErrorCode>,
        prepared: Arc<AtomicUsize>,
        aborted: Arc<AtomicUsize>,
        relaunched: Arc<AtomicUsize>,
    }
    impl HookFixture {
        fn new(preparation: Preparation) -> Self {
            Self {
                preparation,
                install_error: None,
                prepared: Arc::default(),
                aborted: Arc::default(),
                relaunched: Arc::default(),
            }
        }
        fn counts(&self) -> (usize, usize, usize) {
            (
                self.prepared.load(Ordering::SeqCst),
                self.aborted.load(Ordering::SeqCst),
                self.relaunched.load(Ordering::SeqCst),
            )
        }
        fn lease(&self) -> InstallLease {
            let aborted = self.aborted.clone();
            let relaunched = self.relaunched.clone();
            let mode = self.preparation;
            InstallLease::new(
                move || {
                    aborted.fetch_add(1, Ordering::SeqCst);
                },
                move || {
                    relaunched.fetch_add(1, Ordering::SeqCst);
                    if matches!(mode, Preparation::RestartError) {
                        Err("application relaunch refused".into())
                    } else {
                        Ok(())
                    }
                },
            )
        }
    }
    struct TestLifecycle(HookFixture);
    impl UpdateLifecycle for TestLifecycle {
        fn prepare(&self) -> InstallPreparation {
            let fixture = self.0.clone();
            Box::pin(async move {
                fixture.prepared.fetch_add(1, Ordering::SeqCst);
                match fixture.preparation {
                    Preparation::Error => Err("application save failed".into()),
                    Preparation::Cancel => Ok(None),
                    Preparation::Retired => {
                        let (owner, lease) = create_root(|| fixture.lease());
                        owner.dispose();
                        Ok(Some(lease))
                    }
                    _ => Ok(Some(fixture.lease())),
                }
            })
        }
    }

    #[derive(Clone, PartialEq, Props)]
    struct ActionProps {
        cancelled: Prop<bool>,
        verification_error: Prop<bool>,
    }

    #[component]
    fn ActionProbe(props: ActionProps) -> impl IntoElement {
        let hook = engine_context::<HookFixture>();
        let install_error = hook
            .as_ref()
            .and_then(|hook| hook.install_error)
            .or_else(|| {
                props
                    .verification_error
                    .get_untracked()
                    .then_some(ErrorCode::Verification)
            });
        let (updater, operations) =
            crate::update::tests::menu_fixture(props.cancelled.get_untracked(), install_error);
        let lifecycle: Rc<dyn UpdateLifecycle> = hook
            .map(|fixture| Rc::new(TestLifecycle((*fixture).clone())) as Rc<dyn UpdateLifecycle>)
            .unwrap_or_else(|| Rc::new(StandaloneLifecycle));
        let contribution = UpdateActions::new(updater, lifecycle);
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
        let check = contribution.clone();
        let observed = contribution.clone();
        let checks = signal(Vec::<bool>::new());
        view()
            .flex_col()
            .child(
                button()
                    .on_press(move || selected.clone().start())
                    .child(text("Run update")),
            )
            .child(
                button()
                    .on_press(move || {
                        let first = check.check_for_updates(UpdateLabels::default()).unwrap();
                        let repeated = check.check_for_updates(UpdateLabels::default()).unwrap();
                        checks.set(vec![first, repeated]);
                    })
                    .child(text("Public check")),
            )
            .child(text(move || {
                format!(
                    "{:?} cached={} operations={:?} busy={} checks={:?}",
                    actions.phase.get(),
                    actions.downloaded.get().is_some(),
                    operations.lock().unwrap(),
                    observed.is_busy(),
                    checks.get()
                )
            }))
    }

    fn start(cancelled: bool, verification_error: bool) -> Headless {
        start_with_hook(cancelled, verification_error, None)
    }

    fn start_with_hook(
        cancelled: bool,
        verification_error: bool,
        hook: Option<HookFixture>,
    ) -> Headless {
        let mut config = EngineConfig::new(Root::new::<ActionProbe>(move || ActionProps {
            cancelled: Prop::new(cancelled),
            verification_error: Prop::new(verification_error),
        }));
        // NSH intentionally does not install application menus on phones;
        // this probe qualifies the actual desktop menu shortcut path.
        if let Some(hook) = hook {
            config.context = EngineContext::default().with(hook);
        }
        config.environment.os = nsh_core::platform::Os::Linux;
        config.environment.idiom = nsh_core::platform::Idiom::Desktop;
        let mut app = Headless::start(config).unwrap();
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
    fn public_check_reuses_busy_dialogs_and_rechecks_cached_download_without_preparation() {
        let hook = HookFixture::new(Preparation::Ready);
        let mut app = start_with_hook(false, false, Some(hook.clone()));
        download(&mut app);
        app.answer_dialog(DialogAnswer::Press("Later".into()))
            .unwrap();
        wait_status(&mut app, "Idle cached=true");
        app.press("text:Public check").unwrap();
        wait_dialog(&mut app);
        wait_status(&mut app, "busy=true checks=[true, false]");
        let dialog = app.pending_dialog().unwrap();
        assert!(
            dialog
                .buttons
                .iter()
                .any(|button| button.text == "Download")
        );
        assert!(
            !dialog
                .buttons
                .iter()
                .any(|button| button.text == "Install and Restart")
        );
        assert_eq!(hook.counts(), (0, 0, 0));
        app.answer_dialog(DialogAnswer::Press("Later".into()))
            .unwrap();
        wait_status(&mut app, "Idle cached=false");
        wait_status(
            &mut app,
            "operations=[\"check\", \"download\", \"check\"] busy=false",
        );
        assert_eq!(hook.counts(), (0, 0, 0));
        assert!(!restarted(&app));
    }

    #[component]
    fn RetiredCheckProbe() -> impl IntoElement {
        let (updater, operations) = crate::update::tests::menu_fixture(false, None);
        let (owner, updates) =
            create_root(|| UpdateActions::new(updater, Rc::new(StandaloneLifecycle)));
        owner.dispose();
        assert!(!updates.check_for_updates(UpdateLabels::default()).unwrap());
        assert!(!updates.is_busy());
        assert!(operations.lock().unwrap().is_empty());
        text("Retired public check is inert")
    }
    #[test]
    fn retained_public_check_does_not_restart_a_retired_owner() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<RetiredCheckProbe>())).unwrap();
        app.wait_for("text:Retired public check is inert").unwrap();
    }
    #[test]
    fn unconfigured_public_check_is_inert_and_dynamic_labels_remain_validated() {
        let updates = UpdateActions(Rc::new(State::Disabled));
        assert!(!updates.check_for_updates(UpdateLabels::default()).unwrap());
        assert!(!updates.is_busy());
        let invalid = UpdateLabels {
            menu_check: String::new(),
            ..UpdateLabels::default()
        };
        assert!(updates.check_for_updates(invalid).is_err());
    }

    #[component]
    fn UnavailableCheckProbe() -> impl IntoElement {
        let updates = UpdateActions(Rc::new(State::Unavailable {
            owner: Owner::current(),
            error: "Invalid installed update configuration".into(),
            busy: signal(false),
        }));
        let observed = updates.clone();
        let decisions = signal(Vec::<bool>::new());
        view()
            .child(
                button()
                    .on_press(move || {
                        let first = updates.check_for_updates(UpdateLabels::default()).unwrap();
                        let repeated = updates.check_for_updates(UpdateLabels::default()).unwrap();
                        decisions.set(vec![first, repeated]);
                    })
                    .child(text("Check unavailable source")),
            )
            .child(text(move || {
                format!(
                    "error busy={} accepted={:?}",
                    observed.is_busy(),
                    decisions.get()
                )
            }))
    }
    #[test]
    fn unavailable_checks_share_one_busy_dialog_and_rearm_only_after_it_closes() {
        let mut app =
            Headless::start(EngineConfig::new(Root::of::<UnavailableCheckProbe>())).unwrap();
        app.answer_dialogs_myself();
        app.wait_for("text:error busy=false accepted=[]").unwrap();
        for _ in 0..2 {
            app.press("text:Check unavailable source").unwrap();
            wait_dialog(&mut app);
            wait_status(&mut app, "error busy=true accepted=[true, false]");
            app.answer_dialog(DialogAnswer::Press("OK".into())).unwrap();
            wait_status(&mut app, "error busy=false accepted=[true, false]");
            assert!(
                app.pending_dialog().is_none(),
                "no repeated error sheet is queued"
            );
        }
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

    fn confirm_install(app: &mut Headless) {
        download(app);
        app.answer_dialog(DialogAnswer::Press("Install and Restart".into()))
            .unwrap();
    }

    fn assert_no_install(app: &Headless) {
        assert!(
            app.screen()
                .texts()
                .iter()
                .any(|text| { text.contains("operations=[\"check\", \"download\"]") })
        );
        assert!(!restarted(app));
    }

    #[test]
    fn save_error_retains_verified_download_without_install_or_restart() {
        let hook = HookFixture::new(Preparation::Error);
        let mut app = start_with_hook(false, false, Some(hook.clone()));
        confirm_install(&mut app);
        wait_dialog(&mut app);
        app.answer_dialog(DialogAnswer::Press("OK".into())).unwrap();
        wait_status(&mut app, "Idle cached=true");
        assert_no_install(&app);
        assert_eq!(hook.counts(), (1, 0, 0));
    }

    #[test]
    fn preparation_cancel_retains_download_without_error_dialog() {
        let hook = HookFixture::new(Preparation::Cancel);
        let mut app = start_with_hook(false, false, Some(hook.clone()));
        confirm_install(&mut app);
        wait_status(&mut app, "Idle cached=true");
        assert_no_install(&app);
        assert!(app.pending_dialog().is_none());
        assert_eq!(hook.counts(), (1, 0, 0));
    }

    #[test]
    fn retired_preparation_owner_cannot_install_or_restart() {
        let hook = HookFixture::new(Preparation::Retired);
        let mut app = start_with_hook(false, false, Some(hook.clone()));
        confirm_install(&mut app);
        wait_status(&mut app, "Idle cached=true");
        assert_no_install(&app);
        assert_eq!(hook.counts(), (1, 0, 0));
    }

    #[test]
    fn failed_archive_preflight_releases_live_application_preparation_once() {
        let hook = HookFixture::new(Preparation::Ready);
        let mut app = start_with_hook(false, true, Some(hook.clone()));
        confirm_install(&mut app);
        wait_dialog(&mut app);
        app.answer_dialog(DialogAnswer::Press("OK".into())).unwrap();
        wait_status(&mut app, "Idle cached=false");
        assert_eq!(hook.counts(), (1, 1, 0));
        assert!(!restarted(&app));
    }

    #[test]
    fn uncertain_installation_and_lost_worker_reply_never_thaw_or_restart() {
        for code in [ErrorCode::Installation, ErrorCode::Stopped] {
            let hook = HookFixture {
                install_error: Some(code),
                ..HookFixture::new(Preparation::Ready)
            };
            let mut app = start_with_hook(false, false, Some(hook.clone()));
            confirm_install(&mut app);
            wait_dialog(&mut app);
            app.answer_dialog(DialogAnswer::Press("OK".into())).unwrap();
            wait_status(&mut app, "Idle cached=true");
            assert_eq!(hook.counts(), (1, 0, 0), "uncertain failure: {code:?}");
            assert!(!restarted(&app));
            assert!(app.screen().texts().iter().any(|text| {
                text.contains("operations=[\"check\", \"download\", \"install\"]")
            }));
        }
    }

    #[test]
    fn installed_application_uses_only_its_own_relaunch_callback() {
        let hook = HookFixture::new(Preparation::Ready);
        let mut app = start_with_hook(false, false, Some(hook.clone()));
        confirm_install(&mut app);
        wait_status(&mut app, "Idle cached=false");
        assert_eq!(hook.counts(), (1, 0, 1));
        assert!(!restarted(&app));
        assert!(app.pending_dialog().is_none());
    }

    #[test]
    fn failed_relaunch_never_thaws_the_committed_application() {
        let hook = HookFixture::new(Preparation::RestartError);
        let mut app = start_with_hook(false, false, Some(hook.clone()));
        confirm_install(&mut app);
        wait_dialog(&mut app);
        app.answer_dialog(DialogAnswer::Press("OK".into())).unwrap();
        wait_status(&mut app, "Idle cached=false");
        assert_eq!(hook.counts(), (1, 0, 1));
        assert!(!restarted(&app));
    }

    #[component]
    fn LeaseDropProbe() -> impl IntoElement {
        let hook = HookFixture::new(Preparation::Ready);
        drop(hook.lease());
        assert_eq!(hook.counts(), (0, 1, 0));
        let mut dispatched = hook.lease();
        dispatched.dispatched();
        drop(dispatched);
        assert_eq!(hook.counts(), (0, 1, 0));

        let (owner, mut retired) = create_root(|| hook.lease());
        retired.dispatched();
        owner.dispose();
        assert!(retired.restart().is_err());
        assert_eq!(hook.counts(), (0, 1, 0));
        text("Owned install lease checks passed")
    }

    #[test]
    fn cancelled_inflight_and_retired_restart_leases_do_not_resume_old_work() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<LeaseDropProbe>())).unwrap();
        app.wait_for("text:Owned install lease checks passed")
            .unwrap();
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
        assert!(
            app.screen().commands().iter().any(|(_, command)| {
                matches!(command, Command::Desktop(command)
                if matches!(&**command, DesktopCommand::SetMenu(Some(_))))
            }),
            "desktop fixture did not install its actual application menu"
        );
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
        let (owner, updates) =
            create_root(|| UpdateActions::new(updater, Rc::new(StandaloneLifecycle)));
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
        let mut labels = UpdateLabels {
            menu_check: "检查更新…".into(),
            ..Default::default()
        };
        assert!(labels.validate().is_ok());
        labels.version_notes = "Missing version and notes".into();
        assert!(labels.validate().is_err());
        labels = UpdateLabels::default();
        labels.menu_cancel.clear();
        assert!(labels.validate().is_err());
    }
}
