# integration/

Code d'intégration **propre à Fabi** — c'est ici que vit la glue entre
le CLI agentique (fork OpenCode) et le moteur d'inférence (fork Parallax).

Ce code est **100 % nous**. Il n'est jamais en conflit avec un sync upstream
parce qu'il vit hors des sous-repos forkés.

## Sous-modules

| Dossier | Rôle | Statut |
|---|---|---|
| [`fabi-launcher/`](./fabi-launcher/) | Le binaire `fabi` : healthcheck scheduler → spawn `parallax join` → exec opencode en foreground avec TTY hérité, cleanup propre à l'exit | ✅ |
| [`fabi-cli-config/`](./fabi-cli-config/) | `opencode.fabi.jsonc` : provider Fabi (scheduler Fabi, OpenAI-compatible) pré-baker, posé via `OPENCODE_CONFIG` au spawn | ✅ |

## Comment c'est branché côté `packages/fabi-cli/`

**Zéro patch source.** Tout passe par des points d'extension natifs d'opencode :

- **Spawn parallax** → fait dans le launcher externe (`fabi-launcher/src/parallax.ts`),
  jamais dans le code d'opencode.
- **Provider Fabi** → déclaré dans `fabi-cli-config/opencode.fabi.jsonc` et chargé
  via l'env var `OPENCODE_CONFIG` qu'opencode supporte officiellement
  (cf `packages/fabi-cli/packages/core/src/flag/flag.ts`).
- **TTY de la TUI** → `stdio: "inherit"` au spawn, opencode prend le contrôle.

Le diff vs upstream `sst/opencode` reste à 0. La sync upstream se fait sans
conflits.

## Tests

À implémenter en phase 2 :

- Le supervisor lance bien Parallax avec les bons args
- SIGTERM sur le parent → Parallax meurt aussi (process group)
- Restart auto si Parallax crashe (avec backoff)
- Healthcheck : ping le scheduler avant d'annoncer "join"
