# Workflow de synchronisation upstream

> Notre stratégie : sync périodique avec cherry-pick à la demande, comme Cursor avec VSCode.

## Cadence recommandée

| Cadence | Justification |
|---|---|
| Mensuelle | Bon compromis entre "pas trop de boulot" et "pas trop de divergence accumulée" |
| Hebdomadaire | Si tu veux suivre de près une release upstream précise |
| Trimestrielle | Risqué : conflits potentiellement gros à résoudre |

> **Règle d'or** : sync mensuelle de 30 min >> sync trimestrielle de 8 heures.
> La douleur d'un sync croît plus vite que le délai (effet exponentiel).

## Procédure standard

### 1. Lance le check de divergence

```bash
./scripts/check-divergence.sh
```

Te dit, par sous-repo :
- Combien de commits tu as **en avance** (tes modifs)
- Combien de commits tu as **en retard** (chez upstream)
- Combien de fichiers diffèrent

### 2. Lance le sync interactif

```bash
./scripts/sync-upstream.sh
```

Pour chaque sous-repo, le script :
1. Fetch upstream
2. Affiche jusqu'à 30 commits upstream à intégrer
3. Te demande : merge / cherry-pick / skip

### 3. Décision : merge ou cherry-pick ?

| Situation | Choix |
|---|---|
| **Tu veux tout** ce qu'upstream a fait depuis le dernier sync | **Merge** |
| **Tu veux quelques fixes précis** mais pas tout | **Cherry-pick** des commits par SHA |
| **Tu veux skip cette release** (direction qui ne te plaît pas) | **Skip** |

### 4. Résoudre les conflits

Les conflits Git arrivent **uniquement** sur des lignes que tu as modifiées **et**
qui ont aussi été modifiées chez upstream. Stratégie :

```bash
# Pendant un merge bloqué :
cd packages/void-swarm-cli
git status                    # liste les fichiers en conflit
# Édite chaque fichier, choisis ce que tu veux garder
git add <fichier-résolu>
git commit                    # finalise le merge

# Si tout part en vrille :
git merge --abort             # annule le merge, retour à l'état pré-merge
```

### 5. Tester

Avant de pousser sur `origin`, **vérifie que ça compile et que les tests passent** :

```bash
# CLI :
cd packages/void-swarm-cli
bun install                   # peut être nécessaire si deps ont changé
bun run build                 # ou test selon ce qui est dispo
# Engine :
cd ../swarm-engine
pip install -e .              # idem si deps ont changé
pytest                        # si on a des tests à ce stade
```

### 6. Mettre à jour DIVERGENCE.md

À la racine du méta-projet, édite [`DIVERGENCE.md`](../DIVERGENCE.md) :

- Date de la sync
- Commit upstream synced (le SHA jusqu'où tu as remonté)
- Fichiers en conflit qu'il a fallu résoudre
- Toute modif structurelle nouvelle (un nouveau dossier, une refonte locale)

### 7. Pousser sur origin

```bash
cd packages/void-swarm-cli
git push origin dev    # ou la branche par défaut si différente
```

## Gérer les patches qui résistent au merge

Si une modif upstream casse sévèrement quelque chose chez nous :

### Option A : adapter notre code

Souvent c'est juste qu'upstream a renommé un symbole / refactoré. On adapte nos fichiers.
Documenter dans DIVERGENCE.md.

### Option B : revert le commit upstream localement

Si on n'aime vraiment pas un commit upstream :

```bash
git revert <sha-upstream>     # ajoute un commit qui annule celui-ci
```

À utiliser avec parcimonie : ça augmente la divergence.

### Option C : skip ce sync

Reste sur la version pré-sync, attends la prochaine release upstream qui aura peut-être
résolu le souci.

## Garder les modifs localisées

Pour éviter les conflits, **avant** de modifier un fichier upstream :

1. **Peut-on faire la modif dans un nouveau fichier ?** Souvent oui : on crée un module
   à côté qui fait notre boulot, on l'importe depuis le strict minimum dans upstream.
2. **Si non, peut-on isoler la modif sur 1-2 lignes ?** Préférer un appel à une fonction
   (qu'on définit chez nous) plutôt que d'inliner notre logique partout.
3. **La modif est-elle utile à upstream ?** Si oui, fais une **PR upstream** plutôt qu'un
   patch chez nous. Ça réduit notre divergence et c'est du karma open source.

## Ce qu'il NE faut PAS faire

- ❌ Faire des merges aveugles sans lire le diff upstream
- ❌ Skipper plusieurs syncs de suite (la divergence devient ingérable)
- ❌ Modifier des fichiers upstream sans le documenter dans DIVERGENCE.md
- ❌ Pousser une modif locale vers `upstream` (le script a retiré `origin` au clone
  pour t'éviter ça, mais reste vigilant)
- ❌ Forker un fichier upstream entier pour modifier 5 lignes — adapte plutôt en place

## Que faire si on diverge trop ?

Si à un moment tu vois que la sync devient régulièrement >1 jour, c'est le signe que :

- Soit ta divergence est devenue trop grande pour le retour sur investissement de la sync
- Soit upstream a refondu une partie qui te concerne en profondeur

Choix :
1. **Continuer à sync** mais accepter le coût et le documenter
2. **Couper le cordon** : tu hard-fork, plus de sync. Tu deviens seul responsable des bug
   fixes et du support nouveaux modèles. À ne faire qu'avec une équipe ou un budget.
3. **Repenser ta stratégie** : peut-être que ce que tu modifies serait mieux comme
   contribution upstream (PR) plutôt que comme fork local.
