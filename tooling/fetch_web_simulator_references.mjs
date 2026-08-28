import { execFile } from "node:child_process"
import { access, mkdir, readFile, stat, writeFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"

const execFileAsync = promisify(execFile)
const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const defaultManifest = path.join(projectRoot, "platform/web/references/web-simulator.json")

function option(name, fallback) {
  const index = process.argv.indexOf(name)
  return index === -1 ? fallback : process.argv[index + 1]
}

async function runGit(args, cwd = projectRoot) {
  return execFileAsync("git", args, { cwd, maxBuffer: 4 * 1024 * 1024 })
}

function normalizedRepository(repository) {
  return repository.replace(/\.git$/, "")
}

async function requireFile(checkout, relativePath, description) {
  const absolutePath = path.resolve(checkout, relativePath)
  const relative = path.relative(checkout, absolutePath)
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`${description} escapes the reference checkout: ${relativePath}`)
  }
  const metadata = await stat(absolutePath)
  if (!metadata.isFile()) {
    throw new Error(`${description} is not a file: ${relativePath}`)
  }
}

export async function verifyCheckout(reference, checkout) {
  const { stdout: headOutput } = await runGit(["rev-parse", "HEAD"], checkout)
  const head = headOutput.trim()
  if (head !== reference.commit) {
    throw new Error(`${reference.id} resolved ${head}, expected ${reference.commit}`)
  }

  const { stdout: originOutput } = await runGit(
    ["remote", "get-url", "origin"],
    checkout,
  )
  if (normalizedRepository(originOutput.trim()) !== normalizedRepository(reference.repository)) {
    throw new Error(`${reference.id} has an unexpected origin`)
  }

  await requireFile(checkout, reference.license.path, `${reference.id} license`)
  for (const sourcePath of reference.sourcePaths) {
    await requireFile(checkout, sourcePath, `${reference.id} source`)
  }
}

export async function fetchReference(reference, cacheDirectory) {
  const checkout = path.join(cacheDirectory, reference.id)
  try {
    await access(path.join(checkout, ".git"))
  } catch {
    await runGit([
      "clone",
      "--filter=blob:none",
      "--no-checkout",
      reference.repository,
      checkout,
    ])
  }

  await runGit(["fetch", "--depth", "1", "origin", reference.commit], checkout)
  await runGit(["checkout", "--detach", reference.commit], checkout)
  await verifyCheckout(reference, checkout)
  await writeFile(
    path.join(checkout, ".lui-reference.json"),
    `${JSON.stringify({ id: reference.id, repository: reference.repository, commit: reference.commit }, null, 2)}\n`,
  )
  return checkout
}

export async function fetchReferences(manifestPath = defaultManifest, cacheOverride) {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"))
  const cacheDirectory = path.resolve(
    projectRoot,
    cacheOverride ?? manifest.cacheDirectory,
  )
  await mkdir(cacheDirectory, { recursive: true })

  const checkouts = []
  for (const reference of manifest.references) {
    const checkout = await fetchReference(reference, cacheDirectory)
    checkouts.push({ id: reference.id, checkout })
    process.stdout.write(`verified ${reference.id} at ${reference.commit}\n`)
  }
  return checkouts
}

if (fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const manifestPath = path.resolve(option("--manifest", defaultManifest))
  const cacheDirectory = option("--cache", undefined)
  await fetchReferences(manifestPath, cacheDirectory)
}
