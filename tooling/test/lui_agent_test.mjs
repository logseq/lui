import assert from "node:assert/strict";
import {mkdtempSync, mkdirSync, rmSync, unlinkSync, writeFileSync} from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {listenWs, main, plan, tokens} from "../lui_agent.mjs";
import {checkReceipt, receiptPath, writeReceipt} from "../lui_build_receipt.mjs";

function project() {
  const root = mkdtempSync(path.join(os.tmpdir(), "lui-receipt-"));
  mkdirSync(path.join(root, "src"));
  writeFileSync(path.join(root, "src/view.ml"), "let view = ()\n");
  writeFileSync(path.join(root, "src/model.ml"), "let model = 0\n");
  const artifact = path.join(root, "liblui_app.so");
  writeFileSync(artifact, "binary");
  return {root, artifact, done: () => rmSync(root, {recursive: true, force: true})};
}

test("a receipt refuses a build older than its sources", () => {
  const {root, artifact, done} = project();
  try {
    assert.match(checkReceipt(artifact).message, /no build receipt/);
    writeReceipt({artifact, command: "bash build.sh", inputs: ["src"], root});
    assert.equal(checkReceipt(artifact).fresh, true);

    writeFileSync(path.join(root, "src/view.ml"), "let view = 1\n");
    const edited = checkReceipt(artifact);
    assert.equal(edited.fresh, false);
    assert.deepEqual(edited.changed, ["src/view.ml"]);
    assert.match(edited.message, /build is stale: src\/view\.ml changed since it was built; run bash build\.sh/);

    writeFileSync(path.join(root, "src/view.ml"), "let view = ()\n");
    assert.equal(checkReceipt(artifact).fresh, true, "reverting the edit makes it fresh again");

    writeFileSync(path.join(root, "src/extra.ml"), "\n");
    unlinkSync(path.join(root, "src/model.ml"));
    assert.deepEqual(checkReceipt(artifact).changed, ["src/extra.ml", "src/model.ml"], "added and removed inputs count");

    writeReceipt({artifact, command: "bash build.sh", inputs: ["src"], root});
    writeFileSync(artifact, "rebuilt without a receipt");
    assert.match(checkReceipt(artifact).message, /changed after its receipt was written; run bash build\.sh/);
  } finally {
    done();
  }
});

test("directory artifacts are digested by content", () => {
  const {root, done} = project();
  try {
    const dist = path.join(root, "dist");
    mkdirSync(path.join(dist, "icons"), {recursive: true});
    writeFileSync(path.join(dist, "app.js"), "app");
    writeFileSync(path.join(dist, "icons/a.svg"), "<svg/>");
    writeReceipt({artifact: dist, command: "node build.mjs", inputs: ["src"], root});
    assert.equal(receiptPath(dist), `${dist}.lui-build.json`);
    assert.equal(checkReceipt(dist).fresh, true);
    writeFileSync(path.join(dist, "icons/a.svg"), "<svg></svg>");
    assert.equal(checkReceipt(dist).fresh, false);
  } finally {
    done();
  }
});

test("script lines use the Drive scenario vocabulary", () => {
  assert.deepEqual(tokens(`type kind:text-field "hello world"`), ["type", "kind:text-field", "hello world"]);
  assert.deepEqual(tokens(`press kind:button&text:"Open dialog"`), ["press", "kind:button&text:Open dialog"]);
  assert.deepEqual(plan(`tap "Save"`).request, {op: "press", selector: "Save"});
  assert.deepEqual(plan(`native-press "More"`).request, {op: "native-press", selector: "More"});
  assert.throws(() => plan("native-press"), /usage: native-press/);
  assert.throws(() => plan("native-press More extra"), /usage: native-press/);
  assert.deepEqual(plan(`type id:4 "a b"`).request, {op: "type", selector: "id:4", text: "a b"});
  assert.deepEqual(plan("toggle kind:checkbox true").request, {op: "toggle", selector: "kind:checkbox", value: true});
  assert.deepEqual(plan(`key "cmd+k"`).request, {op: "key", combo: "cmd+k"});
  assert.deepEqual(plan("wait text:Saved 2"), {check: "present", selector: "text:Saved", timeout: 2});
  assert.deepEqual(plan("expect text:Saved"), {check: "present", selector: "text:Saved", timeout: 0});
  assert.equal(plan("# comment"), null);
  assert.throws(() => plan("fly away"), /unknown command: fly/);
  assert.throws(() => plan("value id:3 loud"), /needs a number/);
});

// A host stand-in that answers like the OCaml agent behind a native host.
function fakeHost(answer) {
  const requests = [];
  const server = net.createServer((socket) => {
    socket.setEncoding("utf8");
    let buffered = "";
    socket.on("data", (chunk) => {
      buffered += chunk;
      let newline;
      while ((newline = buffered.indexOf("\n")) !== -1) {
        const request = JSON.parse(buffered.slice(0, newline));
        buffered = buffered.slice(newline + 1);
        requests.push(request);
        socket.write(`${JSON.stringify(answer(request))}\n`);
      }
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () =>
    resolve({address: `127.0.0.1:${server.address().port}`, requests, close: () => server.close()})));
}

function counterHost() {
  let count = 0;
  return fakeHost((request) => {
    switch (request.op) {
      case "hello": return {ok: true, op: "hello", protocol: "lui-agent", version: 1, host: "Fake"};
      case "press":
        if (request.selector === "Boom") {
          return {ok: false, refused: true, op: "press", error: "handler boom", diagnostic: {phase: "agent"}};
        }
        count += 1;
        return {ok: true, op: "press", node: 7};
      case "find": return {ok: true, op: "find", nodes: request.selector === `text:count=${count}` ? [4] : []};
      case "prop": return {ok: true, op: "prop", node: 4, value: `count=${count}`};
      case "dump": return {ok: true, op: "dump", text: `#4 text text="count=${count}"\n`};
      default: return {ok: false, op: request.op, error: `unknown op: ${request.op}`};
    }
  });
}

function capture() {
  const chunks = [];
  return {write: (text) => chunks.push(text), text: () => chunks.join("")};
}

test("the client drives a host and reports every failing line", async () => {
  const host = await counterHost();
  const stdout = capture();
  const stderr = capture();
  try {
    const code = await main(
      ["--tcp", host.address, "--unchecked", `press "+"`, "expect text:count=1", "expect-prop id:4 text count=2",
        "press Boom", "expect-absent text:count=1", "dump"],
      {stdout, stderr},
    );
    assert.equal(code, 1);
    assert.match(stderr.text(), /freshness unchecked/);
    assert.match(stderr.text(), /command 3: prop text on #4 = count=1, want count=2/);
    assert.match(stderr.text(), /command 4: the host refused the call: handler boom \(\{"phase":"agent"\}\)/);
    assert.match(stderr.text(), /command 5: unexpected node present: text:count=1/);
    assert.match(stdout.text(), /#4 text text="count=1"/, "later lines still run");
    assert.deepEqual(host.requests[0], {op: "hello"});
  } finally {
    host.close();
  }
});

test("the client refuses a stale artifact before connecting", async () => {
  const {root, artifact, done} = project();
  const host = await counterHost();
  const stderr = capture();
  try {
    writeReceipt({artifact, command: "bash build.sh", inputs: ["src"], root});
    writeFileSync(path.join(root, "src/view.ml"), "let view = 2\n");
    const code = await main(["--tcp", host.address, "--artifact", artifact, "dump"], {stdout: capture(), stderr});
    assert.equal(code, 3);
    assert.match(stderr.text(), /refusing to drive: .* src\/view\.ml changed since it was built; run bash build\.sh/);
    assert.equal(host.requests.length, 0);
    assert.equal(await main(["--tcp", host.address, "dump"], {stdout: capture(), stderr}), 2, "no artifact and no --unchecked");
  } finally {
    host.close();
    done();
  }
});

test("a page dials the WebSocket listener and answers requests", async () => {
  let page;
  const agent = await listenWs(0, {
    onListening: (port) => {
      page = new WebSocket(`ws://127.0.0.1:${port}`);
      page.onmessage = ({data}) => {
        const request = JSON.parse(data);
        page.send(JSON.stringify({ok: true, op: request.op, echoed: "é".repeat(70_000)}));
      };
    },
  });
  try {
    const reply = await agent.request({op: "hello"});
    assert.equal(reply.op, "hello");
    assert.equal(reply.echoed.length, 70_000, "large frames survive");
  } finally {
    agent.close();
    page.close();
  }
});
