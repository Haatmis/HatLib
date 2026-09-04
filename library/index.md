# HatLibrary — Index des prefabs

Une ligne par prefab, séparateurs en tirets cadratins (`—`) :

`` `nom-fichier.luau` — description courte — categorie/nom-fichier.luau — tags: mot1, mot2, mot3 ``

Les `tags` sont les mots que l'utilisateur risque d'employer en langage naturel
(FR + EN, au singulier). Ils servent au hook `hint.mjs`, qui repère tout seul qu'un
prefab existe pour une demande — sans eux, le prefab reste invisible à la détection auto.

<!-- Ajouter les nouvelles entrées ci-dessous, une par ligne. -->

`SprintController.luau` — sprint client : clavier/manette/tactile, FOV, animation, endurance + barre — movement/SprintController.luau — tags: sprint, sprinter, courir, course, run, running, vitesse, endurance, stamina, shift
`DashController.luau` — ruée directionnelle avec recharge : traînée, coup de FOV, son, mobile/manette — movement/DashController.luau — tags: dash, ruee, ruée, roulade, esquive, dodge, fonce, propulsion
`DoubleJumpController.luau` — sauts en l'air (double, triple...) avec anneau, son et animation — movement/DoubleJumpController.luau — tags: double saut, doublesaut, saut, sauter, jump, doublejump, triple saut, air
`PlayerDataService.luau` — profil joueur persistant (DataStore) : leaderstats, sauvegarde auto, réessais — systems/PlayerDataService.luau — tags: sauvegarde, sauvegarder, save, datastore, donnees, données, data, profil, leaderstats, monnaie, piece, pièce, coins, argent, progression, persistance
`RoundService.luau` — boucle de manches : entracte, timer, téléportation aux spawns, événements — systems/RoundService.luau — tags: manche, manches, round, rounds, partie, lobby, entracte, intermission, timer, minuteur, boucle de jeu
