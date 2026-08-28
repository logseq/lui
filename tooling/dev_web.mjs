import { spawn } from "node:child_process"
import path from "node:path"
import { fileURLToPath } from "node:url"

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
)

function option(name, fallback) {
  const index = process.argv.indexOf(name)
  return index === -1 ? fallback : process.argv[index + 1]
}

const host = option("--host", process.env.LUI_WEB_HOST ?? "0.0.0.0")
const port = option("--port", process.env.LUI_WEB_PORT ?? "8765")
const tailwindBinary = path.join(
  projectRoot,
  "platform",
  "web",
  "node_modules",
  ".bin",
  "tailwindcss",
)
const viteBinary = path.join(
  projectRoot,
  "platform",
  "web",
  "node_modules",
  ".bin",
  "vite",
)
const children = new Set()
let stopping = false

function start(command, args, extra = {}) {
  const child = spawn(command, args, {
    cwd: projectRoot,
    env: { ...process.env, ...extra },
    stdio: ["pipe", "inherit", "inherit"],
    detached: process.platform !== "win32",
  })
  children.add(child)
  child.once("exit", () => children.delete(child))
  return child
}

function stopChild(child) {
  if (child.exitCode !== null || child.signalCode !== null) return
  if (process.platform === "win32") child.kill("SIGTERM")
  else process.kill(-child.pid, "SIGTERM")
}

function stop(exitCode = 0) {
  if (stopping) return
  stopping = true
  for (const child of children) stopChild(child)
  const timer = setTimeout(() => process.exit(exitCode), 2_000)
  timer.unref()
  if (children.size === 0) process.exit(exitCode)
  Promise.all([...children].map((child) => new Promise((resolve) => child.once("exit", resolve))))
    .then(() => process.exit(exitCode))
}

function watch(label, command, args, extra) {
  const child = start(command, args, extra)
  child.once("error", (error) => {
    console.error(`${label} failed to start: ${error.message}`)
    stop(1)
  })
  child.once("exit", (code, signal) => {
    if (!stopping) {
      console.error(`${label} stopped unexpectedly (${signal ?? code})`)
      stop(code ?? 1)
    }
  })
}

function runOnce(label, command, args) {
  return new Promise((resolve, reject) => {
    const child = start(command, args)
    child.once("error", (error) => reject(error))
    child.once("exit", (code, signal) => {
      if (code === 0) resolve()
      else reject(new Error(`${label} failed (${signal ?? code})`))
    })
  })
}

process.once("SIGINT", () => stop(0))
process.once("SIGTERM", () => stop(0))

try {
  await runOnce(
    "Dune initial build",
    "opam",
    ["exec", "--", "dune", "build", "@web", "-j", "1"],
  )
  watch("Dune", "opam", ["exec", "--", "dune", "build", "@web", "-w", "-j", "1"])
  watch(
    "Tailwind",
    tailwindBinary,
    [
      "-i",
      "platform/web/src/lui.css",
      "-o",
      "platform/web/dist/lui.css",
      "--watch",
      "--minify",
    ],
  )
  watch(
    "Vite",
    viteBinary,
    ["--config", "platform/web/vite.config.mjs"],
    { LUI_WEB_HOST: host, LUI_WEB_PORT: port },
  )
} catch (error) {
  console.error(error.message)
  stop(1)
}
