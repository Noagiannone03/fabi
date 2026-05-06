# Divergence vs Upstream

Ce fichier documente toutes nos modifications par rapport aux projets upstream.
À mettre à jour à chaque modif structurante.

---

## packages/fabi-cli (fork de sst/opencode)

### Branche par défaut upstream

`dev` (chez sst/opencode). Notre clone a sa branche locale `dev` également.
La sync se fait toujours vers `upstream/dev`.

### Dernière sync upstream

- **Date** : 2026-05-05 (re-clone propre suite à transfert tronqué — voir note plus bas)
- **Commit upstream** : `301ab3615` (chore: update nix node_modules hashes)

### Modifications par fichier

#### Coupe SaaS/desktop (2026-05-05)

`git rm -rf` des packages hors scope CLI/TUI : `app`, `console`, `desktop`,
`docs`, `enterprise`, `extensions`, `function`, `identity`, `slack`,
`storybook`, `ui`, `web` (12 dossiers, ~3340 fichiers).

#### Modifs upstream (2026-05-05)

| Fichier | Modif |
|---|---|
| `package.json` (root du fork) | `name: "opencode"` → `"fabi"`, suppression scripts `dev:desktop/web/console/storybook/random/hello`, workspaces réduits à `packages/*` + `packages/sdk/js` |
| `turbo.json` | suppression tâches `@opencode-ai/app#test*`, `@opencode-ai/ui#test*` |
| `packages/opencode/package.json` | `bin` ajoute alias `"fabi"` à côté de `"opencode"` |
| `packages/opencode/bin/opencode` | message d'erreur "opencode CLI" → "fabi CLI" |
| `packages/opencode/src/index.ts` | imports Swarm, options yargs (`--no-parallax`, `--scheduler`, `--scheduler-peer`, `--swarm-verbose`), 2e middleware (boot swarm), `printSwarmEvent` helper, env `FABI`/`FABI_PID`, `scriptName("fabi")`, sync exit handler, finally async swarm shutdown |
| `packages/opencode/src/config/config.ts` | import Swarm helpers, `fabiBaseConfig()` injecté comme première couche dans `loadInstanceState` (provider Fabi pré-baké, modèle Qwen3-Coder-30B par défaut) |
| `packages/opencode/src/cli/ui.ts` | wordmark FABI ASCII art (depuis `branding/ascii-banner.txt`), `logo()` simplifié avec couleur sunset `#FF8C42`, suppression import `glyphs` (le fichier `cli/logo.ts` reste pour `cli/cmd/tui/component/logo.tsx`) |

### Nouveaux fichiers/dossiers ajoutés

| Chemin | Rôle |
|---|---|
| `packages/opencode/src/swarm/defaults.ts` | constantes URL scheduler, peer ID, modèle, timeouts |
| `packages/opencode/src/swarm/scheduler.ts` | healthcheck `/cluster/status_json` (jamais bloquant) |
| `packages/opencode/src/swarm/worker.ts` | spawn / stop / killSync du worker `parallax join -s` (process group, SIGTERM puis SIGKILL après grace period) |
| `packages/opencode/src/swarm/provider-defaults.ts` | objet provider Fabi (npm `@ai-sdk/openai-compatible`, api `<scheduler>/v1`, modèle Qwen) |
| `packages/opencode/src/swarm/lifecycle.ts` | orchestration : décide quelles commandes triggent le swarm, attache signal handlers, expose `startSwarm` / `shutdownActive` / `shutdownActiveSync`. **(v0.2.0)** Appelle le registry au démarrage via `resolveFromRegistry` pour résoudre dynamiquement scheduler URL + peer ID |
| `packages/opencode/src/swarm/index.ts` | barrel export du module |
| `packages/opencode/src/swarm/registry.ts` | **(v0.2.0)** client du fabi-registry, expose `discoverSwarm()` et `fetchRegistrySwarms()`. Logique de matching par id ou par modèle, avec fallback gracieux si registry injoignable |
| `packages/opencode/src/swarm/registry.test.ts` | **(v0.2.0)** tests unitaires (9) sur la sélection de swarms |
| `packages/opencode/src/cli/cmd/swarms.ts` | **(v0.2.0)** commande `fabi swarms` qui liste les swarms (table colorée ou `--json`) |

### Configuration ajoutée par défaut

Le provider `fabi` (scheduler Fabi, OpenAI-compatible) et le modèle
`fabi/Qwen/Qwen3-Coder-30B-A3B-Instruct` sont pré-bakés dans la config.
Surchargeables par config user (`~/.config/opencode/opencode.json`),
`OPENCODE_CONFIG`, et flags CLI (`--scheduler`, `--scheduler-peer`,
`--no-parallax`).

### Philosophie "tu codes = tu contribues" — appliquée au boot (2026-05-05)

**Pas de mode consumer-only en usage normal.** Si Parallax n'est pas installé
et que `--no-parallax` n'est pas passé explicitement, `fabi` exit avec
`SwarmWorkerRequiredError` (code 1) et affiche un message expliquant la
philosophie + les steps d'install. Le flag `--no-parallax` reste possible
pour les contributeurs du fork (dev/test de la TUI sans installer Python),
avec un warning explicite "mode dev, pas pour usage normal".

Implémentation : `swarm/lifecycle.ts` throw `SwarmWorkerRequiredError` quand
le worker n'a pas pu spawn ; `index.ts` middleware catch et appelle
`printParallaxRequiredMessage()` puis `process.exit(1)`.

**Why** : empêche le free-riding. Si tout le monde consomme et personne ne
contribue, le swarm meurt. C'est explicité par Paul : *"je veux qu'il ne
puisse utiliser fabi que s'il est worker, en gros il consomme donc il est
worker aussi"*.

### Status `integration/fabi-launcher` et `integration/fabi-cli-config`

**Obsolètes après l'intégration native** : la logique du launcher externe
(spawn parallax + healthcheck + signal handling) a été migrée dans
`packages/opencode/src/swarm/`. La config `opencode.fabi.jsonc` est
désormais en TS dans `swarm/provider-defaults.ts`. Les deux dossiers
restent pour référence/comparaison ; à supprimer plus tard.

### Note 2026-05-05 — Re-clone propre

Le clone initial du 2026-05-04 a été corrompu lors du transfert du projet
(zip tronqué à 2 MB max par fichier → pack files git de fabi-cli et
swarm-engine illisibles). Repos re-clonés depuis upstream le 2026-05-05.
Aucune modification n'avait encore été commit sur les forks à ce moment, donc
aucune perte de travail Fabi.

---

## packages/swarm-engine (fork de GradientHQ/parallax)

### Branche par défaut upstream

`main` (chez GradientHQ/parallax).

### Dernière sync upstream

- **Date** : 2026-05-05 (re-clone propre, identique au commit du 2026-05-04)
- **Commit upstream** : `c8c8ebda` (fix(sglang): preserve tie_word_embeddings for single-node runs)

### Modifications par fichier

_Aucune modification pour l'instant._

### Nouveaux fichiers/dossiers ajoutés

_Aucun pour l'instant._

---

## Code 100 % nous (jamais en conflit avec upstream)

| Chemin | Description |
|---|---|
| `integration/fabi-launcher/` | Le binaire `fabi` : orchestre healthcheck + spawn parallax + exec fabi-cli en foreground. Remplace l'ancienne idée de `parallax-supervisor` côté serveur OpenCode (launcher externe = aucun diff vs upstream) |
| `integration/fabi-cli-config/` | `opencode.fabi.jsonc` : déclare le provider Fabi (scheduler Fabi, `@ai-sdk/openai-compatible`) et le pose comme modèle par défaut. Chargé via l'env `OPENCODE_CONFIG` qu'opencode supporte officiellement → zéro patch source |
| `branding/` | ASCII art, thèmes, manifest de marque Fabi |
| `docs/`, `scripts/`, fichiers racine `.md` | Docs & orchestration meta-projet |

---

## Convention de gestion des modifs

1. **Préférer ajouter un nouveau fichier** plutôt que modifier un fichier upstream
2. **Si modification d'un fichier upstream nécessaire** :
   - Garder la modif minimale (juste la ligne nécessaire)
   - Préférer un import depuis nos fichiers à nous
   - Documenter la modif ici dans la section appropriée
3. **Search/replace de strings "OpenCode" → "Fabi"** : toléré dans les fichiers UI (TUI, banner, footer), pas dans les fichiers de code (imports, types, APIs)
4. Lors d'un sync upstream, vérifier ce fichier d'abord pour anticiper les conflits
