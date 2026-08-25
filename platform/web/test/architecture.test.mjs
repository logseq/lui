import assert from "node:assert/strict"
import { readFile, readdir } from "node:fs/promises"
import test from "node:test"

const webRoot = new URL("../", import.meta.url)
const examplesRoot = new URL("../../../examples/", import.meta.url)

async function filesUnder(directory, suffixes) {
  const entries = await readdir(directory, { withFileTypes: true })
  const nested = await Promise.all(entries.map(async (entry) => {
    const url = new URL(`${entry.name}${entry.isDirectory() ? "/" : ""}`, directory)
    if (entry.isDirectory()) return filesUnder(url, suffixes)
    return suffixes.some((suffix) => entry.name.endsWith(suffix)) ? [url] : []
  }))
  return nested.flat()
}

test("Web components are implemented by the LG backend without raw JavaScript coordinators", async () => {
  const platformSources = await filesUnder(webRoot, [".ml", ".cljc"])
  const exampleBootstraps = (await filesUnder(examplesRoot, ["web_bootstrap.ml"]))
  const sources = await Promise.all(
    [...platformSources, ...exampleBootstraps].map(async (url) => [url, await readFile(url, "utf8")]),
  )

  const rawSources = sources.filter(([, source]) => source.includes("[%raw"))
  const componentInstallers = sources.filter(([, source]) => /Web_(?:dialog|tooltip)\.install/.test(source))

  assert.deepEqual(rawSources.map(([url]) => url.pathname), [])
  assert.deepEqual(componentInstallers.map(([url]) => url.pathname), [])
})
