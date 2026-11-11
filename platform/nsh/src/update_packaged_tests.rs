//! Optional actual-package stage of the always-active native updater fixture.
use super::*;
use serde_json::{Value, json};

fn file_hash(path: &Path) -> String {
    nsh_updater::sha256(&fs::read(path).unwrap())
}

pub(super) fn qualify_from_environment() {
    let Some(specification) = std::env::var_os("LUI_NSH_PACKAGED_UPGRADE_SPEC") else {
        return;
    };
    let specification: Value = serde_json::from_slice(&fs::read(specification).unwrap()).unwrap();
    let path = |name: &str| PathBuf::from(specification[name].as_str().unwrap());
    let executable = path("executable");
    let library = path("library");
    let archive = path("archive");
    let configuration = installed_configuration(&executable)
        .unwrap()
        .expect("N1 has no installed update configuration");
    let config = Config::parse(&configuration).unwrap();
    assert_eq!(config.id, "com.logseq.lui.upgrade-fixture");
    assert_eq!(config.version, "1.0.0");
    assert_eq!(
        config.public_key.as_deref(),
        Some("iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w=")
    );
    let manifest = fs::read(path("manifest")).unwrap();
    let signature = fs::read(path("signature")).unwrap();
    let mut tampered = manifest.clone();
    tampered.push(b' ');
    assert!(
        config
            .check(&tampered, Some(&signature), &nsh_updater::platform())
            .is_err()
    );
    let available = config
        .check(&manifest, Some(&signature), &nsh_updater::platform())
        .unwrap()
        .expect("authenticated N2 was not newer than N1");
    assert_eq!(available.version, "2.0.0");
    let owner = NEXT_OWNER.fetch_add(1, Ordering::Relaxed);
    let installation = Installation::of(&executable, &config.id, &configuration).unwrap();
    let cache = Cache::new(&path("cache"), &executable, owner).unwrap();
    let (progress, _) = watch::channel(Progress::Idle);
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
    let (hash, size) = archive_requirements(&available).unwrap();
    worker.latest = Some(Offer {
        owner,
        ticket: 1,
        available,
        can_install: true,
    });
    let binary_before = file_hash(&executable);
    let library_before = file_hash(&library);
    let cached = worker.cache.0.join("application.download");
    {
        let staged = Archive(cached.clone());
        let file = private_file(&staged.0).unwrap();
        stream_archive(
            File::open(&archive).unwrap(),
            file,
            &hash,
            size,
            &worker.epoch,
            0,
            |_| {},
        )
        .unwrap();
        worker.ready = Some(staged);
    }
    // Even a previously verified cache is rechecked before replacing either half.
    OpenOptions::new()
        .append(true)
        .open(&cached)
        .unwrap()
        .write_all(b"corruption")
        .unwrap();
    assert_eq!(
        worker
            .install(0, Downloaded { owner, ticket: 1 })
            .unwrap_err()
            .code(),
        ErrorCode::Verification
    );
    assert_eq!(file_hash(&executable), binary_before);
    assert_eq!(file_hash(&library), library_before);
    worker.ready = None;
    let staged = Archive(cached.clone());
    stream_archive(
        File::open(&archive).unwrap(),
        private_file(&staged.0).unwrap(),
        &hash,
        size,
        &worker.epoch,
        0,
        |_| {},
    )
    .unwrap();
    worker.ready = Some(staged);
    worker.install(0, Downloaded { owner, ticket: 1 }).unwrap();
    let binary_after = file_hash(&executable);
    let library_after = file_hash(&library);
    assert_ne!(binary_after, binary_before);
    assert_ne!(library_after, library_before);
    assert_eq!(
        binary_after,
        specification["expectedBinarySha256"].as_str().unwrap()
    );
    assert_eq!(
        library_after,
        specification["expectedLibrarySha256"].as_str().unwrap()
    );
    fs::write(
        path("result"),
        serde_json::to_vec_pretty(&json!({
            "qualified": true, "version": "2.0.0", "manifestAuthenticated": true,
            "tamperedManifestRejected": true, "corruptCacheRejected": true,
            "binarySha256": binary_after, "librarySha256": library_after,
            "restartBoundary": "external driver closes N1 and launches installed N2"
        }))
        .unwrap(),
    )
    .unwrap();
}
