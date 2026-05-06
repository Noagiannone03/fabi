# Roadmap Fabi

## Phase 0 — Setup (en cours)

- [x] Choix de la stratégie de fork (cherry-pick style Cursor)
- [x] Création du méta-projet
- [x] Clones initiaux d'OpenCode et Parallax avec remotes upstream configurés
- [ ] Premier `fabi --version` qui boot OpenCode rebadgé sans Parallax encore

## Phase 1 — Validation technique (semaines 1-2)

> Objectif : prouver que la chaîne `agent → scheduler → swarm` fonctionne, sans branding ni rebrand.

- [ ] Faire tourner Parallax pristine sur serveur5 (Fabi) en mode scheduler
- [ ] Lancer un worker Parallax pristine sur serveur1 ou poste local pour héberger Qwen Coder 32B
- [ ] Configurer OpenCode pristine avec une config `opencode.json` qui pointe sur ce scheduler
- [ ] Vérifier qu'on obtient des réponses cohérentes via la TUI OpenCode
- [ ] Mesurer le débit (tok/s) et la latence

## Phase 2 — Intégration auto (semaines 2-4)

> Objectif : `fabi` (binaire forké rebadgé) lance Parallax automatiquement et rejoint le swarm.

- [x] ~~Implémenter `integration/fabi-launcher` (launcher externe)~~ — abandonné au profit de l'intégration **native** dans le fork (cf. [ADR 002](./docs/decisions/002-pivot-fork-actif.md))
- [x] Module `packages/opencode/src/swarm/` créé (defaults, scheduler healthcheck, worker spawn/stop, provider-defaults, lifecycle)
- [x] Branchement boot dans `src/index.ts` : middleware swarm conditionnel sur la commande lancée (TUI default, run, serve)
- [x] Gérer la mort propre : SIGINT/SIGTERM/SIGHUP → kill worker (process group) ; filet sync `process.on("exit")` pour le cas `process.exit()` direct
- [ ] Tester sur poste réel : kill -9 le parent, vérifier que Parallax meurt aussi (process group)
- [ ] Smoke test bout-en-bout : poste local lance fabi → join scheduler local → CLI répond avec le swarm
- [x] Provider Fabi pré-baké directement dans la config par défaut (zéro env var requise) ; surchargeable par config user
- [x] **Auto-discovery via fabi-registry (v0.2.0)** : nouveau package `packages/fabi-registry/` côté serveur, scanne les containers Docker avec label `fabi.swarm=true`, extrait le peer ID des logs, expose `GET /v1/swarms`
- [x] **Commande `fabi swarms`** (v0.2.0) : liste les swarms disponibles avec peers, VRAM, modèle, status
- [x] **Flags CLI** `--registry`, `--swarm`, `--swarm-model`, `--no-registry` pour piloter la discovery

## Phase 3 — Rebrand (semaine 4-6)

> Objectif : zéro mention "opencode" visible à l'utilisateur final.

- [x] Binaire exposé comme `fabi` (alias dans `packages/opencode/package.json`, à côté de `opencode` pour compat)
- [x] ASCII art FABI dans le logo (wordmark depuis `branding/ascii-banner.txt`, couleur sunset `#FF8C42`)
- [x] `scriptName("fabi")` yargs + env vars `FABI` / `FABI_PID`
- [x] `name: "fabi"` dans `package.json` racine du fork
- [ ] Strings UI résiduelles : "opencode" / "OpenCode" dans la TUI/messages → audit + remplacements ciblés
- [ ] Thème par défaut : utiliser `branding/theme-fabi.json` (intégrer dans la config par défaut comme on a fait pour le provider)
- [ ] Welcome screen au premier run
- [ ] Footer discret "based on opencode" (politesse + obligation MIT)

## Phase 4 — Distribution (semaine 6-8)

> Stratégie : `curl -fsSL https://fabi.dev/install.sh | bash`
> (pattern Ollama / Bun / Pulumi / Claude Code, **pas npm** — on bundle Python+Parallax,
> trop lourd pour npm). Détails dans [docs/distribution.md](./docs/distribution.md).

- [x] `scripts/release-build.sh` — produit un tarball `fabi-<os>-<arch>-<accel>.tar.zst`
      contenant binaire fabi + Python standalone + venv Parallax (PyTorch + vLLM/MLX selon `--accel`)
- [x] `.github/workflows/release.yml` — workflow CI matrix (5 runners) qui build sur tag `v*`
- [x] `install.sh` (Linux/macOS) + `install.ps1` (Windows) — installer côté user
- [ ] **Tester en local** le pipeline complet (lancer `release-build.sh` avec FABI_SKIP_PARALLAX=1)
- [ ] **Créer le repo public** `github.com/Noagiannone03/fabi` et push le code
- [ ] **Premier release** : `git tag v0.1.0 && git push --tags` → vérifier les 5 tarballs sur GitHub Releases
- [ ] **Configurer le domaine** `fabi.dev` (DNS + serveur web qui sert install.sh)
- [ ] Page de présentation `fabi.dev` avec one-liner d'install
- [ ] (Plus tard) Publication VSCode Marketplace + Open VSX

## Phase 5 — Premiers users (mois 2)

- [ ] Inviter labo Fabi (~5 personnes)
- [ ] Inviter contacts hobbyists / écoles
- [ ] Monitoring InfluxDB du swarm
- [ ] Boucle de feedback rapide

## Phase 6 — Anti-free-rider (mois 3-4)

> Objectif : éviter que le swarm meure sous le poids des consommateurs non-contributeurs.

- [ ] Système de "credits" basé sur la contribution (compute-time donné)
- [ ] Throttling des consommateurs sans contribution
- [ ] Dashboard de contribution

## Phase 7 — Scale-out (mois 4+)

- [ ] Multi-scheduler (HA)
- [ ] Relays NAT Fabi pour souveraineté
- [ ] Privacy : R&D sur le chiffrement des hidden states
- [ ] Plus de modèles : Llama 3.3 70B, Qwen3 110B, DeepSeek V3 671B

---

## Sync upstream

- [ ] Première sync `sst/opencode` après 1 mois en phase 2
- [ ] Première sync `GradientHQ/parallax` après 1 mois en phase 2
- [ ] Cadence : mensuelle ensuite

## Risques majeurs à surveiller

1. **Cold start** du swarm : tant qu'on n'a pas N peers, latence/disponibilité dégradées
2. **Free-riding** : à attaquer dès phase 5 sinon le swarm meurt
3. **Scheduler unique** : point de défaillance, monitoring requis
4. **Privacy** : ne pas pitcher le produit pour code propriétaire sensible tant que pas chiffré
