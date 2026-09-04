#!/usr/bin/env node
// Hook UserPromptSubmit — signale à Claude qu'un prefab HatLibrary existe déjà
// pour ce que l'utilisateur demande, sans qu'il ait à invoquer quoi que ce soit.
// N'écrit RIEN quand aucun prefab ne correspond : zéro token dans le cas général.
//
//   node <chemin>/hint.mjs   (reçoit le JSON du hook sur stdin)

import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import path from "node:path";

// Deux bibliothèques possibles, la personnelle d'abord (elle peut remplacer un
// prefab livré) : ~/HatLib/library, puis celle fournie avec le dépôt cloné.
const here = path.dirname(fileURLToPath(import.meta.url));
const ROOTS = [
  path.join(homedir(), "HatLib", "library"),
  path.resolve(here, "..", "..", "library"),
];
const MAX_HITS = 2;

const norm = (s) => String(s).toLowerCase()
  .normalize("NFD").replace(/\p{Diacritic}/gu, "")
  .replace(/[^a-z0-9]+/g, " ").trim();

function entriesOf(indexText, root) {
  const out = [];
  for (const line of indexText.split("\n")) {
    const t = line.trim();
    if (!t.startsWith("`")) continue;
    const parts = t.split("—").map((s) => s.trim());
    const file = (parts[0] || "").replace(/`/g, "");
    const rel = parts.find((s) => /\.luau$/.test(s) && !s.startsWith("`")) || "";
    const tagPart = parts.find((s) => /^tags?\s*:/i.test(s));
    if (!file || !rel || !tagPart) continue;
    out.push({
      file,
      abs: path.join(root, "snippets", rel),
      tags: tagPart.replace(/^tags?\s*:/i, "").split(",").map(norm).filter(Boolean),
    });
  }
  return out;
}

async function main() {
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  let prompt = "";
  try { prompt = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}").prompt || ""; }
  catch { return; }
  if (!prompt) return;
  // Notifications de tâches en arrière-plan, rappels système... : ce n'est pas
  // une demande de l'utilisateur, on ne suggère rien.
  if (/\[SYSTEM NOTIFICATION|<task-notification>|<system-reminder>/i.test(prompt)) return;

  const haystack = " " + norm(prompt) + " ";
  const seen = new Set();
  const hits = [];

  for (const root of ROOTS) {
    const index = await readFile(path.join(root, "index.md"), "utf8").catch(() => null);
    if (!index) continue;
    for (const entry of entriesOf(index, root)) {
      if (seen.has(entry.file.toLowerCase())) continue; // la bibliothèque perso gagne
      if (!entry.tags.some((tag) => haystack.includes(" " + tag + " "))) continue;
      seen.add(entry.file.toLowerCase());
      hits.push(entry);
      if (hits.length >= MAX_HITS) break;
    }
    if (hits.length >= MAX_HITS) break;
  }
  if (!hits.length) return;

  const list = hits.map((h) => `${h.file} → ${h.abs}`).join(" | ");
  process.stdout.write(
    `[HatLibrary] Prefab déjà écrit pour cette demande : ${list}. ` +
    `Applique le skill HatLibrary (copie du fichier + configurateur visuel) au lieu de réécrire ce code.\n`
  );
}

main().catch(() => {}).finally(() => process.exit(0));
