// Affichage du banner FABI + mascotte loutre.
// Lit les fichiers depuis branding/ qui est à la racine du méta-projet
// (3 niveaux au-dessus de ce fichier compilé : dist/banner.js).

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { sunset, ocean, cream, otter, dim } from "./colors.js"

const HERE = dirname(fileURLToPath(import.meta.url))

/** Cherche la racine du méta-projet en remontant jusqu'à trouver branding/. */
function findBrandingDir(): string | null {
  const candidates = [
    join(HERE, "..", "..", "..", "..", "branding"),  // dist/banner.js → integration/fabi-launcher/dist → meta
    join(HERE, "..", "..", "..", "branding"),        // src/banner.ts (dev mode)
    join(HERE, "..", "..", "branding"),              // fallback
    join(process.cwd(), "branding"),                 // si lancé depuis racine méta
  ]
  for (const c of candidates) {
    try {
      readFileSync(join(c, "ascii-banner.txt"), "utf-8")
      return c
    } catch { /* try next */ }
  }
  return null
}

function readSafe(path: string): string | null {
  try {
    return readFileSync(path, "utf-8")
  } catch {
    return null
  }
}

export interface BannerInfo {
  scheduler: string
  model: string
}

export function showBanner(info: BannerInfo): void {
  const brand = findBrandingDir()
  process.stdout.write("\n")

  if (brand) {
    const banner = readSafe(join(brand, "ascii-banner.txt"))
    const otterArt = readSafe(join(brand, "mascot", "otter-idle.txt"))
    if (banner)    process.stdout.write(sunset(banner) + "\n")
    if (otterArt)  process.stdout.write(otter(otterArt) + "\n")
  } else {
    process.stdout.write(sunset("  Fabi") + "\n\n")
  }

  process.stdout.write(dim(`  scheduler  ${info.scheduler}`) + "\n")
  process.stdout.write(dim(`  modèle     ${info.model}`) + "\n")
  process.stdout.write("\n")
}

export function showStatus(line: string): void {
  process.stdout.write(`  ${line}\n`)
}

export function showSeparator(): void {
  process.stdout.write(dim("  ─────────────────────────────────────────────") + "\n")
}
