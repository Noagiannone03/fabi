import { copyFileSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const launcherRoot = join(here, "..")
const metaRoot = join(launcherRoot, "..", "..")

const src = join(metaRoot, "integration", "fabi-cli-config", "opencode.fabi.jsonc")
const destDir = join(launcherRoot, "dist", "config")
const dest = join(destDir, "opencode.fabi.jsonc")

mkdirSync(destDir, { recursive: true })
copyFileSync(src, dest)
