use super::*;
use serde_json::json;
use std::io::Cursor;
#[cfg(unix)]
use std::process::Command;

// Deterministic public test material; never use these keys for distribution.
const SECRET: &str = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=";
const PUBLIC: &str = "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w=";

struct Temporary(PathBuf);
impl Temporary {
    fn new() -> Self {
        for _ in 0..100 {
            let id = NEXT_OWNER.fetch_add(1, Ordering::Relaxed);
            let path =
                std::env::temp_dir().join(format!("lui-update-test-{}-{id}", std::process::id()));
            if fs::create_dir(&path).is_ok() {
                return Self(path);
            }
        }
        panic!("cannot create update test directory");
    }
}
impl Drop for Temporary {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn configuration(version: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "id": "com.logseq.update-fixture", "version": version,
        "url": "https://updates.example.test/latest.json", "publicKey": PUBLIC
    }))
    .unwrap()
}
fn signed_offer(
    config: &Config,
    version: &str,
    id: &str,
    platform: &str,
    archive: &[u8],
) -> Result<Option<Available>> {
    let bytes = serde_json::to_vec(&json!({
        "id": id, "version": version,
        "platforms": { (platform): {
            "url": "Application.tar.gz", "sha256": nsh_updater::sha256(archive),
            "size": archive.len()
        }}
    }))
    .unwrap();
    let signature = nsh_updater::sign(SECRET, &bytes).unwrap();
    config
        .check(&bytes, Some(signature.as_bytes()), &nsh_updater::platform())
        .map_err(|error| UpdateError::new(ErrorCode::Verification, error))
}

pub(crate) fn menu_fixture(
    cancelled_check: bool,
    install_error: Option<ErrorCode>,
) -> (Updater, Arc<std::sync::Mutex<Vec<&'static str>>>) {
    let owner = NEXT_OWNER.fetch_add(1, Ordering::Relaxed);
    let config = Config::parse(&configuration("1.0.0")).unwrap();
    let available = signed_offer(
        &config,
        "2.0.0",
        &config.id,
        &nsh_updater::platform(),
        b"menu action fixture",
    )
    .unwrap()
    .unwrap();
    let offer = Offer {
        owner,
        ticket: 1,
        available,
        can_install: true,
    };
    let (progress, receiver) = watch::channel(Progress::Idle);
    let (commands, requests) = mpsc::sync_channel(8);
    let observed = Arc::new(std::sync::Mutex::new(Vec::new()));
    let operations = observed.clone();
    thread::spawn(move || {
        let _progress = progress;
        while let Ok(command) = requests.recv() {
            match command {
                super::Command::Check { reply, .. } => {
                    operations.lock().unwrap().push("check");
                    let result = if cancelled_check {
                        Err(UpdateError::new(ErrorCode::Cancelled, "cancelled fixture"))
                    } else {
                        Ok(Some(offer.clone()))
                    };
                    let _ = reply.send(result);
                }
                super::Command::Download { reply, .. } => {
                    operations.lock().unwrap().push("download");
                    let _ = reply.send(Ok(Downloaded { owner, ticket: 1 }));
                }
                super::Command::Install { reply, .. } => {
                    operations.lock().unwrap().push("install");
                    let result = install_error.map_or(Ok(()), |code| {
                        Err(UpdateError::new(code, "installation fixture"))
                    });
                    let _ = reply.send(result);
                }
            }
        }
    });
    (
        Updater(Arc::new(Inner {
            commands,
            epoch: Arc::new(AtomicU64::new(0)),
            progress: receiver,
        })),
        observed,
    )
}

#[test]
fn signed_manifests_reject_tampering_wrong_apps_and_stale_versions() {
    let config = Config::parse(&configuration("1.0.0")).unwrap();
    validate_config(&config).unwrap();
    let platform = nsh_updater::platform();
    let offer = signed_offer(&config, "1.0.1", &config.id, &platform, b"archive")
        .unwrap()
        .unwrap();
    assert_eq!(offer.version, "1.0.1");
    assert_eq!(offer.url, "https://updates.example.test/Application.tar.gz");
    assert!(
        signed_offer(&config, "0.9.0", &config.id, &platform, b"archive")
            .unwrap()
            .is_none()
    );
    assert!(
        signed_offer(&config, "1.0.0", &config.id, &platform, b"archive")
            .unwrap()
            .is_none()
    );
    assert!(
        signed_offer(&config, "2.0.0", &config.id, "another-platform", b"archive")
            .unwrap()
            .is_none()
    );
    assert_eq!(
        signed_offer(&config, "2.0.0", "another.app", &platform, b"archive")
            .unwrap_err()
            .code(),
        ErrorCode::Verification
    );
    let bytes =
        serde_json::to_vec(&json!({"id": config.id, "version":"2.0.0", "platforms": {}})).unwrap();
    let signature = nsh_updater::sign(SECRET, &bytes).unwrap();
    let mut changed = bytes.clone();
    changed.push(b' ');
    assert!(
        config
            .check(&changed, Some(signature.as_bytes()), &platform)
            .is_err()
    );
    assert!(config.check(&bytes, None, &platform).is_err());
}

#[test]
fn unsigned_and_code_only_updates_are_not_admitted() {
    let mut config = Config::parse(&configuration("1.0.0")).unwrap();
    config.public_key = None;
    assert_eq!(
        validate_config(&config).unwrap_err().code(),
        ErrorCode::Configuration
    );
    config.public_key = Some(PUBLIC.into());
    config.packages = Some(nsh_updater::Packages::default());
    assert_eq!(
        validate_config(&config).unwrap_err().code(),
        ErrorCode::Configuration
    );
    let mut offered = Available::default();
    assert!(archive_requirements(&offered).is_err());
    offered.sha256 = Some(nsh_updater::sha256(b"data"));
    offered.size = Some(MAX_ARCHIVE + 1);
    assert!(archive_requirements(&offered).is_err());
    offered.size = Some(0);
    assert!(archive_requirements(&offered).is_err());
}

#[test]
fn a_package_without_update_configuration_creates_no_cache_or_worker() {
    let temporary = Temporary::new();
    let cache = temporary.0.join("cache");
    let executable = temporary.0.join("development-host");
    assert!(
        Updater::from_installed(&executable, &cache)
            .unwrap()
            .is_none()
    );
    assert!(!cache.exists());
}

#[test]
fn large_archives_stream_and_verify_without_a_whole_body_buffer() {
    struct BoundedReader(Cursor<Vec<u8>>);
    impl Read for BoundedReader {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            assert!(buffer.len() <= 64 << 10);
            self.0.read(buffer)
        }
    }
    let body: Vec<_> = (0..(4 << 20)).map(|index| (index % 251) as u8).collect();
    let mut written = Vec::new();
    let mut progress = Vec::new();
    stream_archive(
        BoundedReader(Cursor::new(body.clone())),
        &mut written,
        &nsh_updater::sha256(&body),
        body.len() as u64,
        &AtomicU64::new(0),
        0,
        |received| progress.push(received),
    )
    .unwrap();
    assert_eq!(written, body);
    assert_eq!(progress.first(), Some(&0));
    assert_eq!(progress.last(), Some(&(body.len() as u64)));
}

#[test]
fn interrupted_corrupt_oversized_and_cancelled_downloads_leave_no_archive() {
    let temporary = Temporary::new();
    struct Interrupted;
    impl Read for Interrupted {
        fn read(&mut self, _: &mut [u8]) -> std::io::Result<usize> {
            Err(std::io::Error::new(
                std::io::ErrorKind::ConnectionReset,
                "interrupted fixture",
            ))
        }
    }
    let epoch = AtomicU64::new(0);
    for (body, expected_size, expected_code) in [
        (&b"abc"[..], 4, ErrorCode::Verification),
        (&b"abcde"[..], 4, ErrorCode::Verification),
        (&b"xxxx"[..], 4, ErrorCode::Verification),
    ] {
        let path = temporary.0.join("partial");
        {
            let archive = Archive(path.clone());
            let file = private_file(&archive.0).unwrap();
            let error = stream_archive(
                Cursor::new(body),
                file,
                &nsh_updater::sha256(b"data"),
                expected_size,
                &epoch,
                0,
                |_| {},
            )
            .unwrap_err();
            assert_eq!(error.code(), expected_code);
        }
        assert!(!path.exists());
    }
    assert_eq!(
        stream_archive(
            Interrupted,
            std::io::sink(),
            &nsh_updater::sha256(b"data"),
            4,
            &epoch,
            0,
            |_| {}
        )
        .unwrap_err()
        .code(),
        ErrorCode::Transport
    );
    struct Cancelling<'a>(&'a AtomicU64);
    impl Read for Cancelling<'_> {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            buffer[0] = 1;
            self.0.fetch_add(1, Ordering::Release);
            Ok(1)
        }
    }
    let mut written = Vec::new();
    assert_eq!(
        stream_archive(
            Cancelling(&epoch),
            &mut written,
            &nsh_updater::sha256(&[1]),
            1,
            &epoch,
            0,
            |_| {}
        )
        .unwrap_err()
        .code(),
        ErrorCode::Cancelled
    );
    assert!(written.is_empty());
}

#[test]
fn cancellation_during_a_timed_out_read_removes_the_partial_archive() {
    struct TimeoutAfterCancel<'a> {
        epoch: &'a AtomicU64,
        started: bool,
    }
    impl Read for TimeoutAfterCancel<'_> {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            if !self.started {
                self.started = true;
                buffer[0] = b'd';
                return Ok(1);
            }
            self.epoch.fetch_add(1, Ordering::Release);
            Err(std::io::Error::new(
                std::io::ErrorKind::TimedOut,
                "cancelled while waiting for the next chunk",
            ))
        }
    }
    let temporary = Temporary::new();
    let path = temporary.0.join("cancelled.partial");
    let epoch = AtomicU64::new(0);
    {
        let archive = Archive(path.clone());
        let file = private_file(&archive.0).unwrap();
        let error = stream_archive(
            TimeoutAfterCancel {
                epoch: &epoch,
                started: false,
            },
            file,
            &nsh_updater::sha256(b"data"),
            4,
            &epoch,
            0,
            |_| {},
        )
        .unwrap_err();
        assert_eq!(error.code(), ErrorCode::Cancelled);
        assert_eq!(fs::metadata(&path).unwrap().len(), 1);
    }
    assert!(!path.exists());
}

#[cfg(unix)]
fn build_native_package(parent: &Path, name: &str, version: u32) -> (PathBuf, PathBuf, PathBuf) {
    let root = parent.join(name);
    let (executable, resources, library) = if cfg!(target_os = "macos") {
        (
            root.join("Contents/MacOS/Application"),
            root.join("Contents/Resources/nsh"),
            root.join("Contents/Resources/lui/liblui_app.dylib"),
        )
    } else {
        (
            root.join("Application"),
            root.join("nsh"),
            root.join("lui/liblui_app.so"),
        )
    };
    fs::create_dir_all(executable.parent().unwrap()).unwrap();
    fs::create_dir_all(resources.join("assets")).unwrap();
    fs::create_dir_all(library.parent().unwrap()).unwrap();
    let source = parent.join(format!("fixture-{version}.c"));
    fs::write(
        &source,
        format!("int fixture_version(void) {{ return {version}; }}\n"),
    )
    .unwrap();
    let mut compiler = Command::new("cc");
    if cfg!(target_os = "macos") {
        compiler.arg("-dynamiclib");
    } else {
        compiler.args(["-shared", "-fPIC"]);
    }
    assert!(
        compiler
            .arg(&source)
            .arg("-o")
            .arg(&library)
            .status()
            .unwrap()
            .success()
    );
    fs::write(&source, format!("#include <dlfcn.h>\n#include <stdio.h>\nint main(int argc, char **argv) {{ if (argc != 2) return 1; void *handle = dlopen(argv[1], RTLD_NOW); if (!handle) return 2; int (*version)(void) = dlsym(handle, \"fixture_version\"); if (!version || version() != {version}) return 3; printf(\"{version}.0.0\"); return 0; }}\n")).unwrap();
    assert!(
        Command::new("cc")
            .arg(&source)
            .arg("-ldl")
            .arg("-o")
            .arg(&executable)
            .status()
            .unwrap()
            .success()
    );
    fs::write(
        resources.join("app.json"),
        json!({"id":"com.logseq.update-fixture", "version": format!("{version}.0.0")}).to_string(),
    )
    .unwrap();
    fs::write(
        resources.join("assets/nsh-updater.json"),
        configuration(&format!("{version}.0.0")),
    )
    .unwrap();
    if cfg!(target_os = "macos") {
        fs::write(root.join("Contents/Info.plist"), "<?xml version=\"1.0\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>Application</string><key>CFBundleIdentifier</key><string>com.logseq.update-fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>").unwrap();
        for code in [&library, &executable, &root] {
            assert!(
                Command::new("codesign")
                    .args(["--force", "--sign", "-", "--timestamp=none"])
                    .arg(code)
                    .status()
                    .unwrap()
                    .success()
            );
        }
    }
    (root, executable, library)
}

#[cfg(unix)]
#[test]
fn native_signed_fixture_replaces_both_halves_and_restarts_at_the_new_version() {
    let temporary = Temporary::new();
    let name = if cfg!(target_os = "macos") {
        "Application.app"
    } else {
        "Application"
    };
    let (installed, executable, library) = build_native_package(&temporary.0, name, 1);
    let bootstrap = Updater::from_installed(&executable, &temporary.0.join("bootstrap-cache"))
        .unwrap()
        .expect("the installed signed configuration was not discovered");
    assert_eq!(*bootstrap.progress().borrow(), Progress::Idle);
    drop(bootstrap);
    let built = temporary.0.join("new");
    fs::create_dir(&built).unwrap();
    let (new, _, _) = build_native_package(&built, name, 2);
    let archive = temporary.0.join("application.tar.gz");
    assert!(
        Command::new("tar")
            .arg("-czf")
            .arg(&archive)
            .arg("-C")
            .arg(&built)
            .arg(new.file_name().unwrap())
            .status()
            .unwrap()
            .success()
    );
    let config_bytes = configuration("1.0.0");
    let config = Config::parse(&config_bytes).unwrap();
    let installation = Installation::of(&executable, &config.id, &config_bytes).unwrap();
    let (progress, _) = watch::channel(Progress::Idle);
    let owner = NEXT_OWNER.fetch_add(1, Ordering::Relaxed);
    let cache = Cache::new(&temporary.0.join("cache"), &executable, owner).unwrap();
    let mut worker = Worker {
        owner,
        config,
        installation,
        cache,
        agent: ureq::Agent::new_with_defaults(),
        epoch: Arc::new(AtomicU64::new(0)),
        progress,
        latest: None,
        ready: None,
        next_ticket: 1,
    };
    let before = Command::new(&executable)
        .arg(&library)
        .current_dir(&temporary.0)
        .output()
        .unwrap();
    assert!(before.status.success());
    assert_eq!(before.stdout, b"1.0.0");
    let bytes = fs::read(&archive).unwrap();
    let available = signed_offer(
        &worker.config,
        "2.0.0",
        &worker.config.id,
        &nsh_updater::platform(),
        &bytes,
    )
    .unwrap()
    .unwrap();
    worker.latest = Some(Offer {
        owner,
        ticket: 1,
        available,
        can_install: true,
    });
    assert_eq!(
        worker.current(owner + 1, 1).unwrap_err().code(),
        ErrorCode::Stale
    );
    assert_eq!(
        worker.current(owner, 0).unwrap_err().code(),
        ErrorCode::Stale
    );
    let cached = worker.cache.0.join("application.download");
    fs::write(&cached, b"corrupt").unwrap();
    worker.ready = Some(Archive(cached.clone()));
    assert_eq!(
        worker
            .install(0, Downloaded { owner, ticket: 1 })
            .unwrap_err()
            .code(),
        ErrorCode::Verification
    );
    assert!(installed.exists());
    assert_eq!(
        Command::new(&executable)
            .arg(&library)
            .output()
            .unwrap()
            .stdout,
        b"1.0.0"
    );
    fs::copy(&archive, &cached).unwrap();
    let (reply, caller) = oneshot::channel();
    drop(caller);
    worker.handle(super::Command::Install {
        epoch: 0,
        downloaded: Downloaded { owner, ticket: 1 },
        reply,
    });
    assert_eq!(
        Command::new(&executable)
            .arg(&library)
            .output()
            .unwrap()
            .stdout,
        b"1.0.0",
        "an install whose caller was cancelled while queued replaced the app"
    );
    assert!(worker.ready.is_some());
    worker.install(0, Downloaded { owner, ticket: 1 }).unwrap();
    assert_eq!(*worker.progress.borrow(), Progress::Installed);
    let after = Command::new(&executable)
        .arg(&library)
        .current_dir(&temporary.0)
        .output()
        .unwrap();
    assert!(after.status.success());
    assert_eq!(after.stdout, b"2.0.0");
    assert!(worker.ready.is_none());
    assert!(worker.latest.is_none());
    assert!(!cached.exists());
    super::packaged_tests::qualify_from_environment();
}
