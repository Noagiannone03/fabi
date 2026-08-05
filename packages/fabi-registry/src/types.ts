// Types publics du fabi-registry.
//
// Le contrat de `SwarmEntry` est aussi consommé par le CLI fabi (côté client),
// via une copie minimale dans `packages/fabi-cli/.../swarm/registry.ts`.
// Si tu modifies ce fichier, mets à jour aussi le client (et le test contractuel).

/**
 * Une instance de swarm Fabi découverte sur l'hôte Docker.
 *
 * Mélange métadonnées statiques (labels Docker du compose) et état dynamique
 * (peer ID extrait des logs, healthcheck du scheduler, peers connectés).
 */
export interface WorkerConnectionProfile {
  /** Contract version understood by the worker bootstrapper. */
  protocolVersion: 3
  /** Version of the signed DHT membership payloads (offers, leases and links). */
  catalogSchemaVersion: 2
  transport: "iroh"
  /** Public Iroh relay URL. No shared token is distributed. */
  relayUrl: string
  /** HTTPS endpoint where a worker enrolls its signed EndpointId. */
  enrollmentUrl: string
  /** Public libp2p Kademlia bootstrap peers for autonomous placement. */
  catalogDhtBootstraps: string[]
  /** TUF trust bootstrap and content endpoints for selective layer downloads. */
  modelRegistry: {
    rootUrl: string
    rootSha256: string
    metadataUrl: string
    targetsUrl: string
  }
}

export interface SwarmEntry {
  /** Identifiant stable, lu depuis le label `fabi.swarm.id`. */
  id: string

  /** Nom lisible (label `fabi.swarm.name`). Tombe sur `id` si absent. */
  name: string

  /** URL HTTP du scheduler (label `fabi.swarm.url`). Sans trailing slash. */
  schedulerUrl: string

  /** EndpointId Iroh v3 (ou PeerID Lattica historique). `null` si indisponible. */
  schedulerPeer: string | null

  /**
   * Identité SHA-256 canonique du manifeste de modèle servi par ce swarm V3.
   * Le Request Agent la vérifie avant toute planification ou génération.
   */
  modelSwarmId?: string | undefined

  /** Transport annoncé par le scheduler. Iroh est le transport produit v3. */
  networkTransport?: "iroh" | "lattica" | undefined

  /** Secret-free, complete bootstrap profile for a fresh V3 worker. */
  workerConnection?: WorkerConnectionProfile | undefined

  /** Modèle servi (label `fabi.swarm.model`). */
  model: string

  /** Statut du scheduler tel qu'annoncé par /cluster/status_json. */
  status: "online" | "offline" | "unknown"

  /** Statut applicatif moteur: "waiting" tant qu'aucune route ne sert, "available" sinon. */
  schedulerStatus: string | null

  /** Nombre de workers (peers GPU) actuellement connectés. */
  peers: number

  /** Somme des VRAM annoncées par les peers, en GB. */
  totalVramGb: number

  /** Fenêtre maximale (prompt + génération) d'une route complète à swarm idle. */
  maxContextTokens?: number | undefined

  // --- État riche d'orchestration (lu au scan, fan-out via SSE) ---
  // Permet aux clients (IDE/CLI) d'afficher un écran de connexion fidèle SANS
  // poller le scheduler eux-mêmes : un seul scan registry → tous les clients.

  /** Le scheduler attend encore des nœuds pour bootstrapper le pipeline. */
  needMoreNodes?: boolean | undefined

  /** Seuil minimal de nœuds pour démarrer le bootstrap. */
  initNodesNum?: number | undefined

  /** Dernier résultat de bootstrap : 'pending'|'success'|'failed_capacity'|'deferred_not_enough_nodes'. */
  lastBootstrapResult?: string | null | undefined

  /** Nœuds actifs dans le pipeline (node_state === 'active'). */
  nodesActive?: number | undefined

  /** Nœuds encore en initialisation (loading_phase joining/initializing). */
  nodesInitializing?: number | undefined

  /** Nombre total de routes/pipelines connues par le scheduler. */
  pipelineCount?: number | undefined

  /** Nombre de routes/pipelines réellement prêtes à servir. */
  pipelineReadyCount?: number | undefined

  /** True uniquement si au moins un pipeline est prêt côté scheduler. */
  pipelineReady?: boolean | undefined

  /** True si la table de routage est construite et utilisable. */
  routingReady?: boolean | undefined

  /** Capacité totale annoncée par les pipelines prêts. */
  pipelineCapacityTotal?: number | undefined

  /** Requêtes actuellement en cours sur les pipelines prêts. */
  pipelineCapacityCurrent?: number | undefined

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
