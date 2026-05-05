# Fabi

> Un IDE / CLI agentique open source qui rejoint automatiquement un swarm P2P d'inférence LLM.
> Tu codes → tu contribues une part de ton GPU → tu utilises gratuitement un gros modèle distribué entre tous les peers.

---

## Pitch

| | Cursor / Copilot | Fabi |
|---|---|---|
| Coût mensuel | 20-100 € | **0 €** (en échange du partage GPU pendant que tu codes) |
| Modèles | propriétaires fermés | Qwen Coder, DeepSeek, Llama 3.x, Kimi-K2, etc. |
| Qualité visée | référence | ~80 % de Sonnet 4.6 |
| Confidentialité du code | cloud tiers | tes hidden states transitent via peers (pas pour code propriétaire sensible) |
| Vitesse | 100 tok/s | 15-50 tok/s selon modèle/swarm |

Cible : étudiants, devs solo, hobbyists, écoles, labos, PME — gens pour qui le coût des API cloud est un blocage et 80 % de qualité suffit.

---

## Architecture

```
       Utilisateur final
              │
       ┌──────┴──────┐
       │   fabi CLI / TUI    │  ← fork de sst/opencode
       │   ou ext VSCode           │     (rebrand, intégration Parallax)
       └──────┬──────┬─────────────┘
              │      │
   ┌──────────┘      └──────────┐
   │                            │
   ▼                            ▼
┌───────────────┐     ┌──────────────────────┐
│ Inférence     │     │ Swarm Engine         │
│ via /v1/chat  │     │ (fork Parallax)      │
│ /completions  │     │ ↑ rejoint au boot    │
│               │     │ ↑ contribue VRAM/GPU │
│               │     │ ↑ quitte à l'arrêt   │
└───────┬───────┘     └──────────┬───────────┘
        │                        │
        └────────┬───────────────┘
                 ▼
       ┌──────────────────────┐
       │ Aircarto Scheduler   │
       │ (orchestrateur du    │
       │  swarm, point public)│
       └──────────┬───────────┘
                  │
       ┌──────────┴────────────┐
       ▼                       ▼
   Worker peer 1         Worker peer N
   (autres users actifs en train de coder)
```

Le serveur `fabi` (= fork OpenCode) lance Parallax en sous-process au démarrage. L'utilisateur rejoint donc le swarm dès qu'il ouvre le CLI/IDE, et le quitte quand il ferme. L'inférence pour ses propres requêtes se fait via le scheduler central Aircarto qui route à travers le swarm.

---

## Composants

| Composant | Rôle | Origine | Localisation |
|---|---|---|---|
| **fabi-cli** | Agent agentique : CLI, TUI, ext VSCode, desktop | fork de [sst/opencode](https://github.com/sst/opencode) (MIT) | `packages/fabi-cli/` |
| **swarm-engine** | Inférence distribuée P2P | fork de [GradientHQ/parallax](https://github.com/GradientHQ/parallax) (Apache 2.0) | `packages/swarm-engine/` |
| **integration** | Code de glue : supervisor Parallax, config scheduler | écrit par nous | `integration/` |
| **scheduler** (futur) | Orchestrateur public Aircarto | écrit par nous | hors monorepo (déployé serveur5 Aircarto) |

---

## Statut

🚧 **MVP en construction.** Voir [ROADMAP.md](./ROADMAP.md).

---

## Démarrage rapide (développeurs)

```bash
# 1. Cloner ce méta-projet
git clone <ton-fork-meta> fabi
cd fabi

# 2. Récupérer les upstreams (clones de OpenCode et Parallax)
./scripts/setup.sh

# 3. Lire la doc dev
cat docs/development.md
```

---

## Stratégie de fork

**On ne réécrit pas, on cherry-pick comme Cursor sur VSCode.**

- Chaque sous-package (`packages/fabi-cli`, `packages/swarm-engine`) est un git repo distinct cloné depuis upstream
- Chacun a un remote `upstream` qui pointe sur le repo original
- Sync mensuelle : `./scripts/sync-upstream.sh` (cherry-pick / merge à la demande)
- Toutes nos modifs sont documentées dans [DIVERGENCE.md](./DIVERGENCE.md)

Voir [docs/upstream-sync-workflow.md](./docs/upstream-sync-workflow.md) pour la procédure détaillée.

---

## Licence

Ce méta-projet est sous **MIT** (voir [LICENSE](./LICENSE)).

Crédit obligatoire et reconnaissance aux projets upstream — voir [NOTICE](./NOTICE).

---

## Crédits

- **OpenCode** par l'équipe SST (Anomaly) — [sst/opencode](https://github.com/sst/opencode), licence MIT
- **Parallax** par Gradient HQ — [GradientHQ/parallax](https://github.com/GradientHQ/parallax), licence Apache 2.0
