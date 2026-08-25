.PHONY: test test-schema generate-component-schema test-lg test-apple test-flutter build-apple-app \
	build-components-flutter-macos test-components-flutter-macos \
	run-components-flutter-macos build-web build-web-css serve-web

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

build-apple-app:
	sh examples/todos/macos-appkit/build-app.sh

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check

build-web: build-web-css
	opam exec -- dune build @web -j 1

serve-web: build-web
	node tooling/serve_web.mjs
