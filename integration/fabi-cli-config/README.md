# integration/fabi-cli-config

Config opencode **pré-baker** pour Fabi : déclare le scheduler Aircarto comme
provider OpenAI-compatible et le pose comme modèle par défaut.

## Comment c'est branché

Le launcher `integration/fabi-launcher` pose l'env var `OPENCODE_CONFIG` vers
le chemin absolu de `opencode.fabi.jsonc` au moment de spawn opencode (cf
[`src/fabicli.ts`](../fabi-launcher/src/fabicli.ts)).

opencode supporte nativement cette env var (cf
`packages/fabi-cli/packages/core/src/flag/flag.ts`), donc **zéro patch source**
côté fork — sync upstream parfait.

## Override par l'utilisateur

La config Fabi est chargée AVANT le `~/.config/opencode/opencode.json` de
l'utilisateur, qui est mergé par-dessus. L'utilisateur peut donc :

- Ajouter d'autres providers (`anthropic`, `openai`…) sans casser Fabi.
- Changer le modèle par défaut : `{"model": "anthropic/claude-3-7-sonnet"}`.
- Désactiver Fabi : `{"disabled_providers": ["fabi"]}`.

## Mise à jour du scheduler

Si l'IP/port ou la PeerID du scheduler change :

1. Mettre à jour `provider.fabi.api` dans ce fichier (URL HTTP).
2. Mettre à jour `DEFAULTS.scheduler` et `DEFAULTS.schedulerPeer` dans
   `integration/fabi-launcher/src/config.ts` (utilisé par le launcher pour le
   healthcheck et `parallax join -s`).
3. Rebuild le launcher (`npm run build` dans `integration/fabi-launcher`).

À terme : auto-discovery via un endpoint `GET /swarm.json` exposé par le
scheduler, qu'on lirait au boot pour peupler ces deux champs.
