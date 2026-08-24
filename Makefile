.PHONY: test test-lg test-apple test-flutter build-apple-app build-web build-web-css serve-web

test: test-lg test-apple test-flutter build-web

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

build-apple-app:
	sh examples/todos/macos-appkit/build-app.sh

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check

build-web: build-web-css
	opam exec -- dune build @web -j 1

serve-web: build-web
	python3 -m http.server 8765
