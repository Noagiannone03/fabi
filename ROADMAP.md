# Roadmap Void-Swarm

## Phase 0 — Setup (en cours)

- [x] Choix de la stratégie de fork (cherry-pick style Cursor)
- [x] Création du méta-projet
- [x] Clones initiaux d'OpenCode et Parallax avec remotes upstream configurés
- [ ] Premier `void-swarm --version` qui boot OpenCode rebadgé sans Parallax encore

## Phase 1 — Validation technique (semaines 1-2)

> Objectif : prouver que la chaîne `agent → scheduler → swarm` fonctionne, sans branding ni rebrand.

- [ ] Faire tourner Parallax pristine sur serveur5 (Aircarto) en mode scheduler
- [ ] Lancer un worker Parallax pristine sur serveur1 ou poste local pour héberger Qwen Coder 32B
- [ ] Configurer OpenCode pristine avec une config `opencode.json` qui pointe sur ce scheduler
- [ ] Vérifier qu'on obtient des réponses cohérentes via la TUI OpenCode
- [ ] Mesurer le débit (tok/s) et la latence

## Phase 2 — Intégration auto (semaines 2-4)

> Objectif : `void-swarm` (binaire forké rebadgé) lance Parallax automatiquement et rejoint le swarm.

- [ ] Implémenter `integration/parallax-supervisor` : spawn `parallax join -s <scheduler>` au boot
- [ ] Modifier le boot du serveur OpenCode forké pour appeler le supervisor
- [ ] Gérer la mort propre : SIGTERM → kill Parallax → exit
- [ ] Tests : kill -9 le parent, vérifier que Parallax meurt aussi (process group)
- [ ] Pré-baker `opencode.json` avec le provider Void-Swarm comme défaut

## Phase 3 — Rebrand (semaine 4-6)

> Objectif : zéro mention "opencode" visible à l'utilisateur final.

- [ ] Renommer le binaire `opencode` → `void-swarm` (package.json `bin`)
- [ ] ASCII art VOID-SWARM dans le banner
- [ ] Strings UI : "OpenCode" → "Void-Swarm" dans TUI/banner/footer
- [ ] Thème par défaut : `void-swarm.json`
- [ ] Welcome screen au premier run
- [ ] Footer discret "based on opencode" (politesse + obligation MIT)

## Phase 4 — Distribution (semaine 6-8)

- [ ] CI/CD GitHub Actions pour build multi-OS (Linux, macOS Intel, macOS ARM, Windows)
- [ ] Publication npm `@aircarto/void-swarm`
- [ ] Publication VSCode Marketplace + Open VSX
- [ ] Page de download `voidswarm.io` (ou sous-domaine Aircarto)
- [ ] Bundling Parallax binary (téléchargement au premier run)

## Phase 5 — Premiers users (mois 2)

- [ ] Inviter labo Aircarto (~5 personnes)
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
- [ ] Relays NAT Aircarto pour souveraineté
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
