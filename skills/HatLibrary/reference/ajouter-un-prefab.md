# Ajouter / modifier un prefab HatLibrary

À lire **uniquement** quand tu écris un nouveau prefab, que tu enrichis un prefab existant,
ou que tu installes le hook dans un nouveau projet. Le parcours courant (chercher → copier →
configurer) n'a pas besoin de ce fichier.

## Convention de prefab

```lua
--[[
	NomDuPrefab — une ligne sur ce que ça fait.
	Placement : src/client/controllers/ (ModuleScript `require`) ou StarterPlayerScripts (LocalScript).
]]

-- ⚙️ CONFIG
-- ▸ Base
local SPRINT_KEY = Enum.KeyCode.LeftShift -- touche de sprint au clavier
local SPRINT_MODE = "Hold" -- maintien ou bascule, options: Hold|Toggle
local SPRINT_SPEED = 24 -- vitesse en sprint, 8..80
-- ▸ Caméra
local ENABLE_FOV = true -- élargit le champ de vision pendant le sprint
local FOV_BOOST = 12 -- degrés de FOV ajoutés, si: ENABLE_FOV, 0..40
-- ⚙️ FIN CONFIG

-- (logique en dessous, jamais mélangée à la config)

return true
```

Règles :

- Le bloc va de `⚙️ CONFIG` à `⚙️ FIN CONFIG`. Avec le marqueur de fin, lignes vides, sections `-- ▸`
  et commentaires libres sont autorisés dedans. Sans marqueur (ancien format), le bloc s'arrête à la
  première ligne vide.
- Le commentaire de fin de ligne sert de libellé affiché. Il peut porter des annotations, retirées du
  libellé : `min..max`, `options: A|B|C`, `si: AUTRE_OPTION`.
- Chaque effet optionnel derrière un `ENABLE_X`, **désactivé par défaut s'il exige un asset**
  (id d'animation, son) — sinon le prefab casse à la copie.
- Terminer par `return true` : valide en ModuleScript comme en LocalScript.
- Le prefab doit survivre à un respawn (`Player.CharacterAdded`) et ne rien casser si son effet est
  désactivé.

## Contrôles générés par le configurateur

| Dans le code | Contrôle affiché |
|---|---|
| `true` / `false` | interrupteur |
| `Enum.KeyCode.X` | menu de touches (clavier + manette) |
| nombre | curseur + champ (bornes lues dans `-- min..max`, sinon heuristique) |
| `"#RRGGBB"` | sélecteur de couleur |
| `"texte"` | champ texte |
| `-- options: A\|B\|C` | menu déroulant |
| `-- ▸ Titre` | titre de section |
| `-- si: ENABLE_X` | l'option n'apparaît que si `ENABLE_X` est coché |
| autre expression Luau | champ texte brut (secours) |

Seules les lignes du bloc CONFIG sont réécrites ; le reste du fichier est recopié à l'identique.

**Limite volontaire** : le configurateur règle des *valeurs*, pas de la logique. Une fonctionnalité
qui n'existe pas encore s'écrit une fois en code, derrière un `ENABLE_X`, et devient pilotable
visuellement pour toujours.

## Enregistrer le prefab dans la bibliothèque

1. Fichier dans `~/HatLib/library/snippets/<categorie>/<Nom>.luau`.
2. Une ligne dans `~/HatLib/library/index.md` :

   `` `Nom.luau` — description courte — categorie/Nom.luau — tags: mot1, mot2, mot3 ``

   Les `tags` sont les mots que l'utilisateur emploiera vraiment (FR + EN, au singulier).
   **Sans tags, le hook ne retrouvera jamais le prefab** et il restera invisible.

## Installer le hook de détection dans un projet

`hint.mjs` (hook `UserPromptSubmit`) compare les mots de chaque message aux `tags:` de `index.md` et
n'écrit une ligne **que s'il y a correspondance** — 0 octet le reste du temps, et rien sur les
notifications système. Dans `.claude/settings.json` du projet :

```json
{ "hooks": { "UserPromptSubmit": [ { "hooks": [
  { "type": "command", "command": "node \".claude/skills/HatLibrary/hint.mjs\"" }
] } ] } }
```

Sans lui (ou sans Node), rien ne casse : la détection repose alors sur la description du skill et sur
le `grep` de l'index.

## Limites connues du skill

- Pas de `git pull` automatique de `~/HatLib/library/` — la mise à jour reste explicite.
- Pas de découpage d'`index.md` par catégorie — prématuré tant que la bibliothèque est petite.
