# Architecture Fabi

## Vue d'ensemble

Fabi = (fork OpenCode pour l'agent) + (fork Parallax pour le swarm) + (code d'intégration).

Le binaire final que l'utilisateur lance est `fabi`. Il :

1. **Démarre le serveur agentique** (logique OpenCode rebadgée)
2. **Spawn le worker Parallax** en sous-process — l'utilisateur rejoint le swarm
3. **Affiche la TUI** (ou ouvre l'ext VSCode si lancé via VSCode)
4. **Route les requêtes IA** de l'utilisateur vers le scheduler Fabi qui orchestre l'inférence dans le swarm
5. **Tue le worker Parallax proprement** quand l'utilisateur ferme — l'utilisateur quitte le swarm

Cycle de vie : strictement aligné sur l'usage. Pas de daemon caché, pas de contribution 24/7. Tu codes = tu contribues.

## Diagramme bloc détaillé

```
                      MACHINE DE L'UTILISATEUR
   ┌────────────────────────────────────────────────────────────────────┐
   │                                                                    │
   │   Process: fabi                                              │
   │   ┌─────────────────────────────────────────────────────────────┐  │
   │   │  Serveur agentique (fork OpenCode)                          │  │
   │   │  - boot()                                                    │  │
   │   │     ├─► spawnParallax()          ← integration/parallax-sup │  │
   │   │     ├─► loadVoidSwarmConfig()    ← config Fabi           │  │
   │   │     └─► startHTTPServer(:7777)   ← API REST + SSE            │  │
   │   │                                                              │  │
   │   │  - HTTP/SSE :7777                                            │  │
   │   │     ◄─── TUI client (Ink)                                    │  │
   │   │     ◄─── ext VSCode (terminal)                               │  │
   │   │     ◄─── desktop / web (futur)                               │  │
   │   └─────────────────────────────────────────────────────────────┘  │
   │                                  │                                 │
   │                                  ▼                                 │
   │   ┌─────────────────────────────────────────────────────────────┐  │
   │   │  Worker Parallax (sous-process Python)                       │  │
   │   │  - rejoint le swarm via le scheduler Fabi                │  │
   │   │  - héberge une tranche de modèle (sharding)                  │  │
   │   │  - utilise GPU local (vLLM/SGLang/MLX)                       │  │
   │   │  - communique P2P avec autres peers via Lattica              │  │
   │   └─────────────────────────────────────────────────────────────┘  │
   │                                                                    │
   └──────────────────────────┬─────────────────────────────────────────┘
                              │ HTTPS + libp2p
                              ▼
                  ┌──────────────────────────┐
                  │ INTERNET                 │
                  │                          │
                  │  Fabi Scheduler      │  ← serveur public Fabi
                  │  - PeerID stable         │     (serveur5 derrière OPNsense)
                  │  - orchestration shards  │
                  │  - API /v1/chat/...      │
                  │  - dashboard santé       │
                  │                          │
                  │  Relay servers (Gradient │
                  │  publics ou Fabi)    │
                  │  pour NAT traversal      │
                  └─────────┬────────────────┘
                            │
              ┌─────────────┼─────────────┬─────────────┐
              ▼             ▼             ▼             ▼
          Worker peer A  Worker peer B  Worker peer C  ... (autres users)
```

## Flux d'une requête utilisateur

1. Utilisateur tape une question dans la TUI Fabi
2. TUI fait un POST `/v1/chat/completions` sur son serveur local `:7777`
3. Le serveur agentique applique son tool use, ses prompts système, etc.
4. Le serveur fait un appel HTTP à `https://fabi.dev/v1/chat/completions` (le scheduler Fabi)
5. Le scheduler choisit un chemin de peers (pipeline) qui héberge les couches du modèle
6. Le forward pass passe de peer en peer, le token sort, retour au scheduler
7. Le scheduler renvoie au serveur fabi local
8. Le serveur stream la réponse à la TUI

## Cycle de vie

| Évent | Action |
|---|---|
| User lance `fabi` | Boot serveur → spawn Parallax → join swarm → TUI prête |
| User tape une commande | Requête routée via scheduler Fabi |
| User Ctrl+C / ferme la TUI | Serveur reçoit SIGTERM → kill Parallax proprement → exit |
| Crash du serveur | Le sous-process Parallax meurt aussi (process group) |
| Ext VSCode démarre | Lance `fabi` en process enfant → même cycle |

## Choix d'architecture (et leurs raisons)

| Choix | Pourquoi |
|---|---|
| Forks séparés (multi-repo) plutôt que monorepo subtree | Sync upstream simple via `git fetch upstream` natif. Standard Cursor/Windsurf. |
| Parallax en sous-process plutôt qu'en lib | Parallax est Python, fabi est TS/Bun. Process séparé = découpage propre. |
| Scheduler centralisé Fabi plutôt que pur P2P public | Contrôle, observabilité, pas de free-riders dès le début. Évolution possible. |
| OpenAI-compatible endpoint | Parallax l'expose nativement, OpenCode le supporte nativement, zéro glue à écrire. |
| Sync upstream cherry-pick | Souveraineté + bug fixes upstream. Standard fork pro. |

## Décisions à venir

Voir [docs/decisions/](./docs/decisions/) pour les ADRs (Architecture Decision Records) à venir :

- Bundling Parallax (binaire séparé téléchargé au 1er run, ou inclus dans installeur ?)
- Format de l'incitation anti-free-rider (post-MVP)
- Stratégie de relay NAT (utiliser Gradient public ou monter les nôtres ?)
- Stratégie de packaging multi-OS

## Limites connues / non-goals MVP

- ❌ Mode "contribute 24/7" en daemon → pas dans le MVP, le user contribue uniquement quand il code
- ❌ Privacy chiffrée des hidden states → R&D longue, pas dans le MVP
- ❌ Multi-modèles simultanés sur le même swarm → un seul modèle actif à la fois
- ❌ Schedulers redondants HA → un seul scheduler Fabi, point fragile à surveiller
