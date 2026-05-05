// Helpers ANSI minimalistes — pas de dépendance externe.
// Détection automatique du support couleur (TTY) avec fallback.

const ENABLED = process.stdout.isTTY && process.env.NO_COLOR === undefined

const C = (code: string) => (s: string): string =>
  ENABLED ? `\x1b[${code}m${s}\x1b[0m` : s

// Foreground 256-colors (codes alignés avec la palette theme-fabi.json)
export const sunset = C("38;5;208")   // ~#FF8C42
export const ocean  = C("38;5;39")    // ~#00B4D8
export const cream  = C("38;5;230")   // ~#FFE5B4
export const otter  = C("38;5;130")   // ~#8B5A3C
export const seafoam = C("38;5;108")  // ~#88C0A8
export const amber  = C("38;5;215")   // ~#FFB347
export const salmon = C("38;5;203")   // ~#FF6B6B
export const dim    = C("2")
export const bold   = C("1")

// Composables
export const ok    = (s: string) => seafoam("✓") + " " + s
export const warn  = (s: string) => amber("⚠")  + " " + s
export const error = (s: string) => salmon("✗") + " " + s
export const info  = (s: string) => ocean("ℹ")  + " " + s
