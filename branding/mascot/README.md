# Mascotte Fabi — la loutre

Fabi est représentée par une **loutre de mer** flottant sur le dos. C'est l'animal le plus
sympathique du règne animal : il flotte tranquille, mange des coquillages sur son ventre,
et **se tient les pattes avec ses ami·es pour ne pas dériver pendant la sieste**.

C'est exactement la métaphore d'un swarm P2P :
- chaque utilisateur est une loutre
- le swarm c'est tenir les pattes ensemble
- la dérive solo, c'est ce qu'on évite

## Frames disponibles

| Fichier | Quand l'utiliser |
|---|---|
| `otter-idle.txt` | Au repos — boot, status idle |
| `otter-thinking-1.txt` | Animation "réflexion" frame 1 (bulle vide) |
| `otter-thinking-2.txt` | Animation "réflexion" frame 2 (bulle ⋅) |
| `otter-thinking-3.txt` | Animation "réflexion" frame 3 (bulle ⋅⋅⋅) |
| `otter-connected.txt` | Connecté au swarm (deux loutres se tiennent les pattes) |
| `otter-error.txt` | Erreur — loutre qui dort / triste |
| `otter-mini.txt` | Petite version inline pour status bar / footer |

## Convention de coloration

Quand on rend la mascotte dans la TUI, on colorie selon la palette `theme-fabi.json` :

| Partie de la loutre | Couleur |
|---|---|
| Corps (caractères pleins ▄ ▀ █) | `fabi_otter` |
| Ventre / accents clairs (caractères ░ ▒) | `fabi_cream` |
| Yeux, nez | `fabi_otter` foncé ou noir terminal |
| Eau (~) | `fabi_ocean` |
| Reflets soleil ✦ ✧ | `fabi_sunset` |

## Usage technique (en attendant l'intégration TUI)

Pour afficher la mascotte au boot du launcher :

```ts
import { readFileSync } from "node:fs"
import { join } from "node:path"

const otter = readFileSync(
  join(__dirname, "../../../branding/mascot/otter-idle.txt"),
  "utf-8",
)
console.log(otter)
```

Pour animer la "réflexion" (1 frame toutes les 400 ms) :

```ts
const frames = ["otter-thinking-1.txt", "otter-thinking-2.txt", "otter-thinking-3.txt"]
let i = 0
const tick = setInterval(() => {
  process.stdout.write("\x1B[H\x1B[J") // clear screen
  process.stdout.write(loadFrame(frames[i]))
  i = (i + 1) % frames.length
}, 400)
// clearInterval(tick) quand la réponse arrive
```

L'intégration dans le TUI Ink (React-CLI) viendra plus tard quand on touchera
au code de `packages/fabi-cli/`. Pour le launcher, le rendu plain-stdout suffit.
