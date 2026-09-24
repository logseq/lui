.PHONY: test test-schema generate-component-schema generate-json-view test-ocaml test-apple build-web-css

test: test-schema test-ocaml

test-schema:
	node --test tooling/test/*.mjs

generate-component-schema:
	node tooling/generate_component_schema.mjs

generate-json-view:
	python3 tools/gen_json_view.py

test-ocaml:
	opam exec -- dune build --action-stderr-on-success=must-be-empty @runtest

test-apple:
	swift test

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check
