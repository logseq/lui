import path from "node:path"
import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
)

export default defineConfig({
  root: projectRoot,
  publicDir: false,
  optimizeDeps: {
    noDiscovery: true,
  },
  server: {
    host: process.env.LUI_WEB_HOST ?? "0.0.0.0",
    port: Number(process.env.LUI_WEB_PORT ?? 8765),
    strictPort: true,
    fs: {
      allow: [projectRoot],
    },
  },
})
