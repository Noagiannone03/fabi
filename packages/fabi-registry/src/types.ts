// Types publics du fabi-registry.
//
// Le contrat de `SwarmEntry` est aussi consommé par le CLI fabi (côté client),
// via une copie minimale dans `packages/fabi-cli/.../swarm/registry.ts`.
// Si tu modifies ce fichier, mets à jour aussi le client (et le test contractuel).

/**
 * Une instance de swarm Parallax découverte sur l'hôte Docker.
 *
 * Mélange métadonnées statiques (labels Docker du compose) et état dynamique
 * (peer ID extrait des logs, healthcheck du scheduler, peers connectés).
 */
export interface SwarmEntry {
  /** Identifiant stable, lu depuis le label `fabi.swarm.id`. */
  id: string

  /** Nom lisible (label `fabi.swarm.name`). Tombe sur `id` si absent. */
  name: string

  /** URL HTTP du scheduler (label `fabi.swarm.url`). Sans trailing slash. */
  schedulerUrl: string

  /** PeerID Lattica/libp2p extrait des logs. `null` si pas encore vu. */
  schedulerPeer: string | null

  /** Modèle servi (label `fabi.swarm.model`). */
  model: string

  /** Statut du scheduler tel qu'annoncé par /cluster/status_json. */
  status: "online" | "offline" | "unknown"

  /** Statut applicatif Parallax: "waiting" tant que pas assez de peers, "ready" sinon. */
  schedulerStatus: string | null

  /** Nombre de workers (peers GPU) actuellement connectés. */
  peers: number

  /** Somme des VRAM annoncées par les peers, en GB. */
  totalVramGb: number

  /** Date ISO du dernier scan. */
  lastSeen: string

  /** Nom du container Docker (debug). */
  containerName: string
}

/**
 * Réponse du registry pour `GET /v1/swarms`.
 *
 * On enveloppe la liste dans un objet pour pouvoir ajouter des champs
 * (pagination, version d'API, ...) sans casser le contrat.
 */
export interface SwarmsResponse {
  /** Version sémantique du contrat — bumpe le major si breaking change. */
  apiVersion: "v1"

  /** Date ISO de génération de cette réponse (= lastSeen le plus récent). */
  generatedAt: string

  /** Hôte qui héberge le registry (typiquement le FQDN ou IP du serveur). */
  host: string

  /** Liste des swarms découverts. Peut être vide. */
  swarms: SwarmEntry[]
}
