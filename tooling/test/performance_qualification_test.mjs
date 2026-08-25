import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const repoRoot = new URL("../../", import.meta.url);

async function source(path) {
  return readFile(new URL(path, repoRoot), "utf8");
}

test("runtime performance qualification has explicit sustained-work budgets", async () => {
  const makefile = await source("Makefile");
  const benchmark = await source("test/lui/benchmark_test.cljc");
  const runner = await source("tooling/performance/qualify_runtime.sh");

  assert.match(makefile, /test-performance:/);
  assert.match(benchmark, /benchmark-10k-sustained-local-mutations/);
  assert.match(
    benchmark,
    /"LUI_PERF" "sustained_local_mutations_10k_ms"/,
  );
  assert.match(runner, /lui\.benchmark-test/);
  assert.match(runner, /LUI_PERF_TYPING_10K_60_MS_MAX/);
  assert.match(runner, /LUI_PERF_SUSTAINED_MUTATIONS_10K_MS_MAX/);
  assert.match(runner, /check_budget sustained_local_mutations_10k_ms/);
});
