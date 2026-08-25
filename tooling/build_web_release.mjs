import {brotliCompressSync, constants, gzipSync} from "node:zlib";
import {cp, mkdir, readFile, readdir, rm} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import path from "node:path";
import {build} from "../platform/web/node_modules/esbuild/lib/main.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const output = path.join(root, "_build/web-release");
const entry = path.join(
  root,
  "_build/default/examples/components/web/lui-components-web/examples/components/web/web_bootstrap.js",
);

await rm(output, {recursive: true, force: true});
await mkdir(output, {recursive: true});
await build({
  entryPoints: [entry],
  outfile: path.join(output, "app.js"),
  bundle: true,
  minify: true,
  treeShaking: true,
  format: "esm",
  platform: "browser",
  target: "es2022",
  legalComments: "none",
});

await Promise.all([
  cp(
    path.join(root, "examples/components/web/index.release.html"),
    path.join(output, "index.html"),
  ),
  cp(
    path.join(root, "examples/components/web/styles.css"),
    path.join(output, "styles.css"),
  ),
  cp(
    path.join(root, "platform/web/dist/lui.css"),
    path.join(output, "lui.css"),
  ),
  cp(
    path.join(root, "platform/web/dist/icons"),
    path.join(output, "icons"),
    {recursive: true},
  ),
]);

async function filesUnder(directory) {
  const entries = await readdir(directory, {withFileTypes: true});
  const files = await Promise.all(entries.map(async (item) => {
    const target = path.join(directory, item.name);
    return item.isDirectory() ? filesUnder(target) : [target];
  }));
  return files.flat();
}

function sizes(buffer) {
  return {
    raw: buffer.length,
    gzip: gzipSync(buffer, {level: 9}).length,
    brotli: brotliCompressSync(buffer, {
      params: {[constants.BROTLI_PARAM_QUALITY]: 11},
    }).length,
  };
}

const app = await readFile(path.join(output, "app.js"));
const deployFiles = await filesUnder(output);
const deploy = Buffer.concat(await Promise.all(deployFiles.map((file) => readFile(file))));
console.log(JSON.stringify({app: sizes(app), deploy: sizes(deploy)}, null, 2));
