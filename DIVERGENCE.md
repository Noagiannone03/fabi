# Divergence vs Upstream

Ce fichier documente toutes nos modifications par rapport aux projets upstream.
À mettre à jour à chaque modif structurante.

---

## packages/void-swarm-cli (fork de sst/opencode)

### Branche par défaut upstream

`dev` (chez sst/opencode). Notre clone a sa branche locale `dev` également.
La sync se fait toujours vers `upstream/dev`.

### Dernière sync upstream

- **Date** : 2026-05-04 (clone initial, équivalent à un sync à zéro)
- **Commit upstream** : `9f708e74` (chore: generate)

### Modifications par fichier

_Aucune modification pour l'instant. Les modifs commenceront en phase 2 (rebrand)._

### Nouveaux fichiers/dossiers ajoutés

_Aucun pour l'instant._

### Configuration ajoutée par défaut

_Aucune pour l'instant. Sera : config par défaut pointant sur scheduler Aircarto._

---

## packages/swarm-engine (fork de GradientHQ/parallax)

### Branche par défaut upstream

`main` (chez GradientHQ/parallax).

### Dernière sync upstream

- **Date** : 2026-05-04 (clone initial)
- **Commit upstream** : `c8c8ebda` (fix(sglang): preserve tie_word_embeddings for single-node runs)

### Modifications par fichier

_Aucune modification pour l'instant._

### Nouveaux fichiers/dossiers ajoutés

_Aucun pour l'instant._

---

## Code 100 % nous (jamais en conflit avec upstream)

| Chemin | Description |
|---|---|
| `integration/parallax-supervisor/` | Glue : spawn/stop Parallax depuis le serveur void-swarm |
| `integration/scheduler-config/` | Configuration du scheduler Aircarto (URL, modèles, auth) |
| `branding/` | ASCII art, thèmes, manifest de marque Void-Swarm |
| `docs/`, `scripts/`, fichiers racine `.md` | Docs & orchestration meta-projet |

---

## Convention de gestion des modifs

1. **Préférer ajouter un nouveau fichier** plutôt que modifier un fichier upstream
2. **Si modification d'un fichier upstream nécessaire** :
   - Garder la modif minimale (juste la ligne nécessaire)
   - Préférer un import depuis nos fichiers à nous
   - Documenter la modif ici dans la section appropriée
3. **Search/replace de strings "OpenCode" → "Void-Swarm"** : toléré dans les fichiers UI (TUI, banner, footer), pas dans les fichiers de code (imports, types, APIs)
4. Lors d'un sync upstream, vérifier ce fichier d'abord pour anticiper les conflits
