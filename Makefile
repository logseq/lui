.PHONY: test test-schema generate-component-schema generate-json-view test-ocaml test-mygo test-mygo-integration build-web-css test-web-visual update-web-visual-baselines

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
	python3 tooling/generate_mygo_schema.py --export

generate-json-view:
	python3 tools/gen_json_view.py

test-ocaml:
	# Run frame-budget tests without competing Dune jobs.
	opam exec -- dune build --action-stderr-on-success=must-be-empty @runtest -j 1

platform/web/node_modules/.package-lock.json: platform/web/package.json platform/web/package-lock.json
	npm --prefix platform/web ci

build-web-css: platform/web/node_modules/.package-lock.json
	npm --prefix platform/web run check

test-mygo:
	python3 tooling/generate_mygo_schema.py --check
	cd platform/mygo && go test -count=1 -run 'AllocationBudget$$' .
	cd platform/mygo && go test -race ./...

test-mygo-integration:
	./tooling/test_mygo.sh
