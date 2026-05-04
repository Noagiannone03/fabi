# packages/

Ce dossier contient les **forks upstream** clonés. Chaque sous-dossier est un git repo
indépendant avec son propre historique et son propre remote `upstream`.

## Sous-dossiers

| Sous-dossier | Upstream | Licence | Statut |
|---|---|---|---|
| `void-swarm-cli/` | [sst/opencode](https://github.com/sst/opencode) | MIT | À cloner via `./scripts/setup.sh` |
| `swarm-engine/` | [GradientHQ/parallax](https://github.com/GradientHQ/parallax) | Apache 2.0 | À cloner via `./scripts/setup.sh` |

## Convention

- Le contenu des sous-dossiers est **ignoré par le `.gitignore` du méta-projet** (chaque sous-repo gère son propre git).
- Pour cloner ou re-cloner : `./scripts/setup.sh` à la racine du méta-projet.
- Pour synchroniser avec upstream : `./scripts/sync-upstream.sh`.

## Pourquoi pas de submodules ?

Les git submodules figent une référence à un commit précis et compliquent le workflow
cherry-pick. On préfère un setup simple où chaque sous-repo est un clone indépendant
qu'on synchronise à la main quand on veut.

C'est le même pattern que Cursor utilise vis-à-vis de VSCode upstream.
