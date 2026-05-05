# Distribution — phase 4 (multi-OS via curl install.sh)

> **Statut** : pipeline préparé, pas encore exécuté en prod (pas encore de release publiée).
> Voir [ROADMAP.md](../ROADMAP.md) phase 4 pour le tracking.

## Vue d'ensemble

Fabi se distribue **hors npm** (parce qu'on bundle un runtime Python + Parallax
qui dépasse les limites du registry npm). On suit le pattern utilisé par
**Ollama, Bun, Pulumi, Claude Code, Rustup, Deno, uv** :

```
┌──────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│ Toi                  │    │ GitHub                │    │ Utilisateur          │
│                      │    │                       │    │                      │
│ git tag v0.1.0       │───▶│ Actions (5 runners)   │───▶│ curl install.sh|bash │
│ git push --tags      │    │ Releases (tarballs)   │    │                      │
└──────────────────────┘    └──────────────────────┘    └──────────────────────┘
```

## Composants du pipeline

### 1. `scripts/release-build.sh`

Script bash qui produit **un** tarball Fabi pour **une** plateforme donnée.

Fait 4 choses :
1. Compile le binaire `fabi` via `bun build --compile --target=<X>`
2. Télécharge un Python 3.11 standalone via [python-build-standalone](https://github.com/astral-sh/python-build-standalone)
3. Crée un venv Python avec Parallax + ses deps (PyTorch / vLLM / SGLang / MLX selon `--accel`)
4. Empaquette le tout dans `dist/fabi-<os>-<arch>-<accel>.tar.zst` + un `.sha256`

Exécutable localement et en CI. Mode `FABI_SKIP_PARALLAX=1` pour test rapide
du binaire `fabi` seul.

### 2. `.github/workflows/release.yml`

Workflow GitHub Actions déclenché au push d'un tag `v*`. Lance **5 runners
en parallèle** (un par OS/arch) qui exécutent chacun `release-build.sh` puis
uploadent leur tarball sur la GitHub Release du tag.

| Runner GitHub | Cible Bun | Python arch | Accel |
|---|---|---|---|
| `ubuntu-latest` | `bun-linux-x64` | `x86_64-unknown-linux-gnu` | `cpu` |
| `ubuntu-latest` | `bun-linux-x64` | `x86_64-unknown-linux-gnu` | `cuda` |
| `ubuntu-24.04-arm` | `bun-linux-arm64` | `aarch64-unknown-linux-gnu` | `cpu` |
| `macos-14` | `bun-darwin-arm64` | `aarch64-apple-darwin` | `mlx` |
| `macos-13` | `bun-darwin-x64` | `x86_64-apple-darwin` | `cpu` |
| `windows-latest` | _désactivé pour l'instant_ | — | — |

### 3. `install.sh` (Linux + macOS)

Script bash de ~150 lignes hébergé à `https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh`
(ou `https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh` en
fallback). Fait :

1. Détecte OS + arch + accel (CUDA/MLX/CPU) automatiquement
2. Résout la dernière version via l'API GitHub
3. Télécharge le bon `fabi-<os>-<arch>-<accel>.tar.zst` depuis Releases
4. Vérifie le SHA256
5. Extrait dans `~/.local/share/fabi/`
6. Crée un symlink `~/.local/bin/fabi`
7. Avertit si `~/.local/bin` n'est pas dans le PATH

### 4. `install.ps1` (Windows)

Pendant PowerShell de `install.sh`. Place dans `%LOCALAPPDATA%\fabi\`.

## Le flux complet

### Côté mainteneur (toi)

```bash
# 1. Crée le repo public sur GitHub : github.com/Noagiannone03/fabi
# 2. Push le code
git remote add origin https://github.com/Noagiannone03/fabi.git
git push -u origin main

# 3. Tag et push
echo "v0.1.0" > VERSION
git add VERSION && git commit -m "release: v0.1.0"
git tag v0.1.0
git push --tags

# 4. Attends 30 min (5 runners en parallèle, le plus long c'est le pip install Parallax)
# 5. Vérifie github.com/Noagiannone03/fabi/releases/v0.1.0 → 5 tarballs + SHA256
# 6. install.sh / install.ps1 sont attachés automatiquement par le job publish-installer
```

### Côté utilisateur final

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash

# Ou direct depuis GitHub si pas de domaine custom
curl -fsSL https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh | bash

# Windows
irm https://github.com/Noagiannone03/fabi/releases/latest/download/install.ps1 | iex
```

Après ça : `fabi` est dans son PATH, `fabi` lance le binaire qui spawn
Parallax depuis le venv bundlé. **Aucune install Python séparée requise**.

## Variantes par plateforme — tailles attendues

| Tarball | Compressé (.zst) | Décompressé |
|---|---|---|
| `fabi-linux-x64-cpu.tar.zst` | ~600 MB | ~1.5 GB |
| `fabi-linux-x64-cuda.tar.zst` | ~1.2 GB | ~3 GB |
| `fabi-linux-arm64-cpu.tar.zst` | ~600 MB | ~1.5 GB |
| `fabi-darwin-arm64-mlx.tar.zst` | ~500 MB | ~1.2 GB |
| `fabi-darwin-x64-cpu.tar.zst` | ~600 MB | ~1.5 GB |

Total à uploader par release : **~3.5 GB**. GitHub Releases accepte (limite
2 GB par fichier individuel, multi-fichiers sans limite globale).

## Hébergement de `install.sh`

Trois options, par préférence :

### Option A — Sous-domaine custom `github.com/Noagiannone03/fabi` (recommandé)

Tu sers `install.sh` depuis ton DNS Fabi. Avantage : URL belle et
mémorable. Faut juste un Nginx ou un static site qui sert le fichier en
HTTPS. **Le domaine `GitHub` t'appartient déjà**, donc juste un sous-domaine.

### Option B — `raw.githubusercontent.com` (zéro config)

`https://raw.githubusercontent.com/Noagiannone03/fabi/main/install.sh` marche
direct dès que le repo est public. Moins joli mais zéro effort.

### Option C — GitHub Pages

`https://Noagiannone03.github.io/fabi/install.sh` — gratuit, joli URL, géré
automatiquement par GitHub. Active `Pages` dans les settings du repo.

Le workflow `release.yml` attache également `install.sh` à chaque GitHub
Release, donc il est aussi accessible à `https://github.com/Noagiannone03/fabi/releases/latest/download/install.sh`.

## Mises à jour côté utilisateur

Pas de mécanisme `apt update`-style intégré (pour l'instant). L'utilisateur
re-lance simplement le `curl install.sh`. L'installer détecte une install
existante et la backupe avant écraser. À terme : commande `fabi upgrade`
qui fait pareil sans avoir à retaper l'URL.

## Désinstallation

Manuelle pour l'instant :
```bash
rm -rf ~/.local/share/fabi
rm -f ~/.local/bin/fabi
# (optionnel) retire la ligne export PATH ajoutée dans ~/.bashrc
```

À ajouter plus tard : sous-commande `fabi uninstall`.

## Coût

**0 €** :
- GitHub Actions est gratuit pour les projets open source publics
  (illimité depuis 2024, avant c'était 2000 min/mois)
- GitHub Releases est gratuit (jusqu'à 2 GB par fichier)
- Bandwidth GitHub est inclus
- Sous-domaine `github.com/Noagiannone03/fabi` ne coûte rien (déjà dans ton DNS)
