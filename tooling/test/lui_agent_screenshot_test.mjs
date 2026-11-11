import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {deflateSync} from "node:zlib";
import {connectTcp, main, plan, step} from "../lui_agent.mjs";

const MIB = 1024 * 1024;
const crcTable = Uint32Array.from({length: 256}, (_, byte) => {
  let crc = byte;
  for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  return crc >>> 0;
});
function chunk(type, data = Buffer.alloc(0)) {
  const body = Buffer.concat([Buffer.from(type), data]);
  let crc = 0xffffffff;
  for (const byte of body) crc = (crc >>> 8) ^ crcTable[(crc ^ byte) & 255];
  const size = Buffer.alloc(4);
  size.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([size, body, checksum]);
}
// A real one-pixel RGBA PNG, including CRCs, zlib scanline and IEND. A large
// ancillary text chunk tests transport size without inventing image pixels.
function png(padding = 0) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    ...(padding ? [chunk("tEXt", Buffer.concat([Buffer.from("Description\0"), Buffer.alloc(padding, 120)]))] : []),
    chunk("IDAT", deflateSync(Buffer.from([0, 255, 0, 0, 255]))),
    chunk("IEND"),
  ]);
}
const SMALL_PNG = png();
function screenshot(bytes = SMALL_PNG, extra = {}) {
  return {ok: true, op: "screenshot", format: "png", width: 1, height: 1, scale: 1, data: bytes.toString("base64"), ...extra};
}
function directory(t) {
  const temporary = mkdtempSync(path.join(os.tmpdir(), "lui-agent-screenshot-"));
  t.after(() => rmSync(temporary, {recursive: true, force: true}));
  return temporary;
}
function streamed(socket, bytes, size) {
  let offset = 0;
  const send = () => {
    if (socket.destroyed) return;
    while (offset < bytes.length) {
      const end = Math.min(bytes.length, offset + size);
      const writable = socket.write(bytes.subarray(offset, end));
      offset = end;
      if (!writable) { socket.once("drain", send); return; }
    }
  };
  send();
}
async function host(t, answer, {chunkSize = 16 * 1024} = {}) {
  const sockets = new Set();
  const requests = [];
  const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
    socket.on("error", () => {});
    socket.setEncoding("utf8");
    let buffered = "";
    socket.on("data", (data) => {
      buffered += data;
      let newline;
      while ((newline = buffered.indexOf("\n")) !== -1) {
        const request = JSON.parse(buffered.slice(0, newline));
        buffered = buffered.slice(newline + 1);
        requests.push(request);
        const reply = answer(request);
        streamed(socket, Buffer.from(`${JSON.stringify(reply)}\n`), chunkSize);
      }
    });
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  t.after(async () => {
    for (const socket of sockets) socket.destroy();
    await new Promise((resolve) => server.close(resolve));
  });
  return {address: `127.0.0.1:${server.address().port}`, requests};
}
const hello = {ok: true, op: "hello", protocol: "lui-agent", version: 1, host: "Native screenshot test"};

test("screenshot plan keeps a quoted destination and requires its path", () => {
  assert.deepEqual(plan('screenshot "captures/native window.png"'), {screenshot: "captures/native window.png"});
  assert.throws(() => plan("screenshot"), /usage: screenshot/);
});

test("screenshot step writes exact PNG bytes and returns only metadata", async (t) => {
  const output = path.join(directory(t), "nested", "native window.png");
  const printed = [];
  const requests = [];
  const reply = screenshot();
  const result = await step({request: async (request) => { requests.push(request); return reply; }}, plan(`screenshot "${output}"`), {print: (value) => printed.push(value)});
  assert.deepEqual(requests, [{op: "screenshot"}]);
  assert.deepEqual(readFileSync(output), SMALL_PNG);
  assert.equal(result.path, path.resolve(output));
  assert.equal(result.width, 1);
  assert.equal(result.height, 1);
  assert.equal(result.format, "png");
  assert.equal(Object.hasOwn(result, "data"), false);
  assert.deepEqual(printed, [result]);
  assert.equal(JSON.stringify(printed).includes(reply.data), false);
});

test("invalid screenshot replies cannot create directories or overwrite output", async (t) => {
  const root = directory(t);
  const badSignature = Buffer.from(SMALL_PNG); badSignature[0] = 0;
  const badChunk = Buffer.from(SMALL_PNG); badChunk.write("IDAT", 12, "ascii");
  const badIHDRLength = Buffer.from(SMALL_PNG); badIHDRLength.writeUInt32BE(12, 8);
  const zeroWidth = Buffer.from(SMALL_PNG); zeroWidth.writeUInt32BE(0, 16);
  const cases = [
    ["unsupported", {ok: false, op: "screenshot", error: "native screenshots unavailable"}, /unavailable/],
    ["format", screenshot(SMALL_PNG, {format: "jpeg"}), /bounded PNG/],
    ["not-string", screenshot(SMALL_PNG, {data: []}), /bounded PNG/],
    ["base64", screenshot(SMALL_PNG, {data: `${SMALL_PNG.toString("base64")}!`}), /invalid PNG/],
    ["padding", screenshot(SMALL_PNG, {data: SMALL_PNG.toString("base64").replace(/=+$/, "")}), /invalid PNG/],
    ["signature", screenshot(badSignature), /invalid PNG/],
    ["chunk", screenshot(badChunk), /invalid PNG/],
    ["ihdr-length", screenshot(badIHDRLength), /invalid PNG/],
    ["truncated-ihdr", screenshot(SMALL_PNG.subarray(0, 24)), /invalid PNG/],
    ["width", screenshot(SMALL_PNG, {width: 2}), /invalid PNG/],
    ["height", screenshot(SMALL_PNG, {height: 2}), /invalid PNG/],
    ["zero", screenshot(zeroWidth, {width: 0}), /invalid PNG/],
    ["fractional", screenshot(SMALL_PNG, {width: 1.5}), /invalid PNG/],
    ["string-dimensions", screenshot(SMALL_PNG, {width: "1"}), /invalid PNG/],
    ["encoded-cap", screenshot(SMALL_PNG, {data: "A".repeat(24 * MIB + 1)}), /bounded PNG/],
  ];
  for (const [name, reply, error] of cases) {
    await t.test(name, async () => {
      const output = path.join(root, name, "rejected.png");
      const printed = [];
      await assert.rejects(step({request: async () => reply}, {screenshot: output}, {print: (value) => printed.push(value)}), error);
      assert.equal(existsSync(path.dirname(output)), false, "validation must precede directory creation");
      assert.deepEqual(printed, []);
    });
  }
});

test("invalid screenshot preserves an existing output file", async (t) => {
  const output = path.join(directory(t), "existing.png");
  writeFileSync(output, SMALL_PNG);
  const printed = [];
  await assert.rejects(step({request: async () => screenshot(SMALL_PNG, {width: 2})}, {screenshot: output}, {print: (value) => printed.push(value)}), /invalid PNG/);
  assert.deepEqual(readFileSync(output), SMALL_PNG);
  assert.deepEqual(printed, []);
});

test("actual chunked TCP screenshot larger than one MiB reaches the file intact", async (t) => {
  const bytes = png(MIB + 31);
  assert.ok(bytes.length > MIB);
  const reply = screenshot(bytes);
  const fixture = await host(t, () => reply, {chunkSize: 7 * 1024});
  const agent = await connectTcp(fixture.address);
  t.after(() => agent.close());
  const output = path.join(directory(t), "large.png");
  const result = await step(agent, {screenshot: output});
  assert.deepEqual(readFileSync(output), bytes);
  assert.equal(result.width, 1);
  assert.equal(Object.hasOwn(result, "data"), false);
  assert.deepEqual(fixture.requests, [{op: "screenshot"}]);
});

test("main writes screenshot metadata without base64 on stdout", async (t) => {
  const reply = screenshot();
  const fixture = await host(t, (request) => request.op === "hello" ? hello : reply);
  const output = path.join(directory(t), "main capture.png");
  let stdout = ""; let stderr = "";
  const code = await main(["--tcp", fixture.address, "--unchecked", "--json", `screenshot "${output}"`], {stdout: {write: (text) => { stdout += text; }}, stderr: {write: (text) => { stderr += text; }}});
  assert.equal(code, 0, stderr);
  const metadata = JSON.parse(stdout);
  assert.equal(metadata.path, output);
  assert.equal(metadata.op, "screenshot");
  assert.equal(Object.hasOwn(metadata, "data"), false);
  assert.equal(stdout.includes(reply.data), false);
  assert.deepEqual(readFileSync(output), SMALL_PNG);
  assert.deepEqual(fixture.requests, [{op: "hello"}, {op: "screenshot"}]);
});

test("main reports unavailable native capture as a failure without a file or success output", async (t) => {
  const fixture = await host(t, (request) => request.op === "hello" ? hello : {ok: false, op: "screenshot", error: "native screenshots unavailable"});
  const output = path.join(directory(t), "not-created", "capture.png");
  let stdout = ""; let stderr = "";
  const code = await main(["--tcp", fixture.address, "--unchecked", `screenshot "${output}"`], {stdout: {write: (text) => { stdout += text; }}, stderr: {write: (text) => { stderr += text; }}});
  assert.equal(code, 1);
  assert.equal(stdout, "");
  assert.match(stderr, /native screenshots unavailable/);
  assert.equal(existsSync(path.dirname(output)), false);
});

test("oversized TCP reply rejects its request without an uncaught transport exception", {timeout: 20_000}, async (t) => {
  const fixture = await host(t, () => ({ok: true, op: "tree", padding: "x".repeat(32 * MIB + 1)}));
  const moduleURL = new URL("../lui_agent.mjs", import.meta.url).href;
  const source = `import {connectTcp} from ${JSON.stringify(moduleURL)};
    const agent = await connectTcp(${JSON.stringify(fixture.address)});
    try { await agent.request({op:"tree"}); process.stdout.write("unexpected acceptance"); process.exitCode=2; }
    catch(error) { process.stdout.write(JSON.stringify({error:error.message})); }
    finally { agent.close(); }`;
  const child = spawn(process.execPath, ["--input-type=module", "-e", source], {stdio: ["ignore", "pipe", "pipe"]});
  t.after(() => { if (child.exitCode === null) child.kill(); });
  let stdout = ""; let stderr = "";
  child.stdout.setEncoding("utf8").on("data", (text) => { stdout += text; });
  child.stderr.setEncoding("utf8").on("data", (text) => { stderr += text; });
  const code = await new Promise((resolve, reject) => { child.once("error", reject); child.once("exit", resolve); });
  assert.equal(code, 0, stderr || stdout);
  assert.match(JSON.parse(stdout).error, /reply line exceeds 32 MiB/);
  assert.equal(stderr, "", "a protocol size rejection must not escape as an uncaught exception");
});
