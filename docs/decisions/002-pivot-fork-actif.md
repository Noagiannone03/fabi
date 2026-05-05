# ADR 002 — Pivot vers fork actif et appropriation du code OpenCode

- **Date** : 2026-05-05
- **Statut** : accepté
- **Décideur** : Paul (Fabi)
- **Supersedes partiellement** : [ADR 001 — Stratégie de fork](./001-fork-strategy.md) (modalités, pas la décision de principe)

## Contexte

L'ADR 001 (mai 2026) a fixé une stratégie de fork "cherry-pick style Cursor" :
modifs minimales, 90 % de notre code dans des nouveaux fichiers (`integration/`),
patches localisés sur upstream uniquement quand strictement nécessaire,
sync mensuelle facile.

À l'usage, deux constats sont apparus :

1. **OpenCode embarque massivement de la surface SaaS et UI desktop**
   non utilisée par Fabi : 19 sous-packages dont `console`, `enterprise`,
   `slack`, `desktop-electron`, `desktop`, `web`, `app`, `ui`, `storybook`,
   `function`, `extensions/zed`, `identity`, `docs`. Le cœur agent CLI/TUI
   ne représente qu'une fraction (~6 packages : `opencode`, `core`, `plugin`,
   `sdk`, `script`, `containers`).

2. **La doctrine "modifs minimales" rend la base mentalement plus lourde
   à manipuler** alors qu'on n'a aucun usage des packages SaaS et qu'ils
   bruitent la lecture, les dépendances, le `bun install`, le typecheck et
   les builds CI.

Conséquence : Paul a décidé qu'on assume une **appropriation active** du
fork — on supprime ce qu'on n'utilise pas, on modifie ce qu'on doit modifier,
on n'a plus l'objectif d'imiter exactement upstream.

## Question

Comment on traite désormais le fork OpenCode ? Continue-t-on à minimiser
la divergence pour faciliter les syncs upstream, ou est-ce qu'on s'autorise
à modifier/supprimer librement pour faire de Fabi *notre* CLI ?

## Options évaluées

### A. Maintien strict de l'ADR 001 (minimiser la divergence)

- ✅ Sync upstream très simple
- ❌ On garde du code SaaS qu'on n'exécute jamais
- ❌ Charge cognitive de comprendre 19 packages alors qu'on en a besoin de 6
- ❌ Bundle / install / typecheck inutilement lourds
- ❌ Risque qu'un package SaaS upstream reçoive une CVE ou une dépendance
  cassée et qu'on doive gérer ça pour rien

### B. Hard fork complet (couper le cordon avec upstream)

- ✅ Souveraineté totale
- ❌ On rate les nouveaux tools, MCP, providers, fixes upstream
- ❌ Maintenance énorme dès que le moteur agent évolue chez SST
- Trop tôt : upstream OpenCode bouge vite (786 releases) et on perdrait beaucoup

### C. Pivot vers fork actif avec sync upstream sélective (RETENU)

- On **supprime** les packages clairement hors scope (`console`, `enterprise`,
  `slack`, `desktop`, `desktop-electron`, `web`, `app`, `ui`, `storybook`,
  `function`, `extensions`, `identity`, `docs`)
- On **garde** le cœur agent (`opencode`, `core`, `plugin`, `sdk`, `script`)
  et `containers/` (utile phase 4 packaging)
- On **modifie librement** ce qu'on doit modifier dans les packages gardés
  (rebrand, ajouts Fabi, refactor si besoin)
- Sync upstream **sélective** : on ne tire que les modifs qui touchent les
  packages qu'on a gardés ; on ignore le reste
- Toutes les divergences continuent d'être documentées dans `DIVERGENCE.md`

## Décision

**Option C — fork actif avec sync upstream sélective.**

C'est l'évolution naturelle de l'ADR 001 quand on a *commencé à habiter le code*.
On reste philosophiquement aligné (cherry-pick, pas hard fork), mais on
assume que **Fabi ≠ OpenCode rebrandé : Fabi est un produit qui dérive
d'OpenCode mais qui suit sa propre trajectoire**.

### Modalités concrètes

1. **Première coupe** (ce commit) :
   - Suppression dans `packages/fabi-cli/` des dossiers : `app/`, `ui/`,
     `desktop/`, `desktop-electron/`, `web/`, `slack/`, `enterprise/`,
     `console/`, `function/`, `storybook/`, `extensions/`, `identity/`, `docs/`
   - Mise à jour du `package.json` racine (scripts `dev:*`, workspaces)
   - Mise à jour de `turbo.json` (tâches relatives aux packages supprimés)
   - Commit sur la branche `dev` du fork avec message explicite
     `chore(fabi): prune packages SaaS / desktop / web hors scope`

2. **Workflow modifs upstream désormais** :
   - Avant : "n'écris jamais dans un fichier upstream sans documenter"
   - Maintenant : "modifie librement les fichiers dans `opencode/`,
     `core/`, `plugin/`, `sdk/`, `script/`, `containers/` ; documente
     uniquement les modifs *structurantes* dans `DIVERGENCE.md`"
   - Les modifs cosmétiques (strings UI "OpenCode" → "Fabi", branding TUI,
     thèmes) ne sont plus à documenter individuellement — résumé global
     suffit

3. **Sync upstream `./scripts/sync-upstream.sh`** désormais filtre :
   - On ne merge que les commits qui touchent les packages gardés
   - On peut skipper massivement les commits SaaS/desktop sans culpabilité

4. **Critère de "qu'est-ce qui mérite encore un cherry-pick"** :
   - Tout ce qui touche le moteur agent (tools, provider, session, prompt)
   - Tout ce qui touche la TUI (`packages/opencode/src/cli/cmd/tui/`)
   - Sécurité / CVE
   - Bug fixes documentés

## Conséquences

### Positives

- **Codebase mentalement gérable** : ~6 packages au lieu de 19
- **Builds / installs plus rapides** : moins de deps, moins de `bun install`
- **Lisibilité** : un dev qui ouvre `packages/fabi-cli/` voit immédiatement
  ce qui sert
- **Liberté de modifier** : on rebranderait sans complexer
- **Identité produit claire** : Fabi est un fork actif, pas un rebrand cosmétique

### Négatives à surveiller

- **Sync upstream un peu plus délicate** : un commit upstream qui touche
  *à la fois* un package gardé et un package supprimé crée du bruit dans
  le merge — mais peu fréquent en pratique car les modifs touchent rarement
  des packages aussi orthogonaux que `opencode/` et `console/`
- **Si on revient sur la décision** (par ex. si on veut une UI desktop
  un jour) : il faudra `git revert` du commit de coupe ou re-puller depuis
  upstream — facile mais pas instantané
- **Charge de modif augmente** : on aura plus de divergence à terme, donc
  plus de conflits cumulés sur les fichiers réellement modifiés. Mitigation :
  tenir `DIVERGENCE.md` à jour pour chaque modif structurante

## Ré-évaluation

À refaire si :
- On veut **inverser la coupe** (revenir sur un package supprimé)
- La sync upstream devient cauchemardesque (>10 h/mois) → glisser vers
  hard fork (ADR 001 option C) ou rebooter sur Crush (cf. recherche
  alternatives 2026-05-05)
- Un package qu'on a supprimé devient soudainement utile (par ex. on
  veut packager un Electron desktop Fabi → on re-pull `app/` + `desktop-electron/`
  depuis upstream à ce moment-là)

## Références

- [ADR 001 — Stratégie de fork](./001-fork-strategy.md)
- [DIVERGENCE.md](../../DIVERGENCE.md)
- Comparatif Aider vs OpenCode (2026-05-05) : OpenCode 155k stars,
  archi modulaire, équipe pro derrière → meilleur pari long terme malgré
  la coupe
- Audit packages OpenCode 2026-05-05 (cf. cartographie inter-package)
