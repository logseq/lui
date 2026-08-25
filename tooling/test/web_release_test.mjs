import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

const root = new URL("../../", import.meta.url);

test("Web release is bundled, minified, and independent of the development import map", async () => {
  const makefile = await readFile(new URL("Makefile", root), "utf8");
  const builder = await readFile(new URL("tooling/build_web_release.mjs", root), "utf8");
  const html = await readFile(
    new URL("examples/components/web/index.release.html", root),
    "utf8",
  );
  const packageJson = JSON.parse(
    await readFile(new URL("platform/web/package.json", root), "utf8"),
  );

  assert.match(makefile, /build-web-release:/);
  assert.match(builder, /bundle: true/);
  assert.match(builder, /minify: true/);
  assert.match(builder, /treeShaking: true/);
  assert.equal(packageJson.devDependencies.esbuild, "0.28.2");
  assert.match(html, /src="\.\/app\.js"/);
  assert.doesNotMatch(html, /importmap|_build\/default/);
});
