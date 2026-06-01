<div align="center">

# 🦊 Fabi

**Un CLI / IDE agentique open source qui rejoint un swarm P2P d'inférence LLM.**

Tu codes → tu prêtes une part de ton GPU pendant ce temps → tu utilises gratuitement
un gros modèle (Qwen Coder, Llama 3.x, DeepSeek…) réparti entre tous les peers.

</div>

---

## 🚀 Installation

> Une seule commande. L'installeur détecte ton OS / GPU, télécharge le bon runtime
> et ajoute `fabi` à ton `PATH`. Relance ton terminal ensuite.

### Windows

Fabi tourne **dans WSL** sur Windows (le moteur d'inférence GPU n'existe pas en
natif Windows — WSL est la voie officielle pour NVIDIA CUDA). Il faut donc WSL.

1. **Installer WSL** (une fois), dans PowerShell **en admin** :
   ```powershell
   wsl --install -d Ubuntu
   ```
   Redémarre si demandé. *(Pour contribuer en GPU : driver NVIDIA récent — le
   support CUDA-on-WSL est inclus, rien d'autre à installer côté Linux.)*

2. **Installer Fabi**, dans PowerShell :
   ```powershell
   irm https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.ps1 | iex
   ```

3. Rouvre ton terminal, puis :
   ```powershell
   fabi
   ```

### macOS (Apple Silicon)

```bash
curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash
```

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash
```

Puis, sur toutes les plateformes :

```bash
fabi
```

---

## ✅ Pré-requis & ce qui est téléchargé

| Plateforme | Contribution GPU | Détails |
|---|---|---|
| **macOS** | Apple Silicon (MLX) | runtime bundlé dans le tarball |
| **Linux x64 + NVIDIA** | CUDA | moteur installé au 1ᵉʳ lancement (trop gros pour le tarball) |
| **Windows + NVIDIA** | CUDA via WSL | exécute le runtime Linux dans WSL |
| **CPU only** | — | fonctionne mais lent (mode dégradé) |

- **Python 3.10+** est requis pour le worker ; l'installeur le détecte et te guide s'il manque.
- Tout s'installe dans `~/.local/share/fabi/` (Linux/macOS) — désinstallation = supprimer ce dossier + l'entrée PATH.

---

## 🎮 Premiers pas

Au lancement, `fabi` te connecte au swarm :

1. **Choix du modèle** — si ton dernier modèle (ou le défaut) a des peers actifs,
   Fabi s'y connecte directement. Sinon, un **sélecteur s'ouvre dans l'interface**
   avec la liste des modèles disponibles et **leurs peers en direct** :

   ```
   ╭─ Choose your model · you join its swarm and help run it ─╮
   │ Ready                                                    │
   │ ▍ Qwen3-Coder-30B     ● 4 peers · 96 GB · ready          │
   │   Llama-3.3-70B       ● 2 peers · 48 GB · ready          │
   │ Waiting for peers                                        │
   │   DeepSeek-V3         ◌ 1 peer · 24 GB · no peers yet     │
   ╰──────────────────────────────────────────────────────────╯
   ```

2. **Changer de modèle** à tout moment : le footer affiche toujours le modèle
   courant + ses peers + le raccourci (par défaut `Ctrl+P` → *Switch model*, ou
   `/models`). Changer de modèle te reconnecte au swarm correspondant.

3. **Tu contribues** automatiquement pendant que tu l'utilises (philosophie Fabi :
   *tu utilises = tu contribues*). Le worker quitte le swarm quand tu fermes `fabi`.

---

## 🔧 Options d'installation (variables d'env)

| Variable | Effet | Défaut |
|---|---|---|
| `FABI_VERSION` | version à installer | `latest` |
| `FABI_ACCEL` | forcer l'accélérateur (`cuda` / `mlx` / `cpu`) | auto-détecté |
| `FABI_INSTALL` | dossier d'install | `~/.local/share/fabi` (Win : `%LOCALAPPDATA%\fabi`) |
| `FABI_NO_PATH` | `1` = ne pas toucher au PATH | — |
| `FABI_WINDOWS_MODE` | `wsl` (défaut) ou `native` (test only) | `wsl` |
| `FABI_WSL_DISTRO` | distro WSL à utiliser | distro par défaut |

Exemple (forcer CPU) :
```bash
FABI_ACCEL=cpu curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash
```

---

## 🧠 Comment ça marche

```
        Toi (fabi CLI/TUI)
              │
   ┌──────────┴───────────┐
   │ inférence            │ worker Parallax local
   │ (/v1/chat/...)       │ (rejoint le swarm, prête ton GPU)
   └──────────┬───────────┘
              ▼
       Fabi Scheduler  ──► route à travers les workers
              │
     ┌────────┴────────┐
     ▼                 ▼
  Peer 1   …   Peer N   (autres utilisateurs en train de coder)
```

Le CLI lance le moteur d'inférence (**fork de [Parallax](https://github.com/GradientHQ/parallax)**)
en sous-process : tu rejoins le swarm dès l'ouverture, tu le quittes à la fermeture.
Le modèle est **découpé en couches réparties sur plusieurs machines** (pipeline parallel),
donc aucun peer n'a besoin de tout le modèle.

---

## 🧩 Composants

| Composant | Rôle | Origine |
|---|---|---|
| **fabi-cli** | Agent : CLI, TUI, ext VSCode | fork de [sst/opencode](https://github.com/sst/opencode) (MIT) |
| **swarm-engine** | Inférence distribuée P2P | fork de [GradientHQ/parallax](https://github.com/GradientHQ/parallax) (Apache 2.0) |
| **fabi-registry** | Auto-discovery des swarms (API `GET /v1/swarms`) | écrit par nous (`packages/fabi-registry/`) |
| **scheduler** | Orchestrateur public du swarm | déployé hors monorepo |

---

## 👩‍💻 Développement

```bash
git clone <ton-fork-meta> fabi && cd fabi
./scripts/setup.sh        # clone fabi-cli + swarm-engine (forks)
cat docs/development.md
```

On ne réécrit pas les upstreams, on cherry-pick (style Cursor sur VSCode). Sync :
`./scripts/sync-upstream.sh`. Modifs documentées dans [DIVERGENCE.md](./DIVERGENCE.md),
plan dans [ROADMAP.md](./ROADMAP.md).

---

## 📜 Licence & crédits

Méta-projet sous **MIT** (voir [LICENSE](./LICENSE) et [NOTICE](./NOTICE)).

- **OpenCode** — équipe SST, [sst/opencode](https://github.com/sst/opencode) (MIT)
- **Parallax** — Gradient HQ, [GradientHQ/parallax](https://github.com/GradientHQ/parallax) (Apache 2.0)
