import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { createServer } from "node:net"
import { readFile, writeFile } from "node:fs/promises"
import path from "node:path"
import { createRequire } from "node:module"
import test from "node:test"
import { fileURLToPath } from "node:url"

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..")
const require = createRequire(path.join(projectRoot, "platform/web/package.json"))
const { chromium } = require("playwright")
const gallerySource = path.join(projectRoot, "examples/components/lg/components/gallery.cljc")
const galleryCss = path.join(projectRoot, "examples/components/web/styles.css")
const jsFixture = path.join(
  projectRoot,
  "platform/web/test/fixtures/hot-reload/main.js",
)

async function availablePort() {
  const server = createServer()
  await new Promise((resolve, reject) => {
    server.once("error", reject)
    server.listen(0, "127.0.0.1", resolve)
  })
  const { port } = server.address()
  await new Promise((resolve) => server.close(resolve))
  return port
}

async function waitForServer(origin, process, output) {
  const deadline = Date.now() + 60_000
  while (Date.now() < deadline) {
    if (process.exitCode !== null) {
      assert.fail(`Web dev server exited before becoming ready:\n${output.join("")}`)
    }
    try {
      const response = await fetch(`${origin}/examples/components/web/index.html`)
      if (response.ok) return
    } catch {
      // The initial Dune and Tailwind builds have not completed yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  assert.fail(`Web dev server did not become ready:\n${output.join("")}`)
}

async function waitForServerToStop(origin) {
  const deadline = Date.now() + 5_000
  while (Date.now() < deadline) {
    try {
      await fetch(origin)
    } catch {
      return
    }
    await new Promise((resolve) => setTimeout(resolve, 50))
  }
  assert.fail("Web dev server left a child process running")
}

async function openSwitch(page) {
  const switchNavigation = page
    .locator("nav button")
    .filter({ hasText: /^Switch$/ })
  await switchNavigation.waitFor({ state: "attached" })
  await switchNavigation.evaluate((node) => node.click())
}

function nextPageLoad(page) {
  return new Promise((resolve) => page.once("load", () => resolve("reload")))
}

test("LG, CSS, and JavaScript update through Vite without a manual refresh", async () => {
  const originals = new Map(
    await Promise.all(
      [gallerySource, galleryCss, jsFixture].map(async (file) => [file, await readFile(file, "utf8")]),
    ),
  )
  const port = await availablePort()
  const output = []
  const dev = spawn(
    process.execPath,
    ["tooling/dev_web.mjs", "--host", "127.0.0.1", "--port", String(port)],
    { cwd: projectRoot, env: process.env, stdio: ["ignore", "pipe", "pipe"] },
  )
  dev.stdout.on("data", (chunk) => output.push(chunk.toString()))
  dev.stderr.on("data", (chunk) => output.push(chunk.toString()))
  const origin = `http://127.0.0.1:${port}`
  let browser

  try {
    await waitForServer(origin, dev, output)
    browser = await chromium.launch({ headless: true })
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } })
    page.on("console", (message) => {
      if (message.type() === "error") output.push(`Browser console: ${message.text()}\n`)
    })
    page.on("pageerror", (error) => output.push(`Browser error: ${error.message}\n`))
    await page.goto(`${origin}/examples/components/web/index.html`, { waitUntil: "networkidle" })
    await page.waitForTimeout(500)
    assert.ok(
      await page.locator("nav button").count(),
      `Gallery did not mount:\n${await page.locator("body").innerText()}\n${output.join("")}`,
    )
    await openSwitch(page)
    const switchControl = page.locator(".lui-switch-control")
    await switchControl.click()
    await page.evaluate(() => {
      window.__luiHotDocument = document
      window.__luiHotSwitch = document.querySelector(".lui-switch-control")
    })

    await writeFile(
      galleryCss,
      `${originals.get(galleryCss)}\n.lui-switch { outline: 3px solid rgb(1, 2, 3); }\n`,
    )
    await page.waitForFunction(
      () => getComputedStyle(document.querySelector(".lui-switch")).outlineColor === "rgb(1, 2, 3)",
    )
    assert.deepEqual(
      await page.evaluate(() => ({
        sameDocument: document === window.__luiHotDocument,
        sameSwitch: document.querySelector(".lui-switch-control") === window.__luiHotSwitch,
        checked: document.querySelector(".lui-switch-control").checked,
      })),
      { sameDocument: true, sameSwitch: true, checked: true },
    )

    const lgUpdated = originals
      .get(gallerySource)
      .replace(
        "Switch shares the same model-owned Signal.",
        "LG hot reload applied.",
    )
    const firstLgUpdate = Promise.race([
      nextPageLoad(page),
      page.getByText("LG hot reload applied.", { exact: true })
        .waitFor()
        .then(() => "hmr"),
    ])
    await writeFile(gallerySource, lgUpdated)
    assert.equal(
      await firstLgUpdate,
      "hmr",
      "LG updates must not reload the document",
    )
    await openSwitch(page)
    await page.getByText("LG hot reload applied.", { exact: true }).waitFor()
    assert.deepEqual(
      await page.evaluate(() => ({
        sameDocument: document === window.__luiHotDocument,
        sameSwitch: document.querySelector(".lui-switch-control") === window.__luiHotSwitch,
        checked: document.querySelector(".lui-switch-control").checked,
        galleryShells: document.querySelectorAll(".lui-gallery-shell").length,
        popupPortals: document.querySelectorAll(".lui-popup-portal").length,
      })),
      {
        sameDocument: true,
        sameSwitch: true,
        checked: true,
        galleryShells: 1,
        popupPortals: 1,
      },
    )
    assert.doesNotMatch(output.join(""), /Browser error:|\[lui-hmr\] Failed/)
    assert.doesNotMatch(
      output.join(""),
      /Failed to reload .*lui_components_web/,
      "Dune output must settle before Vite imports the generated bundle",
    )

    await writeFile(gallerySource, `${lgUpdated}\n(`)
    await page.waitForTimeout(500)
    assert.equal(await page.getByText("LG hot reload applied.", { exact: true }).count(), 1)
    const recoveredLgUpdate = Promise.race([
      nextPageLoad(page),
      page.getByText("LG hot reload recovered.", { exact: true })
        .waitFor()
        .then(() => "hmr"),
    ])
    await writeFile(
      gallerySource,
      lgUpdated.replace("LG hot reload applied.", "LG hot reload recovered."),
    )
    assert.equal(
      await recoveredLgUpdate,
      "hmr",
      "LG recovery must not reload the document",
    )
    await openSwitch(page)
    await page.getByText("LG hot reload recovered.", { exact: true }).waitFor()
    assert.deepEqual(
      await page.evaluate(() => ({
        sameDocument: document === window.__luiHotDocument,
        sameSwitch: document.querySelector(".lui-switch-control") === window.__luiHotSwitch,
        checked: document.querySelector(".lui-switch-control").checked,
      })),
      { sameDocument: true, sameSwitch: true, checked: true },
    )

    await page.reload({ waitUntil: "networkidle" })
    await openSwitch(page)
    assert.equal(await switchControl.isChecked(), false)

    await page.goto(
      `${origin}/platform/web/test/fixtures/hot-reload/index.html`,
      { waitUntil: "networkidle" },
    )
    await page.evaluate(() => { window.__luiJsHotDocument = document })
    await writeFile(
      jsFixture,
      originals.get(jsFixture).replace("JavaScript HMR one", "JavaScript HMR two"),
    )
    await page.getByText("JavaScript HMR two", { exact: true }).waitFor()
    assert.equal(
      await page.evaluate(() => document === window.__luiJsHotDocument),
      true,
    )
  } catch (error) {
    console.error(output.join(""))
    error.message = `${error.message}\n\nDevelopment output:\n${output.join("")}`
    throw error
  } finally {
    await Promise.all(
      [...originals].map(([file, contents]) => writeFile(file, contents)),
    )
    if (browser) await browser.close()
    dev.kill("SIGTERM")
    await new Promise((resolve) => {
      if (dev.exitCode !== null) resolve()
      else dev.once("exit", resolve)
    })
    await waitForServerToStop(origin)
  }
})
