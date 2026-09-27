import { readdir, stat } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
)
const emitRoot = path.join(
  projectRoot,
  "_build/default/examples/components/web/lui-components-web",
)
const watchSourceRoots = [
  path.join(projectRoot, "examples/components/web"),
  path.join(projectRoot, "examples/gallery"),
  path.join(projectRoot, "platform/web/melange"),
  path.join(projectRoot, "src"),
]
const OCAML_SOURCE_EXTENSIONS = new Set([".ml", ".mli", ".re", ".rei"])

const wait = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds))

// Latest mtime of any emitted .js under the melange.emit target.
async function latestEmitTime() {
  let latest = 0
  const stack = [emitRoot]
  while (stack.length > 0) {
    const dir = stack.pop()
    let entries
    try {
      entries = await readdir(dir, { withFileTypes: true })
    } catch {
      continue
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name)
      if (entry.isDirectory()) stack.push(full)
      else if (entry.name.endsWith(".js")) {
        const { mtimeMs } = await stat(full)
        if (mtimeMs > latest) latest = mtimeMs
      }
    }
  }
  return latest
}

function melangeHotReload() {
  let sourceGeneration = 0

  async function waitForMelangeOutput(generation, baseline) {
    for (let attempt = 0; attempt < 1200; attempt += 1) {
      if (generation !== sourceGeneration) return false
      if ((await latestEmitTime()) > baseline) return true
      await wait(50)
    }
    return false
  }

  return {
    name: "lui-melange-hot-reload",
    enforce: "post",
    // Plain Melange output has no LG-style mutable runtime references, so a
    // source change waits for a running `dune build @web --watch` (or manual
    // rebuild) to refresh the emit tree, then performs a full page reload.
    async handleHotUpdate({ file, modules, server }) {
      const normalizedFile = file.split(path.sep).join("/")
      if (normalizedFile.includes("/_build/default/")) {
        return []
      }
      if (
        !watchSourceRoots.some((root) => file.startsWith(root)) ||
        !OCAML_SOURCE_EXTENSIONS.has(path.extname(file))
      ) {
        return modules
      }

      sourceGeneration += 1
      const generation = sourceGeneration
      const baseline = await latestEmitTime()
      if (await waitForMelangeOutput(generation, baseline)) {
        server.ws.send({ type: "full-reload" })
      }
      return []
    },
  }
}

export default defineConfig({
  root: projectRoot,
  publicDir: false,
  plugins: [melangeHotReload()],
  optimizeDeps: {
    noDiscovery: true,
  },
  server: {
    host: process.env.LUI_WEB_HOST ?? "0.0.0.0",
    port: Number(process.env.LUI_WEB_PORT ?? 8765),
    strictPort: true,
    watch: {
      ignored: ["**/_build/default/**"],
    },
    fs: {
      allow: [projectRoot],
    },
  },
})
