# Architecture — détail technique

> Si tu cherches une vue d'ensemble courte, lis [`/ARCHITECTURE.md`](../ARCHITECTURE.md).
> Ce document creuse les détails techniques pour les contributeurs.

## Stack technique

### packages/fabi-cli (fork OpenCode)

- **Langage** : TypeScript (~98 %)
- **Runtime** : Bun (avec fallback Node sur certaines plateformes)
- **Bundler** : configuration upstream (selon le sous-package OpenCode)
- **TUI** : Ink (React rendu dans le terminal)
- **Architecture** : monorepo Turbo, séparation client/serveur

### packages/swarm-engine (fork Parallax)

- **Langage** : Python (~78 %), TypeScript (~12 %), Metal/C++ (pour GPU)
- **Runtime** : Python ≥ 3.10
- **Backends d'inférence** :
  - vLLM, SGLang (NVIDIA / AMD)
  - MLX LM (Apple Silicon)
- **P2P** : Lattica (couche Gradient)

### integration/ (notre code)

- **Langage** : TypeScript (cohérent avec fabi-cli)
- **Runtime cible** : Bun et Node
- **Pas de dépendances lourdes** — Node natif autant que possible

## Inter-process communication

```
[fabi CLI]  ──spawn──►  [parallax worker (Python subprocess)]
       │                                  │
       │                                  └──libp2p──► [autres peers]
       │
       └──HTTP /v1/chat/...──► [scheduler Fabi]
                                    │
                                    └──orchestre──► [chemins peers swarm]
```

Le serveur fabi **n'attaque jamais directement les peers**. Il parle au scheduler,
qui parle au swarm. Cette indirection nous donne :

- Un point public stable pour authentifier / monitorer
- La possibilité de coller un système d'incitation entre les deux
- Une API OpenAI-compatible exposée par le scheduler que **n'importe quel** client
  IA standard peut consommer (utile pour intégrations futures Cline, Continue…)

## Pourquoi cette séparation ?

1. **OpenCode ≠ inférence** : OpenCode délègue déjà l'inférence à des providers externes
   (Anthropic, OpenAI, Ollama…). On ajoute "Fabi Swarm" comme un provider de plus.
   Notre fork ne touche pas le moteur d'inférence d'OpenCode.

2. **Parallax = backend pur** : Parallax fait l'inférence distribuée. Il ne sait pas qu'il
   y a un agent agentique au-dessus. Il sert n'importe quel client OpenAI-compatible.

3. **Couplage faible** : on peut updater chaque côté indépendamment. Une nouvelle version
   de Parallax qui supporte un nouveau modèle ? On fait `sync-upstream.sh` côté
   swarm-engine, le client fabi-cli n'a même pas besoin de changer.

## Décisions de design avec leurs alternatives écartées

### Pourquoi pas un daemon contributeur 24/7 ?

Considéré, écarté en MVP :

- Plus de surface d'attaque (process qui tourne en permanence)
- Plus de difficulté d'install (auto-startup OS-spécifique)
- Conflit avec la philosophie "tu contribues quand tu codes" (aligne usage et contribution)

Pourrait être ajouté en option avancée plus tard.

### Pourquoi pas du WebRTC ?

Lattica (utilisé par Parallax) couvre déjà le NAT traversal via libp2p + relays. Pas de
raison d'ajouter du WebRTC.

### Pourquoi pas embarquer Parallax dans le même process que OpenCode ?

- OpenCode tourne sur Bun/Node, Parallax sur Python — incompatibles dans un seul process
- Crash de l'inférence ne devrait pas tuer la TUI, et inversement
- Process séparés permettent de monitorer / restart indépendamment

### Pourquoi un scheduler centralisé plutôt que pure DHT publique ?

- En MVP, on veut **maîtriser** qui rejoint le swarm (auth, modération)
- Le scheduler peut implémenter le système d'incitation (impossible en pure DHT)
- Un point public unique = un point de monitoring unique
- Évolutif vers plusieurs schedulers fédérés plus tard

## Ressources / capacités annoncées par chaque worker

Quand un worker rejoint le swarm via Parallax, il annonce :

- VRAM disponible
- GPU compute capability
- Bande passante mesurée
- Latence vers le scheduler

Le scheduler utilise ces métriques pour assigner les tranches de modèle (qui héberge
quelles couches) et pour router les requêtes (chemin de moindre latence).

C'est Parallax qui gère ça, on ne le réinvente pas. Voir
[research paper Parallax](https://arxiv.org/pdf/2509.26182v1) pour les détails.
