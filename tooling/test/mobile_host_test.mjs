import assert from "node:assert/strict";
import {access, readFile} from "node:fs/promises";
import test from "node:test";

const root = new URL("../../", import.meta.url);

async function source(path) {
  return readFile(new URL(path, root), "utf8");
}

test("mobile OCaml toolchains use the official compiler without cross switches", async () => {
  const ios = await source("tooling/mobile/bootstrap_ios_ocaml.sh");
  const android = await source("tooling/mobile/bootstrap_android_ocaml.sh");

  for (const script of [ios, android]) {
    assert.match(script, /https:\/\/github\.com\/ocaml\/ocaml\.git/);
    assert.match(script, /make crossopt/);
    assert.match(script, /make installcross/);
    assert.doesNotMatch(script, /opam switch|opam-cross|cross-ios|cross-android/);
    assert.match(script, /opam_root\/lg-ocaml-toolchains/);
    assert.match(script, /LG_OCAML_TOOLCHAIN_ROOT/);
    assert.match(script, /version_root\/host/);
    assert.match(script, /version_root\/targets/);
  }
});

test("normal mobile builds never bootstrap or clone a toolchain", async () => {
  const ios = await source("tooling/mobile/build_components_ios_simulator.sh");
  const android = await source("tooling/mobile/build_components_android.sh");

  for (const script of [ios, android]) {
    assert.doesNotMatch(script, /^\s*(?:"?\$repo_root\/tooling\/mobile\/)?bootstrap_.*ocaml\.sh/m);
    assert.doesNotMatch(script, /git clone/);
    assert.match(script, /LG_OCAML_TOOLCHAIN_ROOT/);
  }
});

test("Android scripts ignore incomplete SDK manager NDK directories", async () => {
  const bootstrap = await source("tooling/mobile/bootstrap_android_ocaml.sh");
  const build = await source("tooling/mobile/build_components_android.sh");

  for (const script of [bootstrap, build]) {
    assert.match(
      script,
      /\[\[ -x \$candidate\/toolchains\/llvm\/prebuilt\/\$ndk_host\/bin\/clang \]\]/,
    );
    assert.doesNotMatch(script, /\[\[ -d \$candidate \]\] && ndk_root=\$candidate/);
  }
});

test("Android Gallery packages the OCaml runtime as a Flutter jniLib", async () => {
  const build = await source("tooling/mobile/build_components_android.sh");
  const main = await source("examples/components/flutter/lib/main.dart");

  assert.match(
    build,
    /examples\/components\/flutter\/android\/app\/src\/main\/jniLibs\/\$android_abi\/liblui_components\.so/,
  );
  assert.match(main, /Platform\.isAndroid/);
  assert.match(main, /liblui_components\.so/);
  await access(new URL("examples/components/flutter/android/app/build.gradle.kts", root));
});

test("Apple Gallery is a SwiftUI host linked to the retained Apple backend", async () => {
  const build = await source("tooling/mobile/build_components_ios_simulator.sh");
  const objectBuild = await source("tooling/mobile/build_gallery_ocaml_object.sh");
  const packageManifest = await source("examples/components/ios-swiftui/Package.swift");
  const main = await source("examples/components/ios-swiftui/Sources/LUIComponentsApp/LUIComponentsApp.swift");

  assert.match(build, /arm64-apple-ios\$\{deployment_target\}-simulator/);
  assert.match(build, /build_gallery_ocaml_object\.sh/);
  assert.match(objectBuild, /gallery_bridge_complete\.o/);
  assert.match(packageManifest, /LUIAppleBackend/);
  assert.match(main, /import SwiftUI/);
  assert.match(main, /LUIAppleBackend/);
  assert.match(main, /LUISwiftUIRoot/);
});

test("Flutter Gallery derives adaptive one-page navigation from retained sections", async () => {
  const main = await source("examples/components/flutter/lib/main.dart");

  assert.match(main, /rootSections/);
  assert.match(main, /NavigationRail/);
  assert.match(main, /NavigationDrawer/);
  assert.doesNotMatch(main, /widget\(node: _bridge\.rootNode\)/);
});

test("Makefile exposes explicit mobile Gallery build targets", async () => {
  const makefile = await source("Makefile");

  assert.match(makefile, /build-components-ios-simulator:/);
  assert.match(makefile, /test-components-ios-e2e:/);
  assert.match(makefile, /build-components-android:/);
});

test("iOS Gallery has a real interaction E2E flow", async () => {
  const flow = await source(".maestro/ios-components-interactions.yaml");
  const runner = await source("tooling/mobile/test_components_ios_e2e.sh");

  assert.match(flow, /tapOn: "Toggle disabled"/);
  assert.match(flow, /tapOn: "Open dialog"/);
  assert.match(flow, /inputText: "LUI iOS"/);
  assert.match(flow, /inputText: "中文输入"/);
  assert.match(flow, /checked: true/);
  assert.match(flow, /selected: true/);
  for (const page of ["Checkbox", "Switch", "Toggle", "RadioGroup", "Slider"]) {
    assert.match(flow, new RegExp(`id: "component-row-${page}"`));
  }
  assert.doesNotMatch(flow, /Checkbox and Switch|Toggle, RadioGroup, and Slider/);
  assert.match(runner, /build_components_ios_simulator\.sh/);
  assert.match(runner, /maestro.*--device/s);
  assert.match(runner, /simctl io.*screenshot/s);
});

test("iOS Gallery uses an adaptive Apple-native shell", async () => {
  const gallery = await source("examples/components/lg/components/gallery.cljc");
  const main = await source("examples/components/ios-swiftui/Sources/LUIComponentsApp/LUIComponentsApp.swift");

  assert.doesNotMatch(gallery, /\[:table \{:width 520\}/);
  assert.match(gallery, /\[:table \{[^}]*:max-width 520/);
  assert.match(main, /NavigationSplitView/);
  assert.match(main, /systemGroupedBackground/);
  assert.match(main, /navigationTitle\("Components"\)/);
  assert.match(main, /accessibilityIdentifier\("component-row-\\\(section\.title\)"\)/);
  assert.match(main, /LUISwiftUIRoot\(backend: host\.backend, rootID: section\.id\)/);
  assert.doesNotMatch(main, /section\.nodeIDs/);
});

test("iOS Gallery E2E targets component rows by stable identifiers", async () => {
  const flow = await source(".maestro/ios-components-interactions.yaml");

  assert.match(flow, /id: "component-row-TextField"/);
  assert.match(flow, /centerElement: true/);
  assert.match(flow, /id: "component-row-Dialog"[\s\S]*swipe:/);
  assert.match(flow, /id: "component-row-TextField"[\s\S]*tapOn:\n\s+id: "component-row-TextField"/);
  assert.doesNotMatch(flow, /- tapOn: "TextField"/);
});
