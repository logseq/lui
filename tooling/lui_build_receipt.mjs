#!/usr/bin/env node
// Build receipts: what an artifact was built from, so a driver can refuse
// to drive a build older than its sources.
//
//   node tooling/lui_build_receipt.mjs write --artifact PATH --command CMD --input DIR...
//   node tooling/lui_build_receipt.mjs check --artifact PATH
//
// `write` records <artifact>.lui-build.json: the artifact's digest, the
// command that rebuilds it, and the SHA-256 of every input file (tracked or
// untracked-but-not-ignored under the input roots). `check` recomputes them
// and exits 3 with the rebuild command when the artifact or any input
// changed, or when there is no receipt.
import {createHash} from "node:crypto";
import {execFileSync} from "node:child_process";
import {existsSync, readFileSync, readdirSync, renameSync, statSync, writeFileSync} from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

export const RECEIPT_VERSION = 1;
export const STALE_EXIT = 3;
export const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export const receiptPath = (artifact) => `${path.resolve(artifact)}.lui-build.json`;

const digestFile = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");

function walk(directory) {
  return readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) return walk(full);
    return entry.isFile() ? [full] : [];
  });
}

const portable = (file) => file.split(path.sep).join("/");

export function digestArtifact(artifact) {
  if (!statSync(artifact).isDirectory()) return digestFile(artifact);
  const hash = createHash("sha256");
  for (const file of walk(artifact).map((full) => portable(path.relative(artifact, full))).sort()) {
    hash.update(`${file}\0${digestFile(path.join(artifact, file))}\0`);
  }
  return hash.digest("hex");
}

export function listInputs(root, inputs) {
  for (const input of inputs) {
    if (!existsSync(path.join(root, input))) throw new Error(`build input ${input} does not exist under ${root}`);
  }
  let files;
  try {
    files = execFileSync(
      "git", ["-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", ...inputs],
      {encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 64 * 1024 * 1024},
    ).split("\0").filter(Boolean);
  } catch {
    files = inputs.flatMap((input) => {
      const full = path.join(root, input);
      return statSync(full).isDirectory() ? walk(full).map((file) => portable(path.relative(root, file))) : [portable(input)];
    });
  }
  return [...new Set(files)].filter((file) => existsSync(path.join(root, file))).sort();
}

export function digestInputs(root, inputs) {
  return Object.fromEntries(listInputs(root, inputs).map((file) => [file, digestFile(path.join(root, file))]));
}

export function writeReceipt({artifact, command, inputs, root = repositoryRoot}) {
  if (!inputs?.length) throw new Error("a receipt needs at least one --input");
  if (!command) throw new Error("a receipt needs the --command that rebuilds the artifact");
  const receipt = {
    version: RECEIPT_VERSION,
    artifact: path.resolve(artifact),
    artifactDigest: digestArtifact(artifact),
    root: path.resolve(root),
    command,
    inputs,
    files: digestInputs(root, inputs),
  };
  const target = receiptPath(artifact);
  writeFileSync(`${target}.tmp`, `${JSON.stringify(receipt, null, 1)}\n`);
  renameSync(`${target}.tmp`, target);
  return target;
}

const listed = (files) =>
  files.length <= 5 ? files.join(", ") : `${files.slice(0, 5).join(", ")} and ${files.length - 5} more`;

// {fresh: true} or {fresh: false, changed, message}; never throws for a
// missing or unreadable receipt, which is itself a refusal.
export function checkReceipt(artifact) {
  const target = receiptPath(artifact);
  if (!existsSync(artifact)) {
    return {fresh: false, changed: [], message: `${artifact} does not exist; build it first`};
  }
  let receipt;
  try {
    receipt = JSON.parse(readFileSync(target, "utf8"));
  } catch {
    return {
      fresh: false, changed: [],
      message: `no build receipt at ${target}; build ${artifact} with its host build script, which writes one`,
    };
  }
  if (receipt.version !== RECEIPT_VERSION) {
    return {fresh: false, changed: [], message: `${target} has receipt version ${receipt.version}, expected ${RECEIPT_VERSION}; run ${receipt.command}`};
  }
  if (digestArtifact(artifact) !== receipt.artifactDigest) {
    return {fresh: false, changed: [], message: `${artifact} changed after its receipt was written; run ${receipt.command}`};
  }
  const now = digestInputs(receipt.root, receipt.inputs);
  const changed = [...new Set([...Object.keys(now), ...Object.keys(receipt.files)])]
    .filter((file) => now[file] !== receipt.files[file])
    .sort();
  if (changed.length === 0) return {fresh: true, changed, command: receipt.command};
  return {
    fresh: false, changed, command: receipt.command,
    message: `${artifact} build is stale: ${listed(changed)} changed since it was built; run ${receipt.command}`,
  };
}

function parse(argv) {
  const options = {inputs: []};
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (flag === "--artifact") options.artifact = value;
    else if (flag === "--command") options.command = value;
    else if (flag === "--input") options.inputs.push(value);
    else if (flag === "--root") options.root = value;
    else throw new Error(`unknown option ${flag}`);
    index += 1;
  }
  if (!options.artifact) throw new Error("--artifact is required");
  return options;
}

function main([mode, ...argv]) {
  const options = parse(argv);
  if (mode === "write") {
    process.stderr.write(`lui build receipt: ${writeReceipt(options)}\n`);
    return 0;
  }
  if (mode === "check") {
    const result = checkReceipt(options.artifact);
    if (result.fresh) return 0;
    process.stderr.write(`refusing to drive: ${result.message}\n`);
    return STALE_EXIT;
  }
  throw new Error("usage: lui_build_receipt.mjs write|check --artifact PATH [--command CMD --input DIR...]");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`lui build receipt: ${error.message}\n`);
    process.exitCode = 2;
  }
}
