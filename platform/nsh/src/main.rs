//! Runs the LUI application on the operating system's native NSH surface.
#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

#[cfg(target_os = "linux")]
use nsh_platform_linux as platform;
#[cfg(target_os = "macos")]
use nsh_platform_macos as platform;
#[cfg(target_os = "windows")]
use nsh_platform_windows as platform;

fn main() -> impl std::process::Termination {
    platform::run_app(
        platform::AppSource::Rust(platform::Root::of::<lui_nsh::DesktopApp>()),
        platform::AppOptions {
            title: "LUI Desktop".into(),
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            app_id: "com.logseq.lui.desktop".into(),
            size: (1000, 800),
            ..Default::default()
        },
    )
}
