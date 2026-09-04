---
name: HatInit
description: Initialise un nouveau projet de jeu Roblox en générant le Game Design Document (GDD.md) via un formulaire HTML local. À utiliser au tout début d'un nouveau projet Roblox, avant d'écrire la moindre ligne de code ou de définir l'architecture.
---

# HatInit

## Objectif

Générer `GDD.md` (genre, plateforme, mécaniques, monétisation...) via formulaire HTML, puis enchaîner sur l'outillage technique (Rojo + MCP Roblox Studio).

## Arguments

`/HatInit [fr|en] [tutoriel|skip]` — optionnels, combinables. `fr`/`en` fixe la langue (étape 0). `tutoriel`/`skip` présélectionne le mode de l'étape 4, sans poser la question.

## Étape 0 — Langue

Priorité : argument `fr`/`en` reçu > fichier `.lang` existant (`.claude/skills/HatInit/.lang`) > anglais par défaut. Si argument reçu, écrase `.lang` (mémorisation pour les prochaines invocations).

## Étape 1 — GDD existant ?

Vérifie `GDD.md` à la racine.
- Existe : résumé très court + message "1" (régénérer ou continuer). Jamais d'écrasement sans confirmation.
- N'existe pas : étape 2.

## Étape 1bis — setup.html disponible ?

Normalement déjà présent (`.claude/skills/HatInit/setup.html`). Si absent :
1. `~/HatLib/` existe → copier `~/HatLib/skills/HatInit/setup.html` ici (`cp`, sans lecture).
2. `~/HatLib/` absent → demander confirmation (message "0", c'est un téléchargement).
   - Oui → `git clone https://github.com/Haatmis/HatLib ~/HatLib`, puis (1).
   - Non → message "0bis", attendre.

Ne vérifie ça que si `setup.html` manque réellement — jamais à chaque invocation.

## Étape 2 — Ouvrir le formulaire

**Voie normale — via le pont** (`bridge.mjs`, fourni par le skill `HatLibrary` ; nécessite Node ≥ 18).
Il vit dans le dossier `HatLibrary` **voisin de celui-ci** (`../HatLibrary/bridge.mjs`), que les
skills soient installés dans le projet ou par clone du dépôt. S'il existe, une seule commande — appel
**normal**, surtout pas `run_in_background` (le pont se détache tout seul et rend la main aussitôt) :

```bash
node "<dossier des skills>/HatLibrary/bridge.mjs" \
  --root "<racine du projet>" \
  --page "<dossier des skills>/HatInit/setup.html" \
  --open
```

Le pont ouvre le navigateur lui-même et laisse la page **écrire `GDD.md` directement à la racine du
projet** : plus de téléchargement à déplacer à la main, plus de commande d'ouverture spécifique à
l'OS, plus de doute sur « est-ce que la fenêtre s'est ouverte ». Puis message "2".

**Secours — sans Node, ou si `bridge.mjs` est absent.** Ouvrir `setup.html` (chemin absolu, entre
guillemets) selon l'OS :
- macOS : Bash, `open "<chemin>"`
- Windows : **PowerShell** (pas Bash/Git Bash — `cmd /c start` y échoue souvent silencieusement à cause du quoting MSYS), `Start-Process "<chemin>"`
- Linux : Bash, `xdg-open "<chemin>"`

Code de sortie 0 ≠ fenêtre réellement ouverte (terminal intégré, permissions). N'affirme jamais que
c'est ouvert avec certitude — message "2bis" (donne le chemin dans tous les cas) couvre les deux issues.

Dans les deux cas : **stop, attends la réponse** — pas de vérification proactive.

## Étape 3 — Réception

Sur "terminé"/"done" :
1. `GDD.md` absent → ne relance pas le formulaire, message "3" (demande où il a été sauvé).
2. Présent → lis-le, puis message "4" (résumé pour validation).
3. Enchaîne directement sur l'étape 4 (pas d'archi/code ici).

## Étape 4 — Outillage (Rojo + MCP)

Sauf argument `tutoriel`/`skip` déjà fourni, message "5" et attends la réponse.
- **Tutoriel** : 1-2 phrases avant chaque action ci-dessous, confirmation avant exécution.
- **Skip** : exécute directement, ne t'arrête que pour les installs (confirmation obligatoire).

### 4.1 Rojo

1. `rojo --version` → installé : indique la version, passe à 2. Absent : propose Aftman (confirmation requise avant d'installer) :
   - Windows : `winget install LPGhatguy.aftman` puis `aftman add rojo-rbx/rojo`
   - macOS : `brew install rojo-rbx/rojo/rojo` (ou `brew install aftman` + `aftman add rojo-rbx/rojo`)
   - Linux : `cargo install aftman` + `aftman add rojo-rbx/rojo`, ou binaire des releases GitHub `rojo-rbx/rojo`
2. `default.project.json` présent à la racine → rien à faire. Absent → `rojo init`.

### 4.2 MCP Roblox Studio

Roblox Studio expose lui-même un serveur MCP (Paramètres de l'assistant → Serveurs MCP → "Activer Studio comme serveur MCP"). Le connecter à Claude Code CLI, par OS :

- **Windows** (validé) :
  ```
  MSYS_NO_PATHCONV=1 claude mcp add --transport stdio Roblox_Studio -- "cmd.exe" "/c" "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"
  ```
  Le préfixe `MSYS_NO_PATHCONV=1` est obligatoire (outil Bash = Git Bash) : sans lui, la conversion automatique des chemins MSYS réécrit le flag `/c` en `C:/`, et la connexion time out. Vérifier avec `claude mcp get Roblox_Studio` (`Status: ✔ Connected`, `Args: /c cd /d ...`) ; si `Args` contient `C:/` au lieu de `/c`, `claude mcp remove Roblox_Studio -s local` puis réessayer.
- **macOS/Linux** : pas encore de commande validée. Utilise le message "6" pour demander à l'utilisateur la commande exacte fournie par le panneau MCP de Studio sur sa machine, exécute-la, puis vérifie avec `claude mcp get Roblox_Studio`.

Ne jamais fabriquer une commande/URL non confirmée pour macOS/Linux.

### 4.3 Fin

Rojo + MCP en place (ou MCP en attente d'info) → message "7".

## Étape 5 — Réutilisation de code

Le projet est prêt : à partir d'ici, toute fonctionnalité générique (sprint, double-saut, UI simple…)
passe par le skill `HatLibrary` — prefab copié puis réglé visuellement — avant d'écrire du code neuf.

## Notes

- Le formulaire est la source de vérité du GDD ; ne reformule pas ses questions en conversation.
- Toute install/téléchargement (winget/brew/aftman/cargo/git clone) = confirmation explicite avant.
- Le pont (`bridge.mjs`) n'écoute que sur `127.0.0.1`, n'expose que le dossier du projet, et s'arrête
  seul (30 min d'inactivité, ou dès que le formulaire est validé). Rien à nettoyer à la main.
- **Tout ce qui s'installe par clone ou ajout (skills HatLib, serveur MCP) n'est visible qu'au
  redémarrage suivant de Claude Code.** Le dire explicitement à chaque fois (message "8") : sans ça
  l'utilisateur croit que c'est cassé et recommence l'installation. Ne jamais laisser deviner.
- Sortie sobre en toute circonstance, y compris en tutoriel : phrases courtes, pas de récap d'étapes.

## Messages exacts (personnalisables)

Utilise-les tels quels, sans reformuler. `[...]` = contenu réel à insérer. Langue selon l'étape 0.

---

### 0. Clonage nécessaire (setup.html absent)

**FR :**
> Le formulaire (setup.html) n'est pas présent localement. Je dois cloner le dépôt HatLib (github.com/Haatmis/HatLib) dans ton dossier utilisateur pour le récupérer. OK pour continuer ?

**EN :**
> The form (setup.html) isn't present locally. I need to clone the HatLib repo (github.com/Haatmis/HatLib) into your user folder to get it. OK to proceed?

---

### 0bis. Clonage refusé

**FR :**
> D'accord, pas de clonage. Dépose `setup.html` manuellement dans : [chemin absolu attendu]. Puis relance `/HatInit`.

**EN :**
> OK, no cloning. Drop `setup.html` manually into: [expected absolute path]. Then re-run `/HatInit`.

---

### 1. GDD.md existe déjà

**FR :**
> Un GDD.md existe déjà pour ce projet. Je le régénère (écrase) ou je continue avec l'existant ?

**EN :**
> A GDD.md already exists for this project. Should I regenerate it (overwrite) or continue with the existing one?

---

### 2. Formulaire ouvert (voie normale, via le pont)

**FR :**
> Le formulaire vient de s'ouvrir dans ton navigateur. Remplis-le et valide : le GDD est écrit directement à la racine du projet. Dis-moi "terminé" ensuite.

**EN :**
> The form just opened in your browser. Fill it in and submit: the GDD is written straight to the project root. Say "done" when you're through.

---

### 2bis. Formulaire lancé (secours, sans pont)

**FR :**
> Formulaire lancé (setup.html). S'il ne s'est pas ouvert automatiquement, ouvre-le toi-même : [chemin absolu vers setup.html]. Remplis-le, enregistre GDD.md à la racine du projet, puis dis "terminé".

**EN :**
> Form launched (setup.html). If it didn't open automatically, open it yourself: [absolute path to setup.html]. Fill it out, save GDD.md at the root of the project, then say "done".

---

### 3. GDD.md introuvable après "terminé"

**FR :**
> Je ne trouve pas GDD.md à la racine du projet. Tu l'as enregistré où ?

**EN :**
> I can't find GDD.md at the root of the project. Where did you save it?

---

### 4. GDD.md reçu et confirmé

**FR :**
> GDD.md reçu — [nom du jeu], [genre], [mode de jeu]. Prêt à passer à l'architecture.

**EN :**
> GDD.md received — [game name], [genre], [game mode]. Ready to move on to the architecture.

---

### 5. Tutoriel ou skip

**FR :**
> Passons à l'outillage (Rojo + MCP). Tutoriel (explications à chaque étape) ou skip (direct) ?

**EN :**
> Now the tooling (Rojo + MCP). Tutorial (explained step by step) or skip (straight through)?

---

### 6. MCP non trouvé (macOS/Linux)

**FR :**
> Pas de commande MCP validée pour ton OS. Ouvre Studio → Paramètres de l'assistant → Serveurs MCP, et colle-moi la commande "Claude Code CLI" affichée là-bas.

**EN :**
> No validated MCP command for your OS yet. Open Studio → Assistant Settings → MCP Servers, and paste me the "Claude Code CLI" command shown there.

---

### 7. Prêt

**FR :**
> Rojo initialisé, MCP connecté. Environnement prêt pour le code.

**EN :**
> Rojo initialized, MCP connected. Environment ready for code.

---

### 8. Redémarrage nécessaire après une installation

**FR :**
> [ce qui vient d'être installé] est en place. Il faut **redémarrer Claude Code** pour que ce soit pris en compte — c'est normal, la liste n'est lue qu'au démarrage. Relance, puis on continue.

**EN :**
> [what was just installed] is in place. You need to **restart Claude Code** for it to be picked up — that's expected, the list is only read at startup. Restart, then we'll carry on.
