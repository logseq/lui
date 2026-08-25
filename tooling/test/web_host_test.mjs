import assert from "node:assert/strict";
import {mkdtemp, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";
import test from "node:test";

import {
  createStaticServer,
  defaultHost,
  defaultPort,
} from "../serve_web.mjs";

test("Gallery Web defaults to a LAN-accessible Node host", () => {
  assert.equal(defaultHost, "0.0.0.0");
  assert.equal(defaultPort, 8765);
});

test("make serve-web uses the checked-in Node host", async () => {
  const makefile = await readFile(new URL("../../Makefile", import.meta.url), "utf8");

  assert.match(makefile, /serve-web: build-web\n\tnode tooling\/serve_web\.mjs/);
  assert.doesNotMatch(makefile, /python.*http\.server/);
});

test("Gallery Web derives a sidebar and one active page from the retained root", async () => {
  const main = await readFile(
    new URL("../../examples/components/web/lg/components/web_main.cljc", import.meta.url),
    "utf8",
  );

  assert.match(main, /web\/root-sections/);
  assert.match(main, /lui-gallery-sidebar/);
  assert.match(main, /lui-gallery-content/);
  assert.doesNotMatch(main, /web\/mount! renderer \(driver\/root-node application\) host/);
});

test("Gallery Web Node host serves static files", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "lui-web-host-"));
  await writeFile(path.join(root, "index.html"), "<h1>LUI Gallery</h1>");

  const server = createStaticServer(root);

  try {
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });

    const {port} = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/index.html`);

    assert.equal(response.status, 200);
    assert.equal(await response.text(), "<h1>LUI Gallery</h1>");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  }
});
