---
name: HatInit
description: Initialise un nouveau projet de jeu Roblox en générant le Game Design Document (GDD.md) via un formulaire HTML local. À utiliser au tout début d'un nouveau projet Roblox, avant d'écrire la moindre ligne de code ou de définir l'architecture.
---

# HatInit

## Objectif

Poser les bases d'un nouveau projet de jeu Roblox en récupérant le contexte du jeu (genre, plateforme cible, mécaniques, monétisation...) sous forme d'un fichier `GDD.md` à la racine du projet, avant de démarrer l'architecture ou le code.

## Arguments

La commande accepte un argument optionnel : `/HatInit [fr|en]`

Pas de mode tutoriel ici : le formulaire est auto-explicatif (champs + bouton). L'onboarding plus large (connecter le protocole MCP à Roblox Studio, créer un projet Studio) est hors périmètre de HatInit — ça vit dans un skill séparé (ex: `HatConnect`).

## Étape 0 — Déterminer la langue

Avant toute chose, détermine la langue à utiliser pour cette exécution :

1. **Si un argument `fr` ou `en` est passé** : utilise-le pour cette exécution, puis écris-le dans le fichier `.lang` (à la racine de ce dossier de skill, `.claude/skills/HatInit/.lang`) — écrase le contenu précédent s'il existe. Ça mémorise le choix pour les prochaines fois.
2. **Sinon, si le fichier `.lang` existe déjà** : lis-le et utilise la langue qu'il contient.
3. **Sinon** (aucun argument, aucun fichier `.lang`) : utilise l'anglais par défaut.

Résultat concret : la première fois, sans argument, c'est en anglais. Si l'utilisateur tape `/HatInit fr` une seule fois, toutes les invocations suivantes (même sans argument) seront en français, jusqu'à ce qu'il retape `/HatInit en` pour repasser en anglais.

## Étape 1 — Vérifier l'existant

Avant toute chose, vérifie si un fichier `GDD.md` existe déjà à la racine du projet.

- **S'il existe déjà** : affiche un résumé très court de son contenu et demande à l'utilisateur s'il veut le régénérer (écraser) ou continuer avec l'existant. Ne jamais écraser sans confirmation explicite.
- **S'il n'existe pas** : passe à l'étape 2.

## Étape 2 — Ouvrir le formulaire

Le fichier `setup.html` (dans ce même dossier de skill) contient le formulaire à remplir pour générer le GDD.

Tente de l'ouvrir automatiquement dans le navigateur par défaut, en détectant l'OS avant de choisir la commande :

- macOS : `open setup.html`
- Windows : `start setup.html` (via `cmd /c start setup.html` si le shell l'exige)
- Linux : `xdg-open setup.html`

Si la commande échoue (erreur, commande introuvable, environnement sans interface graphique) : ne pas insister ni réessayer en boucle. Indique clairement le chemin absolu du fichier `setup.html` et demande à l'utilisateur de l'ouvrir lui-même.

Dans tous les cas, informe l'utilisateur avec le message court correspondant (voir "Messages exacts").

Puis **arrête-toi et attends.** Ne relance aucune vérification tant que l'utilisateur n'a pas répondu — ça évite de gaspiller des tours inutiles pendant qu'il remplit le formulaire.

## Étape 3 — Réception

Quand l'utilisateur répond "terminé" / "done" (ou équivalent) :

1. Vérifie que `GDD.md` existe bien à la racine du projet.
   - S'il n'existe pas : ne repars pas sur tout le formulaire, signale juste que le fichier est introuvable et demande où il a été enregistré.
2. Lis le contenu de `GDD.md`.
3. Fais un résumé très court (2-3 lignes) de ce qui a été compris, pour validation par l'utilisateur.
4. Ne commence aucun travail d'architecture ou de code à cette étape — HatInit s'arrête une fois le GDD confirmé.

## Notes

- Le formulaire est la source de vérité. Ne reformule pas toutes les questions du GDD en conversation si le formulaire a déjà été rempli — pas de double saisie.
- Ce skill doit rester sobre en sortie : messages courts, pas de récapitulatif de toutes les étapes à chaque fois qu'il est invoqué.

## Messages exacts (personnalisables)

Utilise ces formulations telles quelles, sans les reformuler ni les enrichir. Remplace uniquement le texte entre crochets `[...]` par le contenu réel. Choisis la langue selon l'argument reçu. Modifie ce fichier directement si tu veux changer le ton ou le texte.

---

### 1. GDD.md existe déjà

**FR :**
> Un GDD.md existe déjà pour ce projet. Je le régénère (écrase) ou je continue avec l'existant ?

**EN :**
> A GDD.md already exists for this project. Should I regenerate it (overwrite) or continue with the existing one?


---

### 2. Formulaire ouvert avec succès

**FR :**
> Initialisation lancée. Remplis le formulaire (setup.html) et enregistre GDD.md à la racine du projet. Dis "terminé" une fois fait.

**EN :**
> Initialization started. Fill out the form (setup.html) and save GDD.md at the root of the project. Say "done" once you're finished.


---

### 3. Échec de l'ouverture automatique

**FR :**
> Je n'ai pas pu ouvrir le formulaire automatiquement. Ouvre-le toi-même : [chemin absolu vers setup.html]. Remplis-le, enregistre GDD.md à la racine, puis dis "terminé".

**EN :**
> I couldn't open the form automatically. Open it yourself: [absolute path to setup.html]. Fill it out, save GDD.md at the root, then say "done".


---

### 4. GDD.md introuvable après "terminé"

**FR :**
> Je ne trouve pas GDD.md à la racine du projet. Tu l'as enregistré où ?

**EN :**
> I can't find GDD.md at the root of the project. Where did you save it?

---

### 5. GDD.md reçu et confirmé

**FR :**
> GDD.md reçu — [nom du jeu], [genre], [mode de jeu]. Prêt à passer à l'architecture.

**EN :**
> GDD.md received — [game name], [genre], [game mode]. Ready to move on to the architecture.
