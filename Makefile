.PHONY: test test-schema generate-component-schema test-lg test-performance test-apple test-apple-uikit-host test-flutter build-apple-app \
	build-components-flutter-macos test-components-flutter-macos \
	run-components-flutter-macos build-components-ios-simulator \
	build-components-mobile test-components-ios-e2e build-components-android build-components-android-release \
	qualify-components-android-release test-components-android-e2e build-web build-web-css \
	test-web-e2e test-web-hot-reload test-web-firefox-e2e test-web-webkit-e2e test-web-visual update-web-visual-baselines fetch-web-references build-web-release serve-web dev-web

test: test-schema test-lg test-apple test-flutter build-web

test-schema:
	node --test tooling/test/*.mjs

generate-component-schema:
	node tooling/generate_component_schema.mjs

test-lg:
	opam exec -- dune runtest -j 1

test-performance:
	tooling/performance/qualify_runtime.sh

test-apple:
	swift test --package-path platform/apple
	LUI_APPLE_LIBRARY="$(CURDIR)/platform/apple/.build/debug/libLUIAppleBackend.dylib" \
		opam exec -- dune build @apple-bridge-test -j 1
	$(MAKE) test-apple-uikit-host

test-apple-uikit-host:
	tooling/mobile/test_uikit_host_contract.sh

test-flutter:
	opam exec -- dune build -j 1 \
		examples/todos/native/liblui_todos.dylib \
		examples/components/native/liblui_components.dylib
	cd platform/flutter && flutter analyze
	cd platform/flutter && flutter test \
		--dart-define=LUI_NATIVE_LIBRARY="$(CURDIR)/_build/default/examples/todos/native/liblui_todos.dylib"
	cd examples/todos/flutter && flutter analyze
	cd examples/todos/flutter && flutter test \
		--dart-define=LUI_NATIVE_LIBRARY="$(CURDIR)/_build/default/examples/todos/native/liblui_todos.dylib"
	cd examples/components/flutter && flutter analyze
	cd examples/components/flutter && flutter test \
		--dart-define=LUI_NATIVE_LIBRARY="$(CURDIR)/_build/default/examples/components/native/liblui_components.dylib"
	$(MAKE) test-components-flutter-macos

build-components-flutter-macos:
	opam exec -- dune build -j 1 \
		examples/components/native/liblui_components.dylib
	cd examples/components/flutter && flutter build macos --debug

test-components-flutter-macos:
	cd examples/components/flutter && sh test/macos_package_test.sh

run-components-flutter-macos: build-components-flutter-macos
	cd examples/components/flutter && flutter run -d macos

build-components-mobile:
	tooling/mobile/build_components_mobile.sh

build-components-ios-simulator:
	tooling/mobile/build_components_ios_simulator.sh

test-components-ios-e2e:
	tooling/mobile/test_components_ios_e2e.sh

build-components-android:
	tooling/mobile/build_components_android.sh
	cd examples/components/flutter && flutter build apk --debug --target-platform android-arm64

build-components-android-release:
	tooling/mobile/build_components_android.sh
	cd examples/components/flutter && flutter build appbundle --release --target-platform android-arm64

qualify-components-android-release:
	tooling/mobile/qualify_components_android_release.sh

test-components-android-e2e:
	tooling/mobile/test_components_android_e2e.sh

build-apple-app:
	sh examples/todos/macos-appkit/build-app.sh

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check

build-web: build-web-css
	opam exec -- dune build @web -j 1

test-web-e2e: build-web
	npm --prefix platform/web exec playwright install chromium
	node --test platform/web/test/overlay.e2e.mjs
	node --test platform/web/test/simulator.e2e.mjs
	node tooling/capture_web_simulator_baselines.mjs

test-web-hot-reload: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web exec playwright install chromium
	node --test tooling/test/web_hot_reload_test.mjs
	node --test platform/web/test/hot-reload.e2e.mjs

test-web-firefox-e2e: build-web
	npm --prefix platform/web exec playwright install firefox
	node --test platform/web/test/firefox.e2e.mjs

test-web-webkit-e2e: build-web
	npm --prefix platform/web exec playwright install webkit
	LUI_WEB_BROWSER=webkit node --test platform/web/test/firefox.e2e.mjs

fetch-web-references:
	node tooling/fetch_web_simulator_references.mjs

test-web-visual: build-web
	npm --prefix platform/web exec playwright install chromium
	node tooling/capture_web_simulator_baselines.mjs

update-web-visual-baselines: build-web
	npm --prefix platform/web exec playwright install chromium
	LUI_UPDATE_VISUAL_BASELINES=1 node tooling/capture_web_simulator_baselines.mjs

build-web-release: build-web
	node tooling/build_web_release.mjs

serve-web: build-web
	node tooling/serve_web.mjs

dev-web: platform/web/node_modules/.package-lock.json
	node tooling/dev_web.mjs
