.PHONY: test test-lg test-apple test-flutter build-apple-app build-web build-web-css serve-web

test: test-lg test-apple test-flutter build-web

test-lg:
	opam exec -- dune runtest

test-apple:
	swift test --package-path platform/apple
	LUI_APPLE_LIBRARY="$(CURDIR)/platform/apple/.build/debug/libLUIAppleBackend.dylib" \
		opam exec -- dune build @apple-bridge-test

test-flutter:
	opam exec -- dune build examples/todos/native/liblui_todos.dylib
	cd platform/flutter && flutter analyze
	cd platform/flutter && flutter test \
		--dart-define=LUI_NATIVE_LIBRARY="$(CURDIR)/_build/default/examples/todos/native/liblui_todos.dylib"
	cd examples/todos/flutter && flutter analyze
	cd examples/todos/flutter && flutter test \
		--dart-define=LUI_NATIVE_LIBRARY="$(CURDIR)/_build/default/examples/todos/native/liblui_todos.dylib"

build-apple-app:
	sh examples/todos/macos-appkit/build-app.sh

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check

build-web: build-web-css
	opam exec -- dune build @web

serve-web: build-web
	python3 -m http.server 8765
