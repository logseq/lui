import {createReadStream} from "node:fs";
import {stat} from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import {pathToFileURL} from "node:url";

export const defaultHost = "0.0.0.0";
export const defaultPort = 8765;

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".map", "application/json; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".wasm", "application/wasm"],
]);

function requestedFile(root, requestUrl) {
  const pathname = decodeURIComponent(new URL(requestUrl, "http://localhost").pathname);
  const relativePath = pathname.replace(/^\/+/, "");
  const file = path.resolve(root, relativePath || "index.html");
  const relative = path.relative(root, file);

  return relative.startsWith("..") || path.isAbsolute(relative) ? null : file;
}

export function createStaticServer(rootDirectory = process.cwd()) {
  const root = path.resolve(rootDirectory);

  return http.createServer(async (request, response) => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.writeHead(405, {Allow: "GET, HEAD"}).end();
      return;
    }

    try {
      let file = requestedFile(root, request.url ?? "/");
      if (file === null) {
        response.writeHead(403).end();
        return;
      }

      const metadata = await stat(file);
      if (metadata.isDirectory()) {
        file = path.join(file, "index.html");
        await stat(file);
      }

      response.writeHead(200, {
        "Content-Length": (await stat(file)).size,
        "Content-Type": contentTypes.get(path.extname(file)) ?? "application/octet-stream",
      });
      if (request.method === "HEAD") {
        response.end();
      } else {
        createReadStream(file).pipe(response);
      }
    } catch (error) {
      if (error instanceof URIError) {
        response.writeHead(400).end();
      } else {
        response.writeHead(404).end();
      }
    }
  });
}

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1];
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const host = option("--host", process.env.LUI_WEB_HOST ?? defaultHost);
  const port = Number(option("--port", process.env.LUI_WEB_PORT ?? defaultPort));
  const root = option("--root", process.cwd());
  const server = createStaticServer(root);

  server.listen(port, host, () => {
    console.log(`LUI Gallery Web listening on http://${host}:${port}`);
  });
}
