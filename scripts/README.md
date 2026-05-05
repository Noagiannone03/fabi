# scripts/

Scripts d'orchestration du méta-projet Fabi.

| Script | Rôle | Quand l'utiliser |
|---|---|---|
| `setup.sh` | Clone les deux upstreams (OpenCode, Parallax) dans `packages/`, configure les remotes `upstream`. | Une fois après le clone initial du méta-projet. |
| `sync-upstream.sh` | Pour chaque sous-repo : `git fetch upstream`, montre les commits en avance, propose un merge. | Mensuellement (cadence recommandée). |
| `check-divergence.sh` | Pour chaque sous-repo : montre combien de commits on est devant/derrière upstream, et le nombre de fichiers modifiés. | Avant un sync, ou pour un état des lieux. |

Tous les scripts sont **idempotents** : on peut les relancer sans casser quoi que ce soit.

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `OPENCODE_UPSTREAM` | `https://github.com/sst/opencode.git` | URL upstream OpenCode |
| `PARALLAX_UPSTREAM` | `https://github.com/GradientHQ/parallax.git` | URL upstream Parallax |
| `OPENCODE_FORK_REMOTE` | (vide) | URL de notre fork GitHub si elle existe (sera `origin`) |
| `PARALLAX_FORK_REMOTE` | (vide) | URL de notre fork GitHub si elle existe (sera `origin`) |

Si les variables `*_FORK_REMOTE` ne sont pas définies, `origin` sera laissé vide
(à configurer manuellement après création du fork sur GitHub).
