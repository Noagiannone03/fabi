# fabi-registry

Service d'auto-discovery des swarms Parallax tournant sur un hôte Docker.

## Pourquoi

Le CLI `fabi` doit savoir, au démarrage, quel scheduler rejoindre (URL + peer ID
Lattica/libp2p). Hardcoder ces valeurs dans le binaire pose deux problèmes :

- Si la clé `p2p.key` du scheduler est régénérée, le peer ID change → le CLI
  ne peut plus se connecter sans une nouvelle release.
- On ne peut pas exposer plusieurs swarms (différents modèles, environnements).

`fabi-registry` résout ces deux problèmes : il scanne en permanence les
containers Docker présents sur l'hôte, identifie les schedulers Parallax via
des labels Docker, extrait leur peer ID des logs, et expose une liste à jour
sur une API HTTP simple.

## Architecture

```
┌──────────────────────────────────────────────┐
│ Docker daemon                                │
│  └─ container "parallax-scheduler"           │
│       ├─ labels: fabi.swarm=true, ...        │
│       └─ logs:   "Stored scheduler peer id"  │
└──────────────────────────────────────────────┘
                  │
                  │ docker.sock
                  ▼
┌──────────────────────────────────────────────┐
│ fabi-registry                                │
│  ┌─────────────┐    ┌──────────────────┐     │
│  │ Scanner     │───▶│ HTTP server      │     │
│  │ (every 5s)  │    │ /v1/swarms       │     │
│  └─────────────┘    └──────────────────┘     │
└──────────────────────────────────────────────┘
                  ▲
                  │ HTTP GET
                  │
              CLI fabi
```

## API

### `GET /healthz`

Liveness check. Retourne 200 dès que le scanner a complété au moins un cycle.

### `GET /v1/swarms`

Liste les swarms découverts.

```json
{
  "apiVersion": "v1",
  "generatedAt": "2026-05-05T16:30:00.000Z",
  "host": "0.0.0.0",
  "swarms": [
    {
      "id": "fabi-prod",
      "name": "Fabi Prod (Qwen3-Coder-30B)",
      "schedulerUrl": "http://37.59.98.16:3001",
      "schedulerPeer": "12D3KooWKLCTHRAhMEafQfaGZTAEx8kJjeMqpXDDeyhBGVotuSfR",
      "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
      "status": "online",
      "schedulerStatus": "waiting",
      "peers": 5,
      "totalVramGb": 79.5,
      "lastSeen": "2026-05-05T16:30:00.000Z",
      "containerName": "parallax-scheduler"
    }
  ]
}
```

### `GET /v1/swarms/:id`

Une seule entrée swarm, ou 404.

## Configuration côté Docker compose

Dans le `docker-compose.yml` de chaque scheduler, ajouter :

```yaml
labels:
  fabi.swarm: "true"
  fabi.swarm.id: "<id-stable-du-swarm>"
  fabi.swarm.name: "<nom-lisible>"
  fabi.swarm.model: "<huggingface/model-id>"
  fabi.swarm.url: "<url-publique-du-scheduler>"
```

Le peer ID n'est **pas** dans les labels — il est extrait dynamiquement des
logs du container, ce qui permet de gérer les régénérations de clé.

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `FABI_REGISTRY_PORT` | `3002` | Port HTTP d'écoute |
| `FABI_REGISTRY_HOST` | `0.0.0.0` | Interface d'écoute |
| `FABI_REGISTRY_INTERVAL_MS` | `5000` | Période de scan Docker |
| `FABI_DOCKER_SOCKET` | `/var/run/docker.sock` | Socket Docker à interroger |

## Déploiement

### Build du binaire

```sh
cd packages/fabi-registry
bun install
bun run build
# → dist/fabi-registry (binaire self-contained)
```

### Installation sur le serveur

```sh
# Copie le binaire
sudo mkdir -p /opt/fabi-registry
sudo cp dist/fabi-registry /opt/fabi-registry/
sudo chmod +x /opt/fabi-registry/fabi-registry

# Installe le service systemd
sudo cp systemd/fabi-registry.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fabi-registry

# Vérification
curl http://localhost:3002/v1/swarms | python3 -m json.tool
```

L'utilisateur `debian` doit être dans le groupe `docker` :

```sh
sudo usermod -aG docker debian
```

## Tests

```sh
bun test
```

Tests unitaires sur le parsing de logs (extract peer ID), les frames Docker
(demux du multiplex stdout/stderr), et le serveur HTTP (handlers).
