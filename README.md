# HatLib

Chaîne d'outils pour développer des jeux **Roblox** avec Claude Code : des morceaux de code Luau déjà
écrits et réutilisables (sprint, double saut, sauvegarde des joueurs…), qu'on règle **dans une page
web avec des cases à cocher et des curseurs**, au lieu de les réécrire à chaque projet.

## Installation

Une seule commande :

```bash
git clone https://github.com/Haatmis/HatLib ~/.claude/skills/HatLib
```

**Puis redémarre Claude Code.** C'est nécessaire : Claude ne lit la liste des skills qu'au
démarrage, donc tant que tu n'as pas relancé, rien n'apparaît. Après le redémarrage, tout est actif —
rien à copier, aucun fichier de réglages à modifier.

Sous Windows, si `~` ne fonctionne pas dans ton terminal :

```powershell
git clone https://github.com/Haatmis/HatLib "$env:USERPROFILE\.claude\skills\HatLib"
```

Pour mettre à jour plus tard : `git -C ~/.claude/skills/HatLib pull`, puis redémarre à nouveau.

### Il te faut aussi

- **Node.js 18+** — pour la page de réglages et la détection automatique. Sans lui, tout marche
  encore, mais il faut glisser les fichiers dans la page à la main.
- **Rojo** — pour envoyer le code dans Roblox Studio. `HatInit` t'aide à l'installer.

## À quoi ça sert, concrètement

Tu dis à Claude : *« mets un sprint dans mon jeu »*.

1. Il repère tout seul qu'un sprint existe déjà dans la bibliothèque.
2. Il copie le fichier dans ton projet — sans jamais le lire, donc ça ne coûte presque rien.
3. Une page s'ouvre dans ton navigateur avec tous les réglages : touche, vitesse, champ de vision,
   animation, barre d'endurance, bouton mobile, manette…
4. Tu coches, tu bouges les curseurs. **Le fichier est réécrit sur ton disque au fur et à mesure**, et
   Rojo l'envoie dans Studio. Tu n'as rien à télécharger ni à déplacer.

## Ce qu'il y a dedans

| | |
|---|---|
| `skills/HatInit` | Crée le document de conception du jeu (GDD) via un formulaire, puis installe Rojo et connecte Roblox Studio. |
| `skills/HatLibrary` | Trouve, copie et règle les prefabs. Contient le pont local, la page de réglages et le vérificateur. |
| `library/` | Les prefabs eux-mêmes (`.luau`) et leur index. |

Prefabs disponibles : sprint, double saut, ruée (dash), sauvegarde des joueurs (DataStore), boucle de
manches. Chacun a entre 13 et 23 réglages cliquables.

## La page de réglages écrit sur mon disque — c'est prudent ?

Oui, et voilà exactement ce qui se passe. Un petit serveur local (`bridge.mjs`, sans aucune
dépendance) démarre le temps du réglage. Il :

- n'écoute que sur `127.0.0.1` — rien n'est accessible depuis l'extérieur de ta machine ;
- ne peut lire et écrire que **dans le dossier du projet** que tu lui as indiqué, jamais ailleurs ;
- s'arrête tout seul après 30 minutes sans activité, ou quand tu cliques sur « Terminé » ;
- n'envoie rien sur Internet.

C'est ce qui permet de supprimer le glisser-déposer et le téléchargement à replacer à la main.

## Ta propre bibliothèque

Les prefabs livrés ici sont mis à jour quand tu fais `git pull`. Pour les tiens, crée
`~/HatLib/library/` : elle est cherchée **en premier**, donc tes fichiers ne seront jamais écrasés
par une mise à jour, et tu peux même y remplacer un prefab livré par ta version.

## Licence

MIT.
