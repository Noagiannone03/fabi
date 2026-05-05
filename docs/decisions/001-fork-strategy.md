# ADR 001 — Stratégie de fork pour OpenCode et Parallax

- **Date** : 2026-05-04
- **Statut** : accepté
- **Décideur** : Paul (Aircarto)

## Contexte

Fabi a besoin :

1. D'un agent agentique CLI/TUI/extension VSCode qui sert de produit utilisateur
2. D'un moteur d'inférence distribué P2P qui fait tourner les modèles en swarm

Plutôt que de réécrire ces briques (qui représentent des milliers d'heures
d'engineering), on s'appuie sur deux projets open source matures :

- **OpenCode** ([sst/opencode](https://github.com/sst/opencode), licence MIT) pour l'agent
- **Parallax** ([GradientHQ/parallax](https://github.com/GradientHQ/parallax), licence Apache 2.0) pour le swarm

## Question

Quelle stratégie d'incorporation choisir ?

## Options évaluées

### A. Utiliser comme dépendances pures (sans fork)

- ✅ Maintenance zéro
- ❌ Branding "Fabi" impossible (TUI affiche "opencode")
- ❌ Pas de modifications profondes possibles (par ex spawn auto de Parallax)

### B. Fork léger sur copie (rebase actif sur upstream)

- ✅ Branding total possible
- ✅ Modifs profondes possibles
- 🟡 Maintenance moyenne (rebases mensuels)

### C. Hard fork (couper le cordon)

- ✅ Souveraineté totale
- ❌ Maintenance énorme (3-5 ingés full-time pour faire vivre les deux)
- ❌ On rate les bug fixes / nouveaux modèles upstream

### D. Mix : fork avec sync périodique cherry-pick (= "approche Cursor")

- ✅ Branding et modifs profondes possibles
- ✅ On profite des bug fixes upstream
- ✅ On choisit ce qu'on prend de upstream (cherry-pick)
- 🟡 Maintenance modérée si on garde nos modifs propres et localisées

## Décision

**Option D — fork avec sync périodique cherry-pick.**

C'est la stratégie qu'utilisent Cursor, Windsurf, Antigravity sur VSCode upstream.
C'est le compromis le plus efficace pour un projet à petite équipe (1-2 personnes
en MVP) qui veut une marque indépendante sans assumer le coût d'un hard fork.

### Modalités

- **Multi-repo** plutôt que monorepo subtree :
  - Chaque sous-package (`packages/fabi-cli`, `packages/swarm-engine`)
    est un git repo indépendant cloné depuis upstream.
  - Les remotes : `origin` = notre fork GitHub (à créer), `upstream` = repo officiel.
  - Le méta-projet (CE repo) orchestre : docs, scripts, branding, code d'intégration.

- **Sync mensuelle** via `./scripts/sync-upstream.sh`, interactif.

- **Modifs localisées** :
  - 90 % de notre code dans des nouveaux fichiers (jamais en conflit)
  - 10 % en patches ciblés sur fichiers upstream (documentés dans DIVERGENCE.md)

- **Branche par défaut** héritée d'upstream :
  - `dev` pour `fabi-cli` (OpenCode)
  - `main` pour `swarm-engine` (Parallax)

## Conséquences

### Positives

- Démarrage rapide (un weekend pour avoir le squelette)
- Branding total possible dès qu'on veut
- Bug fixes upstream récupérés gratuitement
- Si un jour on veut couper le cordon, on peut (la divergence est documentée)

### Négatives à surveiller

- 2-5 heures de maintenance par mois (acceptable solo)
- Si la divergence augmente trop, sync devient pénible → vigilance
- Si upstream change drastiquement de direction, on est exposés (mais on peut skipper)

## Ré-évaluation

À refaire dans 6 mois si :
- La maintenance dépasse 10h/mois
- Une divergence stratégique émerge (besoin de refondre une archi en profondeur)
- On lève des fonds / staffe une équipe (le hard fork redevient envisageable)

## Références

- [Cursor's approach to forking VSCode](https://news.ycombinator.com/item?id=43831519)
- [Is Forking VS Code a Good Idea? (EclipseSource)](https://eclipsesource.com/blogs/2024/12/17/is-it-a-good-idea-to-fork-vs-code/)
- [OpenCode (sst)](https://github.com/sst/opencode), licence MIT
- [Parallax (GradientHQ)](https://github.com/GradientHQ/parallax), licence Apache 2.0
