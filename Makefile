.PHONY: test test-schema generate-component-schema test-lg test-apple test-flutter build-apple-app \
	build-components-flutter-macos test-components-flutter-macos \
	run-components-flutter-macos build-components-ios-simulator \
	build-components-mobile test-components-ios-e2e build-components-android build-web build-web-css \
	test-web-e2e build-web-release serve-web

test: test-schema test-lg test-apple test-flutter build-web

test-schema:
	node --test tooling/test/*.mjs

generate-component-schema:
	node tooling/generate_component_schema.mjs

test-lg:
	opam exec -- dune runtest -j 1

test-apple:
	swift test --package-path platform/apple
	LUI_APPLE_LIBRARY="$(CURDIR)/platform/apple/.build/debug/libLUIAppleBackend.dylib" \
		opam exec -- dune build @apple-bridge-test -j 1

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

build-apple-app:
	sh examples/todos/macos-appkit/build-app.sh

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check

build-web: build-web-css
	opam exec -- dune build @web -j 1

test-web-e2e: build-web
	node --test platform/web/test/overlay.e2e.mjs

build-web-release: build-web
	node tooling/build_web_release.mjs

serve-web: build-web
	node tooling/serve_web.mjs
