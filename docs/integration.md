# Intégration fabi-cli ↔ swarm-engine

Comment le CLI agentique et le moteur d'inférence sont câblés ensemble.

## Vue logique

```
                   ┌──────────────────────────────────┐
                   │  Utilisateur tape `fabi`   │
                   └────────────────┬─────────────────┘
                                    │
                                    ▼
   ┌─────────────────────────────────────────────────────────┐
   │  Process #1 : fabi (Bun/TS, ex-OpenCode)          │
   │                                                         │
   │  boot()                                                 │
   │   ├─► resolveSchedulerConfig()  ← integration/...       │
   │   ├─► startParallaxSupervisor()  ← integration/...      │
   │   │     │                                                │
   │   │     └─spawn─► [Process #2 : parallax (Python)]      │
   │   │                                                      │
   │   └─► startHTTPServer(:7777)                             │
   │                                                          │
   │  events                                                  │
   │   - SIGTERM/SIGINT → handle d'arrêt :                    │
   │       stopParallaxSupervisor() (kill propre)             │
   │       puis exit                                          │
   └─────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                  ┌─────────────────────────────────┐
                  │  Process #2 : parallax worker    │
                  │  (Python subprocess)             │
                  │                                  │
                  │  - rejoint le scheduler Aircarto │
                  │  - héberge des couches du modèle │
                  │  - communique P2P avec autres   │
                  │    peers via Lattica/libp2p     │
                  └──────────────────────────────────┘
```

## Points d'intégration concrets

### 1. Au boot du serveur OpenCode forké

Trouver le point d'entrée du serveur OpenCode (dans `packages/fabi-cli/`,
probablement quelque chose comme `packages/opencode/src/server/serve.ts` ou
`packages/opencode/src/cli/index.ts` — à confirmer en explorant le repo).

**Modif minimaliste** : juste avant `startHTTPServer()`, ajouter :

```ts
import { startParallaxSupervisor } from "../../../../integration/parallax-supervisor"
import { resolveSchedulerConfig } from "../../../../integration/scheduler-config"

const cfg = await resolveSchedulerConfig({ argv: process.argv })
const supervisor = await startParallaxSupervisor({
  scheduler: cfg.schedulerUrl,
  model:     cfg.defaultModel,
  onStatus:  (s) => console.log(`[swarm] ${JSON.stringify(s)}`),
})

// branchement de l'arrêt propre
process.on("SIGTERM", async () => {
  await supervisor.stop()
  process.exit(0)
})
process.on("SIGINT", async () => {
  await supervisor.stop()
  process.exit(0)
})
```

### 2. Provider OpenAI-compatible "Fabi"

Plutôt que modifier le code source, **on précharge un fichier `opencode.json`** au
premier lancement de fabi dans `~/.config/opencode/` (ou équivalent) :

```json
{
  "provider": {
    "fabi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Fabi Network",
      "options": {
        "baseURL": "https://fabi.aircarto.fr/v1"
      },
      "models": {
        "qwen-coder-32b": { "name": "Qwen Coder 32B (Aircarto)" }
      }
    }
  },
  "defaultProvider": "fabi",
  "defaultModel":    "qwen-coder-32b",
  "theme":           "fabi"
}
```

Cette config :
- Pointe sur notre scheduler Aircarto
- Définit le provider par défaut
- Active notre thème `fabi` (préinstallé via le branding/)

### 3. Process group pour kill propre

Sur Unix, on lance Parallax dans un nouveau process group. Comme ça, si fabi crashe
violemment (`kill -9`), le worker Parallax meurt aussi via la propagation de SIGHUP
au process group.

Implémentation côté `parallax-supervisor` :

```ts
const child = spawn("parallax", ["join", "-s", scheduler], {
  stdio: ["ignore", "pipe", "pipe"],
  detached: false,            // garde-le dans notre group, pas en daemon
  // sur Linux, on peut explicitement créer un nouveau pgid via setpgid
})
```

### 4. Healthcheck avant join

Avant de spawn Parallax, on ping le scheduler pour vérifier qu'il est joignable.
Si scheduler down :
- Mode dégradé : fabi démarre quand même mais affiche un warning
- Le user peut quand même utiliser le CLI avec un autre provider (OpenAI direct, Ollama)
- Logué dans `~/.local/share/fabi/log/` pour debug

### 5. Communication TUI → user

Quand le worker Parallax se connecte au swarm, on émet un event que la TUI affiche :

```
✓ Fabi connecté
  ├─ scheduler : fabi.aircarto.fr (47ms)
  ├─ peers     : 12 actifs
  ├─ modèle    : Qwen Coder 32B
  └─ ta contribution : 12 GB VRAM, layers 24-31
```

(Implémentation TUI à faire en phase 2.)

## Points d'attention

### Bundling de Parallax

Phase 1 / 2 : on suppose que `parallax` est dans le PATH (installé via `pip install -e .`
dans `packages/swarm-engine`).

Phase 4 (distribution) : il faudra **bundler le binaire Parallax** dans l'installeur
Fabi pour que l'utilisateur n'ait pas besoin de Python. Options :
- `pyinstaller` ou `nuitka` pour figer Parallax en binaire
- Téléchargement au premier run depuis nos serveurs Aircarto
- À décider en ADR dédiée plus tard.

### Versions compatibles

Quand on bumpe Parallax (sync upstream), il faut vérifier que le supervisor parle
toujours la bonne CLI (les arguments `parallax join …`). Lire le changelog de Parallax
à chaque sync.

### Gestion des erreurs

Cas à couvrir :
- Parallax crashe au démarrage → log + warning + on continue sans swarm
- Parallax crashe en cours → restart avec backoff (3 tentatives, puis abandon)
- Scheduler down → mode dégradé, on autorise les autres providers
- VRAM insuffisante annoncée → message clair à l'utilisateur

### Tests

À écrire en phase 2 :
- Unit tests sur le supervisor (mock du subprocess)
- Tests d'intégration avec un Parallax local lancé en mode test
- Tests E2E avec un scheduler local fake
