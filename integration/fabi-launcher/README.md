# fabi-launcher

Le binaire `fabi`. C'est ce que l'utilisateur lance.

## Ce qu'il fait, en 5 étapes

1. **Affiche** le banner FABI + la loutre 🦦
2. **Pingue** le scheduler Aircarto (healthcheck non bloquant)
3. **Démarre** le worker `parallax join -s <peer>` en sous-process pour
   rejoindre le swarm (si `parallax` n'est pas installé : warning + mode autonome)
4. **Exécute** fabi-cli (fork OpenCode) en foreground avec TTY hérité —
   l'utilisateur a la TUI directement
5. **À l'exit** du CLI : kill propre du worker parallax (process group entier),
   propagation de l'exit code

Si fabi-cli n'est pas trouvé, le launcher reste en mode keep-alive (utile
pour tester la mécanique parallax + signaux seuls).

## Build & dev

```bash
cd integration/fabi-launcher
npm install              # installe TypeScript + tsx (devDeps uniquement)
npm run dev              # lance via tsx (sans build)
npm run build            # compile en dist/
node dist/index.js       # lance la version compilée
```

Une fois compilé, tu peux mettre `dist/index.js` dans le PATH (ou faire
`npm link`) pour avoir la commande `fabi` globale.

## CLI flags

| Flag | Effet |
|---|---|
| `--scheduler URL` | URL HTTP du scheduler Aircarto (défaut : `http://37.59.98.16:3001`). Sert au healthcheck `/cluster/status_json` et plus tard à configurer fabi-cli. |
| `--scheduler-peer PEER` | PeerID Lattica/libp2p à passer à `parallax join -s` (défaut : la PeerID du scheduler de prod). C'est l'adresse du **swarm**, pas l'API HTTP. |
| `--model NAME` | Modèle par défaut (défaut : `Qwen/Qwen3-Coder-30B-A3B-Instruct`) |
| `--parallax-bin PATH` | Chemin custom vers le binaire parallax |
| `--fabi-cli-bin PATH` | Chemin custom vers le binaire fabi-cli (sinon auto-détecté) |
| `--no-parallax` | Skip le spawn parallax (utile en dev) |
| `--no-cli` | Skip le lancement de fabi-cli (mode worker seul) |
| `-v`, `--verbose` | Affiche stdout/stderr de parallax + résolution fabi-cli |
| `--` | Tout ce qui suit `--` est passé tel quel à fabi-cli |

Tout flag inconnu du launcher est aussi transmis à fabi-cli (donc `fabi run "fix X"` fonctionne).

## Variables d'environnement

| Var | Effet |
|---|---|
| `FABI_SCHEDULER` | Comme `--scheduler` |
| `FABI_SCHEDULER_PEER` | Comme `--scheduler-peer` |
| `FABI_MODEL` | Comme `--model` |
| `FABI_PARALLAX_BIN` | Comme `--parallax-bin` |
| `FABI_CLI_BIN` | Comme `--fabi-cli-bin` |
| `FABI_NO_PARALLAX=1` | Comme `--no-parallax` |
| `FABI_NO_CLI=1` | Comme `--no-cli` |
| `FABI_VERBOSE=1` | Comme `--verbose` |
| `NO_COLOR=1` | Désactive les couleurs ANSI |

## Fichiers de config (priorité décroissante)

1. CLI flags
2. Variables d'environnement
3. `~/.config/fabi/config.json` (user global)
4. `./.fabi/config.json` (projet courant)
5. Défauts hardcodés

Format JSON :

```json
{
  "scheduler":     "https://fabi.aircarto.fr",
  "schedulerPeer": "auto",
  "model":         "qwen-coder-32b",
  "verbose":       false
}
```

## Architecture du launcher

```
src/
├── index.ts      → orchestration : banner → healthcheck → worker → CLI → cleanup
├── config.ts     → résolution multi-sources (CLI/env/fichiers/défauts)
├── parallax.ts   → spawn/stop du worker, healthcheck scheduler, kill propre
├── fabicli.ts    → détection + spawn fabi-cli en foreground (TTY hérité)
├── banner.ts     → lecture des assets branding/ + impression colorée
└── colors.ts     → helpers ANSI minimalistes (zéro dépendance)
```

Stratégie de résolution de fabi-cli, dans l'ordre :

1. `--fabi-cli-bin` / `FABI_CLI_BIN` (override explicite)
2. `<meta>/packages/fabi-cli/packages/opencode/bin/opencode` si un paquet
   `opencode-<platform>-<arch>` est présent dans `node_modules` (post `bun install`)
3. Fallback dev : `bun run --conditions=browser src/index.ts` depuis
   `packages/fabi-cli/packages/opencode/` (clone fresh, dev)
4. `fabi` ou `opencode` dans le PATH (installation globale future)
5. Sinon : warning + mode keep-alive (worker seul)

**Aucune dépendance runtime.** Que des modules Node natifs (`child_process`,
`fs`, `path`, `url`, `os`). Les seules deps sont devDeps : TypeScript et tsx.

## Tests à faire

- [ ] `fabi --no-parallax --no-cli` → banner + status only, Ctrl+C exit propre
- [ ] `fabi --no-cli` (parallax dispo) → spawn parallax, Ctrl+C kill propre
- [ ] `fabi` sans parallax installé → warning "missing-binary" + continue
- [ ] `fabi` sans fabi-cli installé → warning + mode keep-alive
- [ ] `fabi --scheduler http://localhost:3001` → tente le healthcheck dessus
- [ ] `fabi -- run "fix bug"` → passthrough vers fabi-cli
- [ ] `kill -TERM <pid>` du process fabi → tue parallax + fabi-cli
- [ ] `kill -9` du process fabi → tout meurt (process group)
- [ ] Exit normal du CLI (`/quit`) → parallax killed, exit code propagé

## Évolution prévue

- Récupérer la liste des modèles dispos dynamiquement via `GET /v1/models`
- Afficher dans la TUI le statut "tu héberges les couches X-Y du modèle Z"
- Restart auto du worker avec backoff si crash
- Phase 3 (rebrand) : pré-baker l'`opencode.json` dans fabi-cli pour pointer
  par défaut sur `cfg.scheduler` (lu via env `FABI_SCHEDULER` déjà transmis)
