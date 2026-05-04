# scheduler-config

Configuration par défaut pour pointer le CLI sur le scheduler Aircarto.

## Pourquoi un module dédié ?

Plutôt qu'éparpiller des URLs hardcodées dans le code, on centralise tout ici.
Comme ça :

- Changer le domaine du scheduler = 1 fichier à toucher
- Faire pointer une dev/staging/prod différente = variable d'env qui override
- Override par utilisateur via `~/.config/void-swarm/config.json` reste possible

## Sources de config (résolution par priorité descendante)

1. **Argument CLI** (`--scheduler https://...`)
2. **Variable d'environnement** (`VOID_SWARM_SCHEDULER`)
3. **Fichier user** (`~/.config/void-swarm/config.json`)
4. **Fichier projet** (`<cwd>/.void-swarm/config.json`)
5. **Défauts hardcodés ici** (production : `https://swarm.aircarto.fr`)

## API envisagée (phase 2)

```ts
import { resolveSchedulerConfig, voidSwarmDefaults } from "./index"

const cfg = await resolveSchedulerConfig({ argv: process.argv })
// cfg.schedulerUrl, cfg.defaultModel, cfg.headers, etc.
```

## Modèles offerts par défaut

À aligner avec ce que le scheduler Aircarto annonce. En MVP :

- `qwen-coder-32b` — défaut
- (futur) `qwen3-110b`, `deepseek-coder-v3`, etc.

Une route `GET /v1/models` sur le scheduler retournera la liste vivante,
le client pourra donc s'auto-rafraîchir.
