//! Native commits and real measurements must not depend on display-link ticks.
use super::wait_for_commit;
use nsh_core::{ApproxTextEngine, MountBatch, prelude::*};
use nsh_engine::{Engine, EngineConfig, MountSink, Root};
use nsh_testing::Screen;
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
        mpsc,
    },
    time::{Duration, Instant},
};

#[component]
fn CommittedMeasurement() -> impl IntoElement {
    let reference = element_ref();
    let result = signal(SharedString::from("waiting for commit"));
    spawn(async move {
        wait_for_commit().await.unwrap();
        assert!(
            reference.node().is_some(),
            "the creating commit must mount the ref"
        );
        let measured = reference
            .measure()
            .await
            .expect("a real native measurement");
        assert_eq!(measured.frame.size, Size::new(px(320.0), px(180.0)));
        result.set("measured without a display frame".into());
    });
    view()
        .w(px(320.0))
        .h(px(180.0))
        .element_ref(&reference)
        .child(text(result))
}

struct NoDisplayFrames {
    batches: mpsc::Sender<MountBatch>,
    requests: Arc<AtomicUsize>,
    errors: Arc<Mutex<Vec<String>>>,
}
impl MountSink for NoDisplayFrames {
    fn submit(&self, batch: MountBatch) {
        let _ = self.batches.send(batch);
    }
    fn request_frame(&self) {
        // Model a locked native screen: deliberately do not call control.frame().
        self.requests.fetch_add(1, Ordering::SeqCst);
    }
    fn report_error(&self, error: &str) {
        self.errors.lock().unwrap().push(error.to_owned());
    }
}

#[test]
fn commit_barrier_and_native_measurement_complete_without_display_frames() {
    let (batches, receiver) = mpsc::channel();
    let requests = Arc::new(AtomicUsize::new(0));
    let errors = Arc::new(Mutex::new(Vec::new()));
    let engine = Engine::start(
        EngineConfig::new(Root::of::<CommittedMeasurement>()),
        || ApproxTextEngine,
        NoDisplayFrames {
            batches,
            requests: requests.clone(),
            errors: errors.clone(),
        },
    )
    .unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut screen = Screen::default();
    while !screen.shows("measured without a display frame") {
        let batch = receiver
            .recv_timeout(deadline.saturating_duration_since(Instant::now()))
            .unwrap_or_else(|error| {
                panic!(
                    "native commit stalled without display ticks: {error}; errors={:?}",
                    errors.lock().unwrap()
                )
            });
        screen.apply(&batch);
    }
    assert!(errors.lock().unwrap().is_empty());
    assert_eq!(requests.load(Ordering::SeqCst), 0);
    drop(engine);
}
