#!/usr/bin/env node
// HatBridge — pont local entre une page HTML (configurateur, formulaire) et les fichiers du projet.
// Sans dépendance. Écoute uniquement sur 127.0.0.1, confine tous les accès au dossier --root.
//
//   node bridge.mjs --root <projet> --page <page.html> [--file <chemin/relatif>] [--open]
//                   [--port 7777] [--idle 1800]
//
// La page servie a accès à :
//   GET  /api/ping            -> { hatbridge:true, root }
//   GET  /api/read?path=rel   -> { ok, path, text }
//   PUT  /api/write?path=rel  -> { ok }  (corps = contenu du fichier)
//   POST /api/quit            -> { ok }  (arrêt du pont)
// Relance idempotente : si un pont tourne déjà sur le même root, on rouvre juste l'onglet.

import { createServer } from "node:http";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) continue;
    const key = argv[i].slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) out[key] = true;
    else { out[key] = next; i++; }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const root = path.resolve(args.root || process.cwd());
const pagePath = args.page ? path.resolve(String(args.page)) : null;
const basePort = Number(args.port) || 7777;
const idleMs = (Number(args.idle) || 1800) * 1000;

if (!pagePath) {
  console.error("bridge: --page <fichier.html> est obligatoire");
  process.exit(1);
}

const toPosix = (s) => String(s).split(path.sep).join("/").split("\\").join("/");

const targetUrl = (port) => {
  const q = args.file ? "?file=" + encodeURIComponent(toPosix(args.file)) : "";
  return `http://127.0.0.1:${port}/${q}`;
};

function openBrowser(url) {
  try {
    const [cmd, cargs] =
      process.platform === "win32" ? ["cmd", ["/c", "start", "", url]]
      : process.platform === "darwin" ? ["open", [url]]
      : ["xdg-open", [url]];
    spawn(cmd, cargs, { detached: true, stdio: "ignore" }).unref();
  } catch { /* l'utilisateur ouvrira l'URL à la main */ }
}

// --- détachement ----------------------------------------------------------
// Le pont doit survivre à la commande qui le lance : un lanceur de tâches en
// arrière-plan tue son processus enfant dès qu'il le croit terminé. On se
// relance donc détaché, puis on attend que le vrai pont réponde pour afficher
// son URL. `--foreground` garde l'ancien comportement (tests, débogage).
async function waitForBridge(deadlineMs = 5000) {
  const until = Date.now() + deadlineMs;
  while (Date.now() < until) {
    for (let port = basePort; port <= basePort + 20; port++) {
      try {
        const r = await fetch(`http://127.0.0.1:${port}/api/ping`, { signal: AbortSignal.timeout(400) });
        const info = await r.json();
        if (info && info.hatbridge && path.resolve(info.root) === root) return targetUrl(port);
      } catch { /* port libre ou pas un hatbridge */ }
    }
    await new Promise((r) => setTimeout(r, 120));
  }
  return null;
}

if (!args.foreground && !process.env.HATBRIDGE_CHILD) {
  spawn(process.execPath, [fileURLToPath(import.meta.url), ...process.argv.slice(2)], {
    detached: true,
    stdio: "ignore",
    env: { ...process.env, HATBRIDGE_CHILD: "1" },
  }).unref();
  const url = await waitForBridge();
  console.log(url ? `HATBRIDGE_URL=${url}` : "HATBRIDGE: pont détaché lancé (URL non confirmée)");
  process.exit(0);
}

// --- sécurité : tout chemin doit rester sous root -------------------------
function resolveInRoot(rel) {
  const cleaned = toPosix(rel || "").replace(/^\/+/, "");
  const p = path.resolve(root, cleaned);
  if (p !== root && !p.startsWith(root + path.sep)) throw new Error("chemin hors du projet");
  return p;
}

const MIME = {
  ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png",
};

let idleTimer = null;
function touchIdle() {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => { server.close(); process.exit(0); }, idleMs);
}

function json(res, code, obj) {
  res.writeHead(code, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(obj));
}

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks).toString("utf8");
}

const server = createServer(async (req, res) => {
  touchIdle();
  let url;
  try { url = new URL(req.url, "http://127.0.0.1"); } catch { return json(res, 400, { ok: false }); }
  const p = decodeURIComponent(url.pathname);

  try {
    if (p === "/api/ping") return json(res, 200, { hatbridge: true, root });

    if (p === "/api/read" && req.method === "GET") {
      const abs = resolveInRoot(url.searchParams.get("path"));
      const text = await readFile(abs, "utf8");
      return json(res, 200, { ok: true, path: toPosix(path.relative(root, abs)), text });
    }

    if (p === "/api/write" && (req.method === "PUT" || req.method === "POST")) {
      const abs = resolveInRoot(url.searchParams.get("path"));
      const text = await readBody(req);
      await mkdir(path.dirname(abs), { recursive: true });
      await writeFile(abs, text, "utf8");
      return json(res, 200, { ok: true, path: toPosix(path.relative(root, abs)) });
    }

    if (p === "/api/quit") {
      json(res, 200, { ok: true });
      return setTimeout(() => { server.close(); process.exit(0); }, 150);
    }

    // Page principale
    if (p === "/" || p === "/index.html") {
      const html = await readFile(pagePath, "utf8");
      res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
      return res.end(html);
    }

    // Statique, confiné au projet
    const abs = resolveInRoot(p);
    const buf = await readFile(abs);
    res.writeHead(200, { "content-type": MIME[path.extname(abs).toLowerCase()] || "text/plain; charset=utf-8" });
    res.end(buf);
  } catch (err) {
    json(res, err.code === "ENOENT" ? 404 : 400, { ok: false, error: String(err.message || err) });
  }
});

function listen(port, attempt = 0) {
  if (attempt > 20) { console.error("bridge: aucun port libre à partir de " + basePort); process.exit(1); }
  server.once("error", async (err) => {
    if (err.code !== "EADDRINUSE") { console.error("bridge:", err.message); process.exit(1); }
    // Un pont tourne peut-être déjà sur ce projet : on le réutilise au lieu d'en lancer un second.
    try {
      const r = await fetch(`http://127.0.0.1:${port}/api/ping`, { signal: AbortSignal.timeout(1200) });
      const info = await r.json();
      if (info && info.hatbridge && path.resolve(info.root) === root) {
        console.log(`HATBRIDGE_URL=${targetUrl(port)} (déjà en cours)`);
        if (args.open) openBrowser(targetUrl(port));
        process.exit(0);
      }
    } catch { /* pas un hatbridge : port suivant */ }
    listen(port + 1, attempt + 1);
  });
  server.listen(port, "127.0.0.1", () => {
    console.log(`HATBRIDGE_URL=${targetUrl(port)}`);
    touchIdle();
    if (args.open) openBrowser(targetUrl(port));
  });
}

listen(basePort);
