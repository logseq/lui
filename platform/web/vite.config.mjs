import { readFile, stat } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
)
const buildOutputRoot = path.join(
  projectRoot,
  "_build/default/examples/components/web/lui-components-web",
)
const examplesRoot = path.join(projectRoot, "examples")
const OCAML_SOURCE_EXTENSIONS = new Set([".ml", ".mli"])

const wait = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds))

async function settleGeneratedFile(file) {
  let previous
  for (let attempt = 0; attempt < 10; attempt += 1) {
    await wait(20)
    try {
      const current = await readFile(file, "utf8")
      if (current === previous) return current
      previous = current
    } catch {
      previous = undefined
    }
  }
  return previous
}

function generatedModuleFor(sourceFile) {
  const relative = path.relative(examplesRoot, sourceFile)
  return path.join(
    buildOutputRoot,
    "examples",
    relative.replace(/\.(ml|mli)$/, ".js"),
  )
}

function melangeHotReload() {
  let sourceGeneration = 0

  async function waitForMelangeOutput(generation, generatedModule, since) {
    for (let attempt = 0; attempt < 1200; attempt += 1) {
      if (generation !== sourceGeneration) return false
      try {
        const info = await stat(generatedModule)
        if (info.mtimeMs > since) {
          return (await settleGeneratedFile(generatedModule)) !== undefined
        }
      } catch {
        // Dune replaces the generated output tree atomically.
      }
      await wait(50)
    }
    return false
  }

  return {
    name: "lui-melange-hot-reload",
    enforce: "post",
    async handleHotUpdate({ file, modules, server }) {
      const normalizedFile = file.split(path.sep).join("/")
      if (normalizedFile.includes("/_build/default/")) {
        return []
      }
      if (
        !file.startsWith(examplesRoot) ||
        !OCAML_SOURCE_EXTENSIONS.has(path.extname(file))
      ) {
        return modules
      }

      sourceGeneration += 1
      const generation = sourceGeneration
      const { mtimeMs: since } = await stat(file)
      const ready = await waitForMelangeOutput(
        generation,
        generatedModuleFor(file),
        since,
      )
      if (!ready) return []
      server.moduleGraph.invalidateAll()
      server.ws.send({ type: "full-reload" })
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
