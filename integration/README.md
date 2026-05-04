# integration/

Code d'intégration **propre à Void-Swarm** — c'est ici que vit la glue entre
le CLI agentique (fork OpenCode) et le moteur d'inférence (fork Parallax).

Ce code est **100 % nous**. Il n'est jamais en conflit avec un sync upstream
parce qu'il vit hors des sous-repos forkés.

## Sous-modules

| Dossier | Rôle | Statut |
|---|---|---|
| [`parallax-supervisor/`](./parallax-supervisor/) | Spawn / supervise / kill le sous-process Parallax depuis le serveur void-swarm | 🚧 stub |
| [`scheduler-config/`](./scheduler-config/) | Config par défaut pointant sur le scheduler Aircarto (URL, modèles, headers) | 🚧 stub |

## Comment c'est branché côté `packages/void-swarm-cli/`

Une seule ligne ajoutée dans le boot du serveur OpenCode forké, qui importe
le supervisor :

```ts
// dans packages/void-swarm-cli/packages/opencode/src/server/boot.ts (à confirmer)
import { startParallaxSupervisor } from "../../../../integration/parallax-supervisor"
import { voidSwarmDefaults } from "../../../../integration/scheduler-config"

// au boot, juste avant de démarrer l'écoute HTTP
await startParallaxSupervisor({ scheduler: voidSwarmDefaults.schedulerUrl })
```

Tout le reste de la logique (spawn, kill, restart, healthcheck) est dans
`integration/` et n'apparaît jamais dans le diff vs upstream OpenCode.

## Tests

À implémenter en phase 2 :

- Le supervisor lance bien Parallax avec les bons args
- SIGTERM sur le parent → Parallax meurt aussi (process group)
- Restart auto si Parallax crashe (avec backoff)
- Healthcheck : ping le scheduler avant d'annoncer "join"
