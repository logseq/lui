//! Signed whole-application updates on one worker and one streamed HTTP client.
use nsh_updater::{Available, Config, Download, install::Installation};
use std::{
    fmt,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
        mpsc::{self, SyncSender},
    },
    thread,
    time::{Duration, Instant},
};
use tokio::sync::{oneshot, watch};

const MAX_MANIFEST: u64 = 1 << 20;
const MAX_SIGNATURE: u64 = 4096;
const MAX_ARCHIVE: u64 = 2 << 30;
const READ_TIMEOUT: Duration = Duration::from_secs(15);
static NEXT_OWNER: AtomicU64 = AtomicU64::new(1);

/// A failure category applications can match without inspecting messages.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum ErrorCode {
    Configuration,
    Transport,
    Verification,
    Installation,
    Cancelled,
    Stale,
    Busy,
    Stopped,
}

/// Why an update operation could not complete.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateError {
    code: ErrorCode,
    message: String,
}
impl UpdateError {
    fn new(code: ErrorCode, message: impl ToString) -> Self {
        Self {
            code,
            message: message.to_string(),
        }
    }
    /// The stable category of this failure.
    pub fn code(&self) -> ErrorCode {
        self.code
    }
    /// A human-readable description.
    pub fn message(&self) -> &str {
        &self.message
    }
}
impl fmt::Display for UpdateError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}
impl std::error::Error for UpdateError {}

type Result<T> = std::result::Result<T, UpdateError>;

/// The latest update state. Watch subscriptions retain only this value.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
#[non_exhaustive]
pub enum Progress {
    #[default]
    Idle,
    Checking,
    Available,
    Downloading {
        received: u64,
        total: u64,
    },
    Downloaded,
    Installing,
    Installed,
    Cancelled,
    Failed {
        code: ErrorCode,
        message: String,
    },
}

/// An authenticated update offered to one updater instance.
#[derive(Debug, Clone)]
pub struct Offer {
    owner: u64,
    ticket: u64,
    available: Available,
    can_install: bool,
}
impl Offer {
    /// The newer application version.
    pub fn version(&self) -> &str {
        &self.available.version
    }
    /// The release notes, when provided by the signed manifest.
    pub fn notes(&self) -> Option<&str> {
        self.available.notes.as_deref()
    }
    /// The authenticated download or store URL.
    pub fn url(&self) -> &str {
        &self.available.url
    }
    /// Whether this is an archive and this installation is currently writable.
    pub fn can_install(&self) -> bool {
        self.can_install
    }
}

/// A verified download retained by its updater until install or replacement.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Downloaded {
    owner: u64,
    ticket: u64,
}

struct Inner {
    commands: SyncSender<Command>,
    epoch: Arc<AtomicU64>,
    progress: watch::Receiver<Progress>,
}
impl Drop for Inner {
    fn drop(&mut self) {
        // The worker owns no sender. Once this handle closes, it exits after
        // its active read's finite deadline, removing any partial archive.
        self.epoch.fetch_add(1, Ordering::Release);
    }
}

/// Application-owned updater. Clones share one worker and connection pool.
#[derive(Clone)]
pub struct Updater(Arc<Inner>);
impl Updater {
    /// Opens the updater configuration beside an installed executable.
    /// Returns `None` without creating a cache, worker or request when the
    /// package has no updater asset. Development library overrides are ignored.
    pub fn from_installed(executable: &Path, cache: &Path) -> Result<Option<Self>> {
        installed_configuration(executable)?
            .map(|bytes| Self::open(&bytes, executable, cache))
            .transpose()
    }

    /// Opens an installed package whose embedded configuration matches `config`.
    /// The writable cache must be outside the installed application directory.
    /// No worker, polling timer or network request is created for a dev shell.
    pub fn open(config: &[u8], executable: &Path, cache: &Path) -> Result<Self> {
        let parsed = Config::parse(config)
            .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?;
        validate_config(&parsed)?;
        let executable = fs::canonicalize(executable)
            .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?;
        let installation = Installation::of(&executable, &parsed.id, config).ok_or_else(|| {
            UpdateError::new(
                ErrorCode::Configuration,
                "updates require the matching installed package, not a development shell",
            )
        })?;
        let owner = NEXT_OWNER.fetch_add(1, Ordering::Relaxed);
        let cache = Cache::new(cache, &executable, owner)?;
        let agent = ureq::Agent::config_builder()
            .https_only(true)
            .max_redirects(10)
            .timeout_resolve(Some(READ_TIMEOUT))
            .timeout_connect(Some(READ_TIMEOUT))
            .timeout_recv_response(Some(READ_TIMEOUT))
            .timeout_per_read(Some(READ_TIMEOUT))
            .tls_config(
                ureq::tls::TlsConfig::builder()
                    .root_certs(ureq::tls::RootCerts::PlatformVerifier)
                    .build(),
            )
            .build()
            .into();
        let epoch = Arc::new(AtomicU64::new(0));
        let (progress, receiver) = watch::channel(Progress::Idle);
        let (commands, requests) = mpsc::sync_channel(8);
        let mut worker = Worker {
            owner,
            config: parsed,
            installation,
            cache,
            agent,
            epoch: epoch.clone(),
            progress,
            latest: None,
            ready: None,
            next_ticket: 0,
        };
        thread::Builder::new()
            .name("lui-updater".into())
            .spawn(move || {
                while let Ok(command) = requests.recv() {
                    worker.handle(command);
                }
            })
            .map_err(|error| UpdateError::new(ErrorCode::Stopped, error))?;
        Ok(Self(Arc::new(Inner {
            commands,
            epoch,
            progress: receiver,
        })))
    }

    /// Subscribes to coalesced progress without polling the worker.
    pub fn progress(&self) -> watch::Receiver<Progress> {
        self.0.progress.clone()
    }

    /// Invalidates pending checks/downloads. A blocked read has a 15 s deadline.
    /// Installation is indivisible once begun and is not cancelled halfway.
    pub fn cancel(&self) {
        self.0.epoch.fetch_add(1, Ordering::Release);
    }

    /// Fetches and authenticates the current manifest and detached signature.
    pub async fn check(&self) -> Result<Option<Offer>> {
        self.request(|epoch, reply| Command::Check { epoch, reply })
            .await
    }

    /// Streams this instance's current authenticated offer into a private file.
    pub async fn download(&self, offer: Offer) -> Result<Downloaded> {
        self.request(|epoch, reply| Command::Download {
            epoch,
            offer,
            reply,
        })
        .await
    }

    /// Verifies the archive again and replaces the whole application.
    /// The application owns any subsequent restart and must wait for success.
    pub async fn install(&self, downloaded: Downloaded) -> Result<()> {
        self.request(|epoch, reply| Command::Install {
            epoch,
            downloaded,
            reply,
        })
        .await
    }

    async fn request<T>(
        &self,
        command: impl FnOnce(u64, oneshot::Sender<Result<T>>) -> Command,
    ) -> Result<T> {
        let epoch = self.0.epoch.load(Ordering::Acquire);
        let (reply, result) = oneshot::channel();
        self.0
            .commands
            .try_send(command(epoch, reply))
            .map_err(|error| match error {
                mpsc::TrySendError::Full(_) => {
                    UpdateError::new(ErrorCode::Busy, "update request queue is full")
                }
                mpsc::TrySendError::Disconnected(_) => {
                    UpdateError::new(ErrorCode::Stopped, "update worker stopped")
                }
            })?;
        result
            .await
            .map_err(|_| UpdateError::new(ErrorCode::Stopped, "update worker stopped"))?
    }
}

enum Command {
    Check {
        epoch: u64,
        reply: oneshot::Sender<Result<Option<Offer>>>,
    },
    Download {
        epoch: u64,
        offer: Offer,
        reply: oneshot::Sender<Result<Downloaded>>,
    },
    Install {
        epoch: u64,
        downloaded: Downloaded,
        reply: oneshot::Sender<Result<()>>,
    },
}
struct Worker {
    owner: u64,
    config: Config,
    installation: Installation,
    cache: Cache,
    agent: ureq::Agent,
    epoch: Arc<AtomicU64>,
    progress: watch::Sender<Progress>,
    latest: Option<Offer>,
    ready: Option<Archive>,
    next_ticket: u64,
}
impl Worker {
    fn handle(&mut self, command: Command) {
        match command {
            Command::Check { epoch, reply } => {
                if reply.is_closed() {
                    return;
                }
                let result = self.check(epoch);
                self.report_error(&result);
                let _ = reply.send(result);
            }
            Command::Download {
                epoch,
                offer,
                reply,
            } => {
                if reply.is_closed() {
                    return;
                }
                let result = self.download(epoch, offer);
                self.report_error(&result);
                let _ = reply.send(result);
            }
            Command::Install {
                epoch,
                downloaded,
                reply,
            } => {
                if reply.is_closed() {
                    return;
                }
                let result = self.install(epoch, downloaded);
                self.report_error(&result);
                let _ = reply.send(result);
            }
        }
    }
    fn report_error<T>(&self, result: &Result<T>) {
        if let Err(error) = result {
            let progress = if error.code == ErrorCode::Cancelled {
                Progress::Cancelled
            } else {
                Progress::Failed {
                    code: error.code,
                    message: error.message.clone(),
                }
            };
            self.progress.send_replace(progress);
        }
    }
    fn check(&mut self, epoch: u64) -> Result<Option<Offer>> {
        check_epoch(&self.epoch, epoch)?;
        self.progress.send_replace(Progress::Checking);
        self.latest = None;
        self.ready = None;
        let manifest = self.fetch_small(&self.config.manifest_url(), MAX_MANIFEST, epoch)?;
        let signature_url = self.config.signature_url().ok_or_else(|| {
            UpdateError::new(ErrorCode::Configuration, "update public key is missing")
        })?;
        let signature = self.fetch_small(&signature_url, MAX_SIGNATURE, epoch)?;
        check_epoch(&self.epoch, epoch)?;
        let available = self
            .config
            .check(&manifest, Some(&signature), &nsh_updater::platform())
            .map_err(|error| UpdateError::new(ErrorCode::Verification, error))?;
        self.next_ticket = self.next_ticket.checked_add(1).ok_or_else(|| {
            UpdateError::new(ErrorCode::Stopped, "update offer sequence exhausted")
        })?;
        self.latest = available.map(|available| Offer {
            owner: self.owner,
            ticket: self.next_ticket,
            can_install: available.sha256.is_some()
                && available.size.is_some()
                && self.installation.can_install(),
            available,
        });
        self.progress.send_replace(if self.latest.is_some() {
            Progress::Available
        } else {
            Progress::Idle
        });
        Ok(self.latest.clone())
    }
    fn fetch_small(&self, url: &str, limit: u64, epoch: u64) -> Result<Vec<u8>> {
        check_epoch(&self.epoch, epoch)?;
        let mut response = self
            .agent
            .get(url)
            .call()
            .map_err(|error| UpdateError::new(ErrorCode::Transport, error))?;
        let mut body = response.body_mut().as_reader().take(limit + 1);
        let mut result = Vec::new();
        let mut chunk = [0; 8192];
        loop {
            check_epoch(&self.epoch, epoch)?;
            let read = body.read(&mut chunk);
            check_epoch(&self.epoch, epoch)?;
            let count = read.map_err(|error| UpdateError::new(ErrorCode::Transport, error))?;
            if count == 0 {
                break;
            }
            result.extend_from_slice(&chunk[..count]);
            if result.len() as u64 > limit {
                return Err(UpdateError::new(
                    ErrorCode::Verification,
                    "update metadata exceeds its byte limit",
                ));
            }
        }
        check_epoch(&self.epoch, epoch)?;
        Ok(result)
    }
    fn current(&self, owner: u64, ticket: u64) -> Result<&Offer> {
        self.latest
            .as_ref()
            .filter(|offer| offer.owner == owner && owner == self.owner && offer.ticket == ticket)
            .ok_or_else(|| UpdateError::new(ErrorCode::Stale, "update offer is stale or foreign"))
    }
    fn download(&mut self, epoch: u64, offer: Offer) -> Result<Downloaded> {
        check_epoch(&self.epoch, epoch)?;
        let offer = self.current(offer.owner, offer.ticket)?.clone();
        if !offer.can_install || !self.installation.can_install() {
            return Err(UpdateError::new(
                ErrorCode::Installation,
                "update is a link or this application cannot be replaced",
            ));
        }
        self.ready = None;
        let (hash, size) = archive_requirements(&offer.available)?;
        let archive = Archive(self.cache.0.join("application.download"));
        let mut file = private_file(&archive.0)?;
        let mut response = self
            .agent
            .get(&offer.available.url)
            .call()
            .map_err(|error| UpdateError::new(ErrorCode::Transport, error))?;
        stream_archive(
            response.body_mut().as_reader(),
            &mut file,
            &hash,
            size,
            &self.epoch,
            epoch,
            |received| {
                self.progress.send_replace(Progress::Downloading {
                    received,
                    total: size,
                });
            },
        )?;
        file.sync_all()
            .map_err(|error| UpdateError::new(ErrorCode::Transport, error))?;
        check_epoch(&self.epoch, epoch)?;
        self.ready = Some(archive);
        self.progress.send_replace(Progress::Downloaded);
        Ok(Downloaded {
            owner: offer.owner,
            ticket: offer.ticket,
        })
    }
    fn install(&mut self, epoch: u64, downloaded: Downloaded) -> Result<()> {
        check_epoch(&self.epoch, epoch)?;
        let offer = self.current(downloaded.owner, downloaded.ticket)?.clone();
        let archive = self.ready.as_ref().ok_or_else(|| {
            UpdateError::new(
                ErrorCode::Stale,
                "verified update archive is no longer available",
            )
        })?;
        let (hash, size) = archive_requirements(&offer.available)?;
        let mut file = File::open(&archive.0)
            .map_err(|error| UpdateError::new(ErrorCode::Verification, error))?;
        stream_archive(
            &mut file,
            &mut std::io::sink(),
            &hash,
            size,
            &self.epoch,
            epoch,
            |_| {},
        )?;
        check_epoch(&self.epoch, epoch)?;
        if !self.installation.can_install() {
            return Err(UpdateError::new(
                ErrorCode::Installation,
                "application installation is not writable",
            ));
        }
        self.progress.send_replace(Progress::Installing);
        self.installation
            .install(&archive.0)
            .map_err(|error| UpdateError::new(ErrorCode::Installation, error))?;
        self.ready = None;
        self.latest = None;
        self.progress.send_replace(Progress::Installed);
        Ok(())
    }
}

pub(crate) fn installed_configuration(executable: &Path) -> Result<Option<Vec<u8>>> {
    let directory = executable.parent().ok_or_else(|| {
        UpdateError::new(
            ErrorCode::Configuration,
            "executable has no parent directory",
        )
    })?;
    let resources = if cfg!(target_os = "macos") {
        directory.join("../Resources/nsh/assets")
    } else {
        directory.join("nsh/assets")
    };
    let file = match File::open(resources.join(nsh_updater::CONFIG_ASSET)) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(UpdateError::new(ErrorCode::Configuration, error)),
    };
    let mut bytes = Vec::new();
    file.take(MAX_MANIFEST + 1)
        .read_to_end(&mut bytes)
        .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?;
    if bytes.len() as u64 > MAX_MANIFEST {
        return Err(UpdateError::new(
            ErrorCode::Configuration,
            "installed updater configuration exceeds 1 MiB",
        ));
    }
    Ok(Some(bytes))
}

fn validate_config(config: &Config) -> Result<()> {
    if config.public_key.is_none() || config.packages.is_some() {
        return Err(UpdateError::new(
            ErrorCode::Configuration,
            "compiled LUI applications require signed whole-application updates",
        ));
    }
    Ok(())
}
fn archive_requirements(available: &Available) -> Result<(String, u64)> {
    let hash = available
        .sha256
        .as_ref()
        .filter(|hash| hash.len() == 64 && hash.bytes().all(|byte| byte.is_ascii_hexdigit()));
    match (hash, available.size) {
        (Some(hash), Some(size)) if size > 0 && size <= MAX_ARCHIVE => Ok((hash.clone(), size)),
        _ => Err(UpdateError::new(
            ErrorCode::Verification,
            "update archive needs a SHA-256 and size between 1 byte and 2 GiB",
        )),
    }
}
fn check_epoch(current: &AtomicU64, expected: u64) -> Result<()> {
    if current.load(Ordering::Acquire) == expected {
        Ok(())
    } else {
        Err(UpdateError::new(
            ErrorCode::Cancelled,
            "update was cancelled",
        ))
    }
}
fn stream_archive(
    mut reader: impl Read,
    mut writer: impl Write,
    hash: &str,
    size: u64,
    epoch: &AtomicU64,
    expected: u64,
    mut progress: impl FnMut(u64),
) -> Result<()> {
    let mut validation = Download::new(hash, Some(size));
    let mut chunk = [0; 64 << 10];
    let mut last_progress = Instant::now();
    let mut received = 0;
    progress(0);
    loop {
        check_epoch(epoch, expected)?;
        let read = reader.read(&mut chunk);
        check_epoch(epoch, expected)?;
        let count = read.map_err(|error| UpdateError::new(ErrorCode::Transport, error))?;
        if count == 0 {
            break;
        }
        received = validation
            .update(&chunk[..count])
            .map_err(|error| UpdateError::new(ErrorCode::Verification, error))?;
        writer
            .write_all(&chunk[..count])
            .map_err(|error| UpdateError::new(ErrorCode::Transport, error))?;
        if last_progress.elapsed() >= Duration::from_millis(100) {
            progress(received);
            last_progress = Instant::now();
        }
    }
    validation
        .finish()
        .map_err(|error| UpdateError::new(ErrorCode::Verification, error))?;
    progress(received);
    Ok(())
}

// Resolve the existing ancestor before creating anything, so a rejected cache
// inside the signed application does not invalidate its signature.
fn future_path(path: &Path) -> Result<PathBuf> {
    let absolute = if path.is_absolute() {
        path.to_owned()
    } else {
        std::env::current_dir()
            .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?
            .join(path)
    };
    let mut ancestor = absolute.as_path();
    let mut missing = Vec::new();
    while !ancestor.exists() {
        missing.push(
            ancestor
                .file_name()
                .ok_or_else(|| UpdateError::new(ErrorCode::Configuration, "invalid cache path"))?,
        );
        ancestor = ancestor.parent().ok_or_else(|| {
            UpdateError::new(ErrorCode::Configuration, "cache has no existing ancestor")
        })?;
    }
    let mut resolved = fs::canonicalize(ancestor)
        .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?;
    for component in missing.into_iter().rev() {
        resolved.push(component);
    }
    Ok(resolved)
}

struct Cache(PathBuf);
impl Cache {
    fn new(parent: &Path, executable: &Path, owner: u64) -> Result<Self> {
        let parent = future_path(parent)?;
        let installed = if cfg!(target_os = "macos") {
            executable
                .parent()
                .and_then(Path::parent)
                .and_then(Path::parent)
        } else {
            executable.parent()
        }
        .ok_or_else(|| {
            UpdateError::new(ErrorCode::Configuration, "invalid installed executable")
        })?;
        let installed = fs::canonicalize(installed)
            .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?;
        if parent.starts_with(installed) {
            return Err(UpdateError::new(
                ErrorCode::Configuration,
                "update cache must be outside the installed application",
            ));
        }
        fs::create_dir_all(&parent)
            .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?;
        let path = parent.join(format!("lui-update-{}-{owner}", std::process::id()));
        let builder = fs::DirBuilder::new();
        #[cfg(unix)]
        let builder = {
            use std::os::unix::fs::DirBuilderExt;
            let mut builder = builder;
            builder.mode(0o700);
            builder
        };
        builder
            .create(&path)
            .map_err(|error| UpdateError::new(ErrorCode::Configuration, error))?;
        Ok(Self(path))
    }
}
impl Drop for Cache {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
struct Archive(PathBuf);
impl Drop for Archive {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
fn private_file(path: &Path) -> Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options
        .open(path)
        .map_err(|error| UpdateError::new(ErrorCode::Transport, error))
}

#[cfg(test)]
#[path = "update_tests.rs"]
mod tests;
