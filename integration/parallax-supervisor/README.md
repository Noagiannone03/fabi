# parallax-supervisor

Module qui gère le cycle de vie du sous-process Parallax depuis le serveur void-swarm.

## Responsabilités

1. **Trouver l'exécutable Parallax** (selon l'install : binaire bundlé, pip-installé, dev mode)
2. **Spawn** : `parallax join -s <scheduler-url>`
3. **Forwarder les signaux** : SIGTERM/SIGINT du parent → Parallax
4. **Surveiller** : capturer stdout/stderr, parser le statut "joined", logger
5. **Restart avec backoff** si Parallax crashe avant exit normal
6. **Healthcheck** : ping le scheduler au boot pour avertir si le swarm est down

## API publique (envisagée)

```ts
import { startParallaxSupervisor, stopParallaxSupervisor } from "./index"

const supervisor = await startParallaxSupervisor({
  scheduler: "https://swarm.aircarto.fr",
  model:     "qwen-coder-32b",
  // optionnel
  binaryPath: undefined,    // auto-détecté
  vramLimit:  "auto",       // ou "12GB"
  onStatus:   (s) => console.log(s),
})

// plus tard
await stopParallaxSupervisor(supervisor)
```

## Implémentation (phase 2)

- TypeScript + Node `child_process`
- Tests : `vitest` ou `bun test`
- Process group sur Unix pour kill propre du worker même si void-swarm crashe

## Dépendances envisagées

- Aucune dépendance lourde — on vise du Node natif (`child_process`, `events`)
- Peut-être `pino` pour le logging si on veut un format JSON

## Fichiers

```
parallax-supervisor/
├── README.md           ← ce fichier
├── package.json        ← (à créer phase 2)
├── src/
│   ├── index.ts        ← API publique
│   ├── spawn.ts        ← logique spawn + signal forwarding
│   ├── healthcheck.ts  ← ping scheduler
│   └── restart.ts      ← backoff exponentiel
└── tests/
    └── spawn.test.ts
```
