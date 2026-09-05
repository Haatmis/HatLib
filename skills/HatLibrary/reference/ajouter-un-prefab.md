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
  libellé : `min..max`, `options: A|B|C`, `si: AUTRE_OPTION`, `requiert: cat/Service.luau`.
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
| `-- si: MODE = A\|B` | … que si `MODE` vaut A ou B (aussi `!=`, `>`, `<`, `>=`, `<=`) |
| `-- requiert: cat/Service.luau` | cocher l'option pose ce service dans le projet (voir plus bas) |
| nom en `*_ANCHOR` à 9 `options:` | grille d'ancrage 3×3 au lieu d'un menu déroulant |
| `-- 🎬 APERÇU: famille/scenario` | aperçu animé au-dessus des réglages (voir plus bas) |
| autre expression Luau | champ texte brut (secours) |

Seules les lignes du bloc CONFIG sont réécrites ; le reste du fichier est recopié à l'identique.

### Aperçu animé

Un prefab peut demander une scène 3D qui joue son comportement en direct, réglages compris : une
ligne dans le bloc CONFIG suffit.

```lua
-- ⚙️ CONFIG
-- 🎬 APERÇU: movement/sprint
```

La **famille** désigne le module chargé (`preview-movement.js`, à côté de `configurator.html`), le
**scénario** ce qu'il joue. Existants : `movement/sprint`, `movement/dash`, `movement/jump`, `stamina/hud`. La
caméra suit le personnage (Côté / Dos / Face / Isométrique, glisser pour tourner, molette pour
zoomer) et le module relit les valeurs à chaque image — bouger un curseur change l'animation
immédiatement.

Sans annotation, ou si le module est absent, la page reste exactement celle d'avant : l'aperçu est
un bonus, jamais une dépendance. Une nouvelle famille = un nouveau `preview-<famille>.js` exportant
`cameras` et `mount(canvas, api)` ; le cœur du configurateur n'est pas à toucher.

### Ressource partagée : `requiert:`

Une option qui porte sur une **variable susceptible d'être globale** — l'endurance, la monnaie, la
vie, l'inventaire — ne doit pas créer une jauge privée au prefab : deux consommateurs, et on se
retrouve avec deux jauges indépendantes et deux affichages. Elle doit **poser le service** qui tient
la ressource.

```lua
local ENABLE_STAMINA = false -- le sprint dépense l'endurance, requiert: systems/StaminaService.luau
```

À la coche, le configurateur copie `snippets/systems/StaminaService.luau` vers
`src/shared/StaminaService.luau`, ajoute son `require` dans `init.server.luau` et
`init.client.luau`, et ouvre un onglet pour le régler. **Si le fichier existe déjà, il n'est jamais
écrasé** : on ouvre seulement son onglet. Décocher ne supprime rien — un autre prefab s'en sert
peut-être déjà.

Conséquence sur le découpage des réglages : le service porte la ressource (maximum,
régénération, affichage), le prefab consommateur ne garde que **son coût**. Deux sources de
vérité sur la même valeur, c'est un configurateur qui ment.

Critère pour trier : promouvable si plusieurs fonctionnalités voudront la lire ou la dépenser ;
locale si c'est un effet propre au prefab (FOV, durée de tween, id d'animation, touche).

**Limite volontaire** : le configurateur règle des *valeurs*, pas de la logique. Une fonctionnalité
qui n'existe pas encore s'écrit une fois en code, derrière un `ENABLE_X`, et devient pilotable
visuellement pour toujours.

## Vérifier le prefab — obligatoire avant de l'ajouter à l'index

```bash
node .claude/skills/HatLibrary/check.mjs ~/HatLib/library/snippets/<cat>/<Nom>.luau
node .claude/skills/HatLibrary/check.mjs --all      # toute la bibliothèque
```

Il contrôle : blocs Luau ouverts/fermés (`end` manquant ou en trop), bloc CONFIG lisible par le
**parseur réel du configurateur**, `si:` qui pointe sur une option existante et compatible avec son
opérateur, `requiert:` bien formé, valeur présente dans ses
`options:`, nombre dans ses bornes `min..max`, aller-retour d'écriture neutre, `return` final, et
entrée d'index avec `tags:`. Sortie non nulle si un prefab échoue.

Ce n'est **pas** un interpréteur Luau : il ne voit ni les fautes de logique, ni les mauvais appels
d'API Roblox. Un test en jeu reste nécessaire.

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
