#!/usr/bin/env node
// Vérifie qu'un prefab est conforme AVANT de l'ajouter à la bibliothèque.
// Ne remplace pas un test en jeu, mais attrape les fautes qu'on ne voit pas à la relecture.
//
//   node check.mjs <fichier.luau> [autre.luau ...]
//   node check.mjs --all          (tous les prefabs de ~/HatLib/library/snippets)
//
// Contrôles :
//   1. structure Luau  — blocs ouverts/fermés (function/if/do/repeat vs end/until)
//   2. bloc CONFIG     — analysé par le parseur RÉEL du configurateur
//   3. annotations     — `si:` pointe sur un booléen existant, `options:` contient la valeur
//   4. bornes          — la valeur d'un nombre tient dans son `min..max`
//   5. aller-retour    — réécrire le bloc sans rien changer rend le fichier identique
//   6. sortie          — le fichier se termine par un `return`
//   7. index           — une entrée avec des `tags:` existe dans index.md

import { readFile, readdir, access } from "node:fs/promises";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import path from "node:path";

const SKILL_DIR = path.dirname(fileURLToPath(import.meta.url));
// Mêmes deux bibliothèques que le hook : la personnelle d'abord, puis celle
// livrée avec le dépôt cloné. On ne garde que celles qui existent vraiment.
const ALL_ROOTS = [
  path.join(homedir(), "HatLib", "library"),
  path.resolve(SKILL_DIR, "..", "..", "library"),
];

// --- parseur du configurateur, extrait de la page pour rester la seule source de vérité ---
const html = await readFile(path.join(SKILL_DIR, "configurator.html"), "utf8");
const slice = (from, to) => {
  const a = html.indexOf(from), b = html.indexOf(to, a);
  if (a === -1 || b === -1) throw new Error("configurator.html : marqueur introuvable « " + from + " »");
  return html.slice(a, b);
};
const makeParser = new Function(`
  let rawText = ""; let items = []; let blockStart = -1, blockEnd = -1; let eol = "\\n";
  ${slice("function parseConfig()", "// ---------------------------------------------------------------- rendu")}
  ${slice("function serialize(f)", "function updatePreview()")}
  return {
    parse: (t) => { rawText = t; parseConfig(); return { items, blockStart, blockEnd }; },
    rebuild: () => { const l = rawText.split(/\\r?\\n/);
      return [...l.slice(0, blockStart), ...buildBlockLines(), ...l.slice(blockEnd)].join(eol); },
  };
`);

// --- 1. équilibre des blocs Luau -----------------------------------------
// On retire commentaires et chaînes, puis on compte les ouvrants/fermants.
// `if` en position d'expression (Luau : `local x = if c then a else b`) n'ouvre pas de bloc.
function checkStructure(src) {
  // Les remplacements gardent les sauts de ligne, pour que les numéros restent justes.
  const blank = (m) => m.replace(/[^\n]/g, " ");
  const code = src
    .replace(/--\[\[[\s\S]*?\]\]/g, blank)      // commentaires longs
    .replace(/\[\[[\s\S]*?\]\]/g, blank)        // chaînes longues
    .replace(/--[^\n]*/g, blank)                // commentaires de ligne
    .replace(/"(?:[^"\\\n]|\\.)*"/g, '"s"')     // chaînes "..."
    .replace(/'(?:[^'\\\n]|\\.)*'/g, '"s"');    // chaînes '...'

  let depth = 0;
  const problems = [];
  const tokenRe = /\b(function|if|do|repeat|end|until|then|else|elseif)\b/g;
  let m;
  while ((m = tokenRe.exec(code))) {
    const tok = m[1];
    if (tok === "if") {
      // `if` d'expression (Luau : `local x = if c then a else b`) : il n'ouvre pas de bloc.
      // Il n'est jamais en début de ligne, et suit toujours un opérateur ou une ouverture.
      const lineStart = code.lastIndexOf("\n", m.index) + 1;
      const beforeOnLine = code.slice(lineStart, m.index).trimEnd();
      if (beforeOnLine !== "" && /[=,({[]$|\b(return|and|or|else)$/.test(beforeOnLine)) continue;
      depth++;
    } else if (tok === "function" || tok === "do" || tok === "repeat") {
      depth++;
    } else if (tok === "end" || tok === "until") {
      depth--;
      if (depth < 0) {
        const line = code.slice(0, m.index).split("\n").length;
        problems.push(`« ${tok} » en trop ligne ${line}`);
        depth = 0;
      }
    }
  }
  if (depth > 0) problems.push(`${depth} bloc(s) jamais fermé(s) — il manque autant de « end »`);
  return problems;
}

// --- vérification d'un fichier -------------------------------------------
async function checkFile(file, indexText) {
  const problems = [];
  const src = await readFile(file, "utf8");
  const parser = makeParser();

  problems.push(...checkStructure(src));

  const { items, blockStart } = parser.parse(src);
  const fields = items.filter((i) => i.kind === "field");

  if (blockStart === -1) {
    problems.push("aucun bloc « ⚙️ CONFIG »");
  } else if (fields.length === 0) {
    problems.push("bloc CONFIG vide (aucune ligne `local NOM = valeur` reconnue)");
  }

  const byName = new Map(fields.map((f) => [f.name, f]));
  for (const f of fields) {
    if (f.dep) {
      const parent = byName.get(f.dep);
      if (!parent) {
        problems.push(`${f.name} : « si: ${f.dep} » ne correspond à aucune option`);
      } else if (!f.depOp) {
        if (parent.type !== "bool") problems.push(`${f.name} : « si: ${f.dep} » vise une option non booléenne`);
      } else if (f.depOp === "=" || f.depOp === "!=") {
        // Comparaison à des valeurs : elles doivent exister dans le parent.
        const wanted = String(f.depValue).split("|").map((s) => s.trim()).filter(Boolean);
        if (!wanted.length) {
          problems.push(`${f.name} : « si: ${f.dep} ${f.depOp} » sans valeur à comparer`);
        } else if (parent.type === "enum") {
          for (const w of wanted) {
            if (!parent.options.includes(w)) {
              problems.push(`${f.name} : « si: ${f.dep} ${f.depOp} ${w} » — ${w} absent de options: ${parent.options.join("|")}`);
            }
          }
        }
      } else if (parent.type !== "number") {
        problems.push(`${f.name} : « si: ${f.dep} ${f.depOp} … » compare une option non numérique`);
      }
    }
    if (f.requires && !/^[a-z0-9_\-]+\/[A-Za-z0-9_\-]+\.luau$/.test(f.requires)) {
      problems.push(`${f.name} : « requiert: ${f.requires} » n'a pas la forme categorie/Nom.luau`);
    }
    if (f.type === "enum" && !f.options.includes(String(f.value))) {
      problems.push(`${f.name} : valeur ${JSON.stringify(f.value)} absente de options: ${f.options.join("|")}`);
    }
    if (f.type === "number" && (f.value < f.min || f.value > f.max)) {
      problems.push(`${f.name} : ${f.value} hors des bornes ${f.min}..${f.max}`);
    }
    if (f.type === "text") {
      problems.push(`${f.name} : expression non reconnue (champ texte brut dans le configurateur)`);
    }
  }

  if (blockStart !== -1 && parser.rebuild() !== src) {
    problems.push("aller-retour non neutre : réécrire le bloc sans rien changer modifie le fichier");
  }

  if (!/\breturn\b[^\n]*\n?\s*$/.test(src)) {
    problems.push("le fichier ne se termine pas par un `return` (obligatoire pour un ModuleScript)");
  }

  const base = path.basename(file);
  const entry = indexText.split("\n").find((l) => l.includes("`" + base + "`"));
  if (!entry) problems.push(`absent de index.md`);
  else if (!/tags?\s*:/i.test(entry)) problems.push(`entrée d'index sans « tags: » — invisible pour le hook`);

  return { file: base, fields: fields.length, problems };
}

// --- main ----------------------------------------------------------------
const roots = [];
for (const r of ALL_ROOTS) {
  try { await access(path.join(r, "index.md")); roots.push(r); } catch {}
}
if (roots.length === 0) {
  console.error("Aucune bibliothèque trouvée. Cherché dans :\n  " + ALL_ROOTS.join("\n  "));
  process.exit(1);
}

let files = process.argv.slice(2);
if (files[0] === "--all" || files.length === 0) {
  files = [];
  for (const lib of roots) {
    const root = path.join(lib, "snippets");
    const dirs = await readdir(root, { withFileTypes: true }).catch(() => []);
    for (const dir of dirs) {
      if (!dir.isDirectory()) continue;
      for (const f of await readdir(path.join(root, dir.name))) {
        if (f.endsWith(".luau")) files.push(path.join(root, dir.name, f));
      }
    }
  }
}

let indexText = "";
for (const lib of roots) {
  indexText += (await readFile(path.join(lib, "index.md"), "utf8").catch(() => "")) + "\n";
}
let failed = 0;
for (const file of files) {
  const r = await checkFile(file, indexText);
  if (r.problems.length === 0) {
    console.log(`OK   ${r.file.padEnd(28)} ${r.fields} réglages`);
  } else {
    failed++;
    console.log(`FAIL ${r.file.padEnd(28)} ${r.fields} réglages`);
    for (const p of r.problems) console.log(`       - ${p}`);
  }
}
console.log(failed === 0 ? `\n${files.length} prefab(s) conformes.` : `\n${failed} prefab(s) à corriger.`);
process.exit(failed === 0 ? 0 : 1);
