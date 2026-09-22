import { readFile, stat } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
)
const generatedBundle = path.join(
  projectRoot,
  "_build/default/examples/components/web/lui-components-web/examples/components/web/lui_components_web.js",
)
const generatedBootstrap = path.join(
  projectRoot,
  "_build/default/examples/components/web/lui-components-web/examples/components/web/web_bootstrap.js",
)
const gallerySourceRoot = path.join(
  projectRoot,
  "examples/components/lg",
)
const LG_SOURCE_EXTENSIONS = new Set([".cljc", ".mli"])

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

function melangeHotReload() {
  const generatedFiles = new Map()
  let sourceGeneration = 0

  async function waitForMelangeOutput(generation, previousBundle, bootstrapTime) {
    for (let attempt = 0; attempt < 1200; attempt += 1) {
      if (generation !== sourceGeneration) return undefined
      try {
        const [bundle, bootstrapInfo] = await Promise.all([
          readFile(generatedBundle, "utf8"),
          stat(generatedBootstrap),
        ])
        if (bundle !== previousBundle && bootstrapInfo.mtimeMs > bootstrapTime) {
          return settleGeneratedFile(generatedBundle)
        }
      } catch {
        // Dune replaces the generated output tree atomically.
      }
      await wait(50)
    }
    return undefined
  }

  return {
    name: "lui-melange-hot-reload",
    enforce: "post",
    async transform(code, id) {
      const normalizedId = id.split("?", 1)[0].split(path.sep).join("/")
      const generatedJavaScript =
        normalizedId.includes("/_build/default/") &&
        normalizedId.endsWith(".js")
      if (generatedJavaScript) {
        try {
          generatedFiles.set(normalizedId, await readFile(normalizedId, "utf8"))
        } catch {
          generatedFiles.set(normalizedId, code)
        }
      }
      if (
        !generatedJavaScript ||
        !code.includes("Lg_runtime__Runtime_reference") ||
        !code.includes("__root")
      ) {
        return null
      }

      const rootNames = [
        ...new Set(code.match(/\b[A-Za-z_$][\w$]*__root\b/g) ?? []),
      ]
      if (rootNames.length === 0) return null

      const hotReloadBoundary = `

const __luiHmrRoots = import.meta.hot?.data.luiRoots ?? {
  ${rootNames.join(",\n  ")}
}

if (import.meta.hot) {
  import.meta.hot.data.luiRoots = __luiHmrRoots
  import.meta.hot.accept((nextModule) => {
    if (!nextModule) return

    Object.entries(__luiHmrRoots)
      .filter(
        ([name, current]) =>
          nextModule[name] && current.replacement_observers !== 0,
      )
      .forEach(([name, current]) => {
        try {
          Lg_runtime__Runtime_reference.replace_for_redefinition(
            current,
            nextModule[name].value,
          )
        } catch (error) {
          console.error("[lui-hmr] Failed to replace " + name, error.cause ?? error)
          throw error
        }
      })
  })
}
`

      return { code: `${code}${hotReloadBoundary}`, map: null }
    },
    async handleHotUpdate({ file, modules, server }) {
      const normalizedFile = file.split(path.sep).join("/")
      if (normalizedFile.includes("/_build/default/")) {
        return []
      }
      if (
        !file.startsWith(gallerySourceRoot) ||
        !LG_SOURCE_EXTENSIONS.has(path.extname(file))
      ) {
        return modules
      }

      sourceGeneration += 1
      const generation = sourceGeneration
      const normalizedBundle = generatedBundle.split(path.sep).join("/")
      const previous = generatedFiles.get(normalizedBundle)
      let bootstrapTime = 0
      try {
        bootstrapTime = (await stat(generatedBootstrap)).mtimeMs
      } catch {
        // The initial build is guaranteed before Vite starts.
      }
      const current = await waitForMelangeOutput(
        generation,
        previous,
        bootstrapTime,
      )
      if (current === undefined) return []
      generatedFiles.set(normalizedBundle, current)
      const generatedModule = server.moduleGraph.getModuleById(
        generatedBundle,
      )
      return generatedModule ? [generatedModule] : []
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
