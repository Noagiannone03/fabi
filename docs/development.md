# Guide de développement

> Pour démarrer après un clone frais.

## Pré-requis

| Outil | Version mini | Comment installer |
|---|---|---|
| **git** | 2.30+ | `apt install git` ou équivalent |
| **Bun** | 1.0+ | `curl -fsSL https://bun.sh/install \| bash` (pour `fabi-cli`) |
| **Python** | 3.10+ | déjà standard sur Linux récent (pour `swarm-engine`) |
| **Node** | 20+ | optionnel, fallback si Bun pas dispo |

## Setup initial

```bash
git clone <ton-fork-meta>/fabi
cd fabi
./scripts/setup.sh           # clone OpenCode + Parallax dans packages/
./scripts/check-divergence.sh # vérifie l'état
```

## Structure après setup

```
fabi/                       ← le méta-projet (CE repo)
├── README.md, ARCHITECTURE.md, …
├── packages/
│   ├── fabi-cli/           ← fork OpenCode (git repo indépendant)
│   │   └── upstream → sst/opencode (branche dev)
│   └── swarm-engine/             ← fork Parallax (git repo indépendant)
│       └── upstream → GradientHQ/parallax (branche main)
├── integration/                  ← code 100 % nous
│   ├── parallax-supervisor/
│   └── scheduler-config/
├── scripts/                      ← orchestration
├── docs/
└── branding/
```

## Workflow quotidien

### Travailler sur le CLI agentique (fabi-cli)

```bash
cd packages/fabi-cli
bun install           # premier coup uniquement
bun dev               # ou la commande dev d'OpenCode (à confirmer dans leur README)
```

Travailler dans `packages/fabi-cli/` revient à travailler sur OpenCode. Toutes les
docs OpenCode s'appliquent. Pour ajouter de l'intégration Fabi, plutôt que de
modifier des fichiers upstream, on importe depuis `../../integration/`.

### Travailler sur le moteur d'inférence (swarm-engine)

```bash
cd packages/swarm-engine
python3 -m venv .venv
source .venv/bin/activate
pip install -e .      # install editable
parallax --help       # vérifier que le binaire est dispo
```

Voir le README de `packages/swarm-engine/` (provient d'upstream) pour les détails.

### Travailler sur l'intégration

```bash
cd integration/parallax-supervisor
# (futur) bun install ; bun test
```

### Mise à jour upstream

Mensuellement :

```bash
./scripts/sync-upstream.sh
```

Le script est interactif et propose merge / cherry-pick / skip pour chaque sous-repo.
Lis [docs/upstream-sync-workflow.md](./upstream-sync-workflow.md) pour les détails.

## Commits & branches

### Sur le méta-projet (CE repo)

- Branche principale : `main`
- On commit ici : modifications dans `integration/`, `scripts/`, `branding/`, `docs/`,
  fichiers `.md` à la racine.
- Conventional commits suggérés : `feat:`, `fix:`, `docs:`, `chore:`

### Sur les sous-repos (`packages/*/`)

- Chaque sous-repo a ses propres conventions héritées d'upstream.
- Notre branche locale par défaut suit la branche par défaut d'upstream :
  - `fabi-cli` : `dev`
  - `swarm-engine`   : `main`
- Quand on commit dans un sous-repo, c'est sur **notre** fork (`origin`), jamais
  vers `upstream` (les scripts setup.sh enlèvent `origin` initialement pour éviter
  un push accidentel vers le repo officiel).

## Tester la chaîne complète (fin de phase 2)

```bash
# Terminal 1 : scheduler Aircarto en local (à mettre en place)
cd packages/swarm-engine
parallax run -m qwen-coder-32b -n 1   # mode tout-en-un local

# Terminal 2 : CLI fabi
cd packages/fabi-cli
bun run dev   # devrait spawn parallax (via supervisor) et ouvrir la TUI
```

(Procédure à affiner dès qu'on a une première intégration fonctionnelle.)

## Dépannage

### "command not found: parallax"

Active le venv Python (`source packages/swarm-engine/.venv/bin/activate`) ou ajoute
le binaire au `PATH`.

### "command not found: bun"

```bash
curl -fsSL https://bun.sh/install | bash
```

### Conflits de fusion lors du sync upstream

C'est normal sur les fichiers que nous avons modifiés. Voir
[docs/upstream-sync-workflow.md](./upstream-sync-workflow.md).
