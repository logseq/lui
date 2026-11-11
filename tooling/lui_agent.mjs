#!/usr/bin/env node
// One agent client for every LUI host.
//
//   node tooling/lui_agent.mjs --tcp 127.0.0.1:49380 --artifact PATH 'press "Save"' dump
//   node tooling/lui_agent.mjs --ws-listen 49380 --artifact _build/web-release --script flow.agent
//
// Native hosts (NSH, Apple, Android) listen on loopback TCP once opted in;
// a Web page dials the --ws-listen socket from ?lui-agent=ws://127.0.0.1:PORT.
// Both carry the same newline-delimited lui-agent requests and replies,
// answered by the shared OCaml runtime, so one script drives every host.
//
// Before connecting, the artifact's build receipt is checked: a build older
// than its sources is refused with exit code 3 and the rebuild command.
// --unchecked skips the check and says so.
import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import net from "node:net";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {checkReceipt, STALE_EXIT} from "./lui_build_receipt.mjs";

export const USAGE_EXIT = 2;
const MAX_LINE = 1024 * 1024;

// Drive scenario tokenizer: spaces split, quoted spans stay together.
export function tokens(line) {
  const out = [];
  let current = "";
  let started = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (char === " " || char === "\t") {
      if (started) out.push(current);
      current = "";
      started = false;
    } else if (char === "\"" || char === "'") {
      const end = line.indexOf(char, index + 1);
      const stop = end === -1 ? line.length : end;
      current += line.slice(index + 1, stop);
      started = true;
      index = stop;
    } else {
      current += char;
      started = true;
    }
  }
  if (started) out.push(current);
  return out;
}

const GESTURES = new Set(["press", "tap", "long-press", "double-press", "submit", "dismiss", "appear", "change"]);

// One script line -> a plan: {request} for a single round trip, or a
// client-side check built from round trips.
export function plan(line) {
  const words = tokens(line.trim());
  const [command, ...rest] = words;
  const need = (count, shape) => {
    if (rest.length < count) throw new Error(`usage: ${command} ${shape}`);
  };
  if (!command || command.startsWith("#")) return null;
  if (GESTURES.has(command)) {
    need(1, "<selector>");
    return {request: {op: command === "tap" ? "press" : command, selector: rest[0]}};
  }
  switch (command) {
    case "hello":
      return {request: {op: "hello"}};
    case "tree":
    case "dump":
      return {request: rest[0] ? {op: command, selector: rest[0]} : {op: command}};
    case "find":
      need(1, "<selector>");
      return {request: {op: "find", selector: rest[0]}};
    case "prop":
      need(2, "<selector> <name>");
      return {request: {op: "prop", selector: rest[0], name: rest[1]}};
    case "type":
      need(1, "<selector> \"text\"");
      return {request: {op: "type", selector: rest[0], text: rest.slice(1).join(" ")}};
    case "toggle":
      need(2, "<selector> true|false");
      return {request: {op: "toggle", selector: rest[0], value: rest[1] === "true" || rest[1] === "1"}};
    case "value":
      need(2, "<selector> <number>");
      if (!Number.isFinite(Number(rest[1]))) throw new Error(`value needs a number, got ${rest[1]}`);
      return {request: {op: "value", selector: rest[0], value: Number(rest[1])}};
    case "key":
      need(1, "\"combo\"");
      return {request: {op: "key", combo: rest[0]}};
    case "ext":
      need(3, "<selector> <identifier> <name> ['<json fields>']");
      return {request: {op: "ext", selector: rest[0], identifier: rest[1], name: rest[2], fields: rest.slice(3).join(" ") || "{}"}};
    case "expect":
    case "wait":
      need(1, "<selector> [seconds]");
      return {check: "present", selector: rest[0], timeout: Number(rest[1] ?? (command === "wait" ? 5 : 0))};
    case "expect-absent":
      need(1, "<selector>");
      return {check: "absent", selector: rest[0]};
    case "expect-prop":
      need(3, "<selector> <name> <value>");
      return {check: "prop", selector: rest[0], name: rest[1], expected: rest.slice(2).join(" ")};
    case "sleep":
      need(1, "<seconds>");
      return {sleep: Number(rest[0])};
    default:
      throw new Error(`unknown command: ${command}`);
  }
}

// ---------- transports ----------

function lineReader(onLine) {
  let buffered = "";
  return (chunk) => {
    buffered += chunk;
    let newline;
    while ((newline = buffered.indexOf("\n")) !== -1) {
      const line = buffered.slice(0, newline);
      buffered = buffered.slice(newline + 1);
      if (line.trim()) onLine(line);
    }
    if (buffered.length > MAX_LINE) throw new Error("reply line exceeds 1 MiB");
  };
}

const REPLY_TIMEOUT = 10_000;

function session(send, close) {
  const waiting = [];
  let failure = null;
  const agent = {
    receive(line) {
      const next = waiting.shift();
      if (next) next.resolve(line);
    },
    fail(error) {
      failure = error;
      for (const next of waiting.splice(0)) next.reject(error);
    },
    request(object) {
      if (failure) return Promise.reject(failure);
      let timer;
      return new Promise((resolve, reject) => {
        waiting.push({resolve, reject});
        timer = setTimeout(() => {
          agent.fail(new Error(`no reply to ${object.op} within ${REPLY_TIMEOUT} ms`));
          close();
        }, REPLY_TIMEOUT);
        send(JSON.stringify(object));
      }).then((line) => JSON.parse(line)).finally(() => clearTimeout(timer));
    },
    close,
  };
  return agent;
}

export function connectTcp(address) {
  const colon = address.lastIndexOf(":");
  const host = colon > 0 ? address.slice(0, colon) : "127.0.0.1";
  const port = Number(address.slice(colon + 1));
  return new Promise((resolve, reject) => {
    const socket = net.connect({host, port});
    socket.setEncoding("utf8");
    const agent = session((line) => socket.write(`${line}\n`), () => socket.end());
    socket.on("data", lineReader((line) => agent.receive(line)));
    socket.once("connect", () => resolve(agent));
    socket.once("error", (error) => {
      agent.fail(error);
      reject(error);
    });
    socket.once("close", () => agent.fail(new Error(`${address} closed the connection`)));
  });
}

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

function wsFrame(text) {
  const payload = Buffer.from(text, "utf8");
  const length = payload.length;
  const header = length < 126 ? Buffer.from([0x81, length])
    : length < 65536 ? Buffer.from([0x81, 126, length >> 8, length & 255])
      : Buffer.concat([Buffer.from([0x81, 127]), (() => {
        const size = Buffer.alloc(8);
        size.writeBigUInt64BE(BigInt(length));
        return size;
      })()]);
  return Buffer.concat([header, payload]);
}

// Minimal RFC 6455 server for the one page that dials in: masked client text
// frames in, unmasked text frames out; continuation, ping and close handled.
export function listenWs(port, {onListening, timeout = 60_000} = {}) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    const timer = setTimeout(() => {
      server.close();
      reject(new Error(`no page connected to ws://127.0.0.1:${port} within ${timeout} ms`));
    }, timeout);
    server.once("error", reject);
    server.listen(port, "127.0.0.1", () => onListening?.(server.address().port));
    server.once("connection", (socket) => {
      clearTimeout(timer);
      server.close();
      let buffer = Buffer.alloc(0);
      let upgraded = false;
      let fragments = [];
      const agent = session((line) => socket.write(wsFrame(line)), () => socket.end(Buffer.from([0x88, 0])));
      socket.on("data", (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        if (!upgraded) {
          const end = buffer.indexOf("\r\n\r\n");
          if (end === -1) return;
          const head = buffer.subarray(0, end).toString("utf8");
          buffer = buffer.subarray(end + 4);
          const key = /^sec-websocket-key:\s*(.+)$/im.exec(head)?.[1]?.trim();
          if (!key) {
            socket.destroy();
            reject(new Error("the page did not send a WebSocket handshake"));
            return;
          }
          const accept = createHash("sha1").update(key + WS_GUID).digest("base64");
          socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
          upgraded = true;
          resolve(agent);
        }
        while (buffer.length >= 2) {
          const opcode = buffer[0] & 15;
          const final = (buffer[0] & 128) !== 0;
          let length = buffer[1] & 127;
          let offset = 2;
          if (length === 126) {
            if (buffer.length < 4) return;
            length = buffer.readUInt16BE(2);
            offset = 4;
          } else if (length === 127) {
            if (buffer.length < 10) return;
            length = Number(buffer.readBigUInt64BE(2));
            offset = 10;
          }
          const masked = (buffer[1] & 128) !== 0;
          const mask = masked ? buffer.subarray(offset, offset + 4) : null;
          if (masked) offset += 4;
          if (buffer.length < offset + length) return;
          const payload = Buffer.from(buffer.subarray(offset, offset + length));
          buffer = buffer.subarray(offset + length);
          if (mask) for (let index = 0; index < payload.length; index += 1) payload[index] ^= mask[index & 3];
          if (opcode === 8) {
            socket.end();
            return;
          }
          if (opcode === 9) {
            socket.write(Buffer.concat([Buffer.from([0x8a, payload.length]), payload]));
            continue;
          }
          if (opcode === 1 || opcode === 0) {
            fragments.push(payload);
            if (final) {
              const text = Buffer.concat(fragments).toString("utf8");
              fragments = [];
              agent.receive(text);
            }
          }
        }
      });
      socket.once("close", () => agent.fail(new Error("the page closed the agent socket")));
      socket.once("error", (error) => agent.fail(error));
    });
  });
}

// ---------- running ----------

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function describeFailure(reply) {
  if (reply.refused) {
    const diagnostic = reply.diagnostic ? ` (${JSON.stringify(reply.diagnostic)})` : "";
    return `the host refused the call: ${reply.error}${diagnostic}`;
  }
  return reply.error ?? "request failed";
}

async function present(agent, selector) {
  const reply = await agent.request({op: "find", selector});
  if (!reply.ok) throw new Error(describeFailure(reply));
  return reply.nodes.length > 0;
}

const shown = (value) => (typeof value === "string" ? value : JSON.stringify(value));

export async function step(agent, planned, {print = () => {}} = {}) {
  if (planned.sleep !== undefined) return sleep(planned.sleep * 1000);
  if (planned.request) {
    const reply = await agent.request(planned.request);
    if (!reply.ok) throw new Error(describeFailure(reply));
    print(reply);
    return reply;
  }
  if (planned.check === "present") {
    const deadline = Date.now() + planned.timeout * 1000;
    while (!(await present(agent, planned.selector))) {
      if (Date.now() >= deadline) {
        throw new Error(planned.timeout > 0 ? `timed out waiting for: ${planned.selector}` : `expected node: ${planned.selector}`);
      }
      await sleep(50);
    }
    return null;
  }
  if (planned.check === "absent") {
    if (await present(agent, planned.selector)) throw new Error(`unexpected node present: ${planned.selector}`);
    return null;
  }
  const reply = await agent.request({op: "prop", selector: planned.selector, name: planned.name});
  if (!reply.ok) throw new Error(describeFailure(reply));
  if (shown(reply.value) !== planned.expected) {
    throw new Error(`prop ${planned.name} on #${reply.node} = ${shown(reply.value)}, want ${planned.expected}`);
  }
  return null;
}

// Runs every line; returns [{line, message}] for the failures, continuing
// after each so one run reports all of them.
export async function run(agent, lines, {print} = {}) {
  const failures = [];
  for (const [index, line] of lines.entries()) {
    let planned;
    try {
      planned = plan(line);
    } catch (error) {
      failures.push({line: index + 1, message: error.message});
      continue;
    }
    if (!planned) continue;
    try {
      await step(agent, planned, {print});
    } catch (error) {
      failures.push({line: index + 1, message: error.message});
      if (/closed|no reply|ECONN/.test(error.message)) break;
    }
  }
  return failures;
}

function human(reply) {
  if (reply.op === "dump") return reply.text.trimEnd();
  if (reply.op === "find") return reply.nodes.map((node) => `#${node}`).join(" ") || "(no match)";
  if (reply.op === "prop") return `#${reply.node} ${shown(reply.value)}`;
  if (reply.op === "hello") return `${reply.protocol} v${reply.version} on ${reply.host}`;
  if (reply.op === "tree") return JSON.stringify(reply.nodes, null, 1);
  return `${reply.op} #${reply.node}`;
}

function parseArguments(argv) {
  const options = {commands: []};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = () => {
      index += 1;
      if (index >= argv.length) throw new Error(`${argument} needs a value`);
      return argv[index];
    };
    if (argument === "--tcp") options.tcp = value();
    else if (argument === "--ws-listen") options.ws = Number(value());
    else if (argument === "--artifact") options.artifact = value();
    else if (argument === "--unchecked") options.unchecked = true;
    else if (argument === "--script") options.script = value();
    else if (argument === "--json") options.json = true;
    else if (argument.startsWith("--")) throw new Error(`unknown option ${argument}`);
    else options.commands.push(argument);
  }
  if (!options.tcp === !options.ws) throw new Error("pass exactly one of --tcp HOST:PORT or --ws-listen PORT");
  if (!options.artifact && !options.unchecked) {
    throw new Error("pass --artifact PATH (the build the host runs) so a stale build is refused, or --unchecked");
  }
  return options;
}

export async function main(argv, {stdout = process.stdout, stderr = process.stderr} = {}) {
  let options;
  try {
    options = parseArguments(argv);
  } catch (error) {
    stderr.write(`lui-agent: ${error.message}\n`);
    return USAGE_EXIT;
  }
  if (options.artifact) {
    const freshness = checkReceipt(options.artifact);
    if (!freshness.fresh) {
      stderr.write(`lui-agent: refusing to drive: ${freshness.message}\n`);
      return STALE_EXIT;
    }
  } else {
    stderr.write("lui-agent: build freshness unchecked (--unchecked)\n");
  }
  const lines = options.script
    ? readFileSync(options.script, "utf8").split("\n")
    : options.commands;
  let agent;
  try {
    agent = options.tcp
      ? await connectTcp(options.tcp)
      : await listenWs(options.ws, {
        onListening: (port) => stderr.write(`lui-agent: open the page with ?lui-agent=ws://127.0.0.1:${port}\n`),
      });
    const hello = await agent.request({op: "hello"});
    if (!hello.ok || hello.protocol !== "lui-agent") throw new Error(`not a lui-agent host: ${JSON.stringify(hello)}`);
    if (hello.version !== 1) throw new Error(`host speaks lui-agent v${hello.version}; this client speaks v1`);
  } catch (error) {
    stderr.write(`lui-agent: ${error.message}\n`);
    agent?.close();
    return USAGE_EXIT;
  }
  const print = (reply) => stdout.write(`${options.json ? JSON.stringify(reply) : human(reply)}\n`);
  const failures = await run(agent, lines.length ? lines : ["dump"], {print});
  agent.close();
  for (const failure of failures) {
    const where = options.script ? `${path.basename(options.script)}:${failure.line}` : `command ${failure.line}`;
    stderr.write(`${where}: ${failure.message}\n`);
  }
  return failures.length ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
