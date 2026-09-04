---
name: HatLibrary
description: Réutilise les prefabs Luau déjà écrits de ~/HatLib/library (sprint, double-saut, UI simple...) au lieu de régénérer le code — copie sans lecture, puis réglage dans un configurateur visuel. À utiliser dès qu'une demande porte sur une fonctionnalité Roblox générique ("mets un sprint", "ajoute un double saut"), avant d'écrire du code.
---

# HatLibrary

L'utilisateur demande une fonctionnalité courante en langage naturel. Il ne doit rien avoir d'autre à
faire que **régler les options dans une page qui s'ouvre toute seule**. Le code du prefab ne passe
jamais par le contexte de Claude : ni à la copie, ni au réglage.

Deux dossiers à ne pas confondre : **ce skill** (`.claude/skills/HatLibrary/`, la logique + les
outils) et **la bibliothèque de contenu** (`~/HatLib/library/`, les `.luau` + `index.md`, hors du
projet de jeu, partagée via github.com/Haatmis/HatLib).
`~/HatLib/` absent → confirmation puis `git clone https://github.com/Haatmis/HatLib ~/HatLib`.
`~/HatLib/library/` absent → créer `index.md` + `snippets/` directement (local, non destructif).

## Le parcours — 3 appels d'outil, pas un de plus

### 1. Trouver

Le hook `UserPromptSubmit` (`hint.mjs`) annonce déjà le prefab correspondant dès que l'utilisateur
formule sa demande : si le hook a parlé, **passe directement à l'étape 2**. Sinon :

```bash
grep -i "sprint" ~/HatLib/library/index.md
```

Jamais de `cat` sur `index.md`, sauf demande explicite ("qu'est-ce qu'il y a dans la biblio ?").

### 2. Copier — sans lire le fichier

```bash
cp ~/HatLib/library/snippets/<categorie>/<Fichier>.luau <destination-dans-le-projet>
```

Destination usuelle en projet Rojo : `src/client/controllers/`, `src/server/`, `src/shared/`.
Si un `init.client.luau`/`init.server.luau` doit le charger, ajouter la ligne `require(...)` — c'est
la seule édition de code à faire à la main.

### 3. Ouvrir le configurateur — la page s'ouvre seule

```bash
node "<racine>/.claude/skills/HatLibrary/bridge.mjs" \
  --root "<racine du projet>" \
  --page "<racine>/.claude/skills/HatLibrary/configurator.html" \
  --file "src/client/controllers/SprintController.luau" \
  --open
```

Appel **normal**, surtout pas `run_in_background` : la commande se détache toute seule, rend la main
en une seconde et affiche `HATBRIDGE_URL=…` ; un lanceur de tâches en arrière-plan tuerait le pont
dès qu'il le croirait terminé. `bridge.mjs` est un serveur local sans dépendance (Node ≥ 18) qui
ouvre le navigateur lui-même, n'écoute que sur `127.0.0.1`, n'expose que `--root`, laisse la page
lire et réécrire le fichier ciblé (donc **rien à glisser-déposer ni à télécharger**), s'arrête seul
après 30 min d'inactivité ou au clic sur « Terminé », et réutilise le pont déjà ouvert s'il est
relancé sur le même projet. (`--foreground` pour déboguer sans détachement.)

Puis **stop, attends**. L'utilisateur coche les effets, bouge les curseurs, ça s'enregistre tout seul
dans le fichier (Rojo pousse la version à jour dans Studio). Il dit « terminé » quand c'est réglé.

**Si Node est absent** : ouvrir `configurator.html` directement (chemin absolu ; `Start-Process` sous
Windows, `open` sous macOS, `xdg-open` sous Linux) et demander le glisser-déposer du `.luau` dans la
page — l'ancien parcours, toujours supporté en secours.

### 4. Confirmer

Une ou deux lignes : ce qui a été copié, où, et le `require` ajouté le cas échéant. Ne relis pas le
fichier pour « vérifier » les valeurs — c'est du token dépensé pour rien.

## Si aucun prefab ne correspond

Écrire le code normalement. S'il est réutilisable (générique, pas spécifique à ce jeu), **proposer**
de l'ajouter à la bibliothèque — jamais sans confirmation. Si confirmé, lire
`reference/ajouter-un-prefab.md` (convention `⚙️ CONFIG`, annotations, entrée d'index avec `tags:`).

Ce même fichier couvre l'enrichissement d'un prefab existant et l'installation du hook dans un
nouveau projet. Inutile de le lire pour le parcours ci-dessus.
