.PHONY: test test-schema generate-component-schema generate-json-view test-ocaml test-apple test-nsh test-nsh-integration build-web-css test-web-visual update-web-visual-baselines

CARGO ?= cargo

test-web-visual:
	node tooling/capture_web_simulator_baselines.mjs

update-web-visual-baselines:
	LUI_UPDATE_VISUAL_BASELINES=1 node tooling/capture_web_simulator_baselines.mjs

test: test-schema test-ocaml

test-schema:
	node --test tooling/test/*.mjs

generate-component-schema:
	node tooling/generate_component_schema.mjs
	opam exec -- dune build src/lui.cmxa
	python3 tooling/generate_nsh_contract.py

generate-json-view:
	python3 tools/gen_json_view.py

test-ocaml:
	# Run frame-budget tests without competing Dune jobs.
	opam exec -- dune build --action-stderr-on-success=must-be-empty @runtest -j 1

test-apple:
	# AppKit focus and field editors are process-global; .serialized only isolates one suite.
	swift test --no-parallel

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check

test-nsh:
	python3 tooling/generate_nsh_contract.py --check
	python3 tooling/nsh_support_inventory.py --check
	python3 -m unittest discover -s tooling/test -p 'test_nsh_*.py'
	$(CARGO) fmt --manifest-path platform/nsh/Cargo.toml --check
	$(CARGO) clippy --locked --manifest-path platform/nsh/Cargo.toml --all-targets -- -D warnings
	$(CARGO) test --locked --manifest-path platform/nsh/Cargo.toml

test-nsh-integration:
	$(CARGO) test --locked --manifest-path platform/nsh/Cargo.toml --test ocaml_todos --test runtime_protocol --test ocaml_virtual --test ocaml_clock --test ocaml_image --test public_list_seam
