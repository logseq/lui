# OCaml Web desktop startup

Date: 2026-11-17. Host: macOS arm64. The application is a production build
with Web Inspector disabled, loading the OCaml/Melange Gallery. The native
shell uses OCaml 5.5.1 with `-O3`; the frontend is built with the Dune release
profile and minified with esbuild.

The frontend `app.js` has SHA-256
`0af5d31201ae945eaa772186fc615f518849fa903cf088b535435aff7436eefa`.
The window is 1180×820. Updates are unconfigured during measurement. The host
loads `lui://localhost` through public WKURLSchemeHandler APIs without a TCP
listener.

## Criterion

Measure from creating a new native process to the frontend's `window.load`
event, after the OCaml Gallery has mounted. The host reports through its
existing startup acknowledgement. The timer and marker polling use Python's
monotonic clock, with a 1 ms polling interval. The process is terminated after
each sample. These are observations from an active desktop, not an isolated
performance guarantee or a measured first-paint timestamp. The visible Gallery
was separately checked in the actual WKWebView.

## Warm file-cache startup

Discard one warm-up, then measure eight launches.

| Minimum | Median | Maximum | Samples |
| ---: | ---: | ---: | ---: |
| 287.68 ms | 319.58 ms | 351.97 ms | 8 |

Raw milliseconds: 351.36, 298.36, 351.97, 287.68, 334.25, 293.28, 344.70,
304.91. Launch order and short-term OS activity affect individual samples.

## Cold file-cache startup

Before every launch, execute `/usr/sbin/purge` using macOS administrator
authentication. Its completion is outside the timed interval. Stop the
application before the sequence and retain the existing user profile.

| Minimum | Median | Maximum | Samples |
| ---: | ---: | ---: | ---: |
| 1195.47 ms | 1218.96 ms | 1412.42 ms | 3 |

Raw milliseconds: 1195.47, 1218.96, 1412.42.

This is cold file-cache startup, not first launch after an OS reboot.
Other desktop applications and resident system frameworks remain present.
It does not establish fresh-install, empty-profile or cross-platform startup
performance.

## Native lifecycle checks

The macOS scheme probe loads real module scripts from `lui://localhost`,
invokes the real origin-checked IPC callback and the same native close path
used by Remind Me Later. Three consecutive launches exit successfully, and
the probe checks that newly created WebKit processes terminate after closure.
The independent update-engine suite passes 12 signed-manifest, full/delta,
path-validation, replacement, rollback and constructor-rejection regressions.

No downloaded source tree, signing key, package, recording or screenshot is
included in this report.
