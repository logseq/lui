#!/bin/sh
# Rebuilds the committed SPIR-V binaries beside this script.
# Usage: sh shader/build.sh [path-to-glslangValidator]
# The scene and pass shaders are concatenated from their parts —
# common.glsl + a main — so the precompiled units and the units the
# runtime assembler builds (effect pipelines) share one math source.

set -e
cd "$(dirname "$0")"
GLSLANG="${1:-glslangValidator}"

mk() { # $1 output, $2 stage, $3 prelude text, $4... inputs
	out="$1"; stage="$2"; pre="$3"; shift 3
	tmp="/tmp/lui_vk_$out"
	{ printf '%s\n' "$pre"; cat "$@"; } > "$tmp"
	"$GLSLANG" -V -S "$stage" "$tmp" -o "$out" || {
		echo "failed: $out" >&2; exit 1; }
	rm -f "$tmp"
}

mk scene.vert.spv vert '' scene.vert.glsl
mk scene.frag.spv frag '#version 450' common.glsl scene_main.glsl
mk scene_dual.frag.spv frag '#version 450
#define DUAL' common.glsl scene_main.glsl
mk pass.vert.spv vert '' pass.vert.glsl
mk down.frag.spv frag '' down.frag.glsl
mk blur.frag.spv frag '' blur.frag.glsl
echo "built: scene.vert.spv scene.frag.spv scene_dual.frag.spv pass.vert.spv down.frag.spv blur.frag.spv"
