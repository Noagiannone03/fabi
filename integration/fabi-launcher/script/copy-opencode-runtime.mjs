import { chmodSync, copyFileSync, existsSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const launcherRoot = join(here, "..")
const metaRoot = join(launcherRoot, "..", "..")
const opencodeRoot = join(metaRoot, "packages", "fabi-cli", "packages", "opencode")

const platformMap = {
  darwin: "darwin",
  linux: "linux",
  win32: "windows",
}
const archMap = {
  x64: "x64",
  arm64: "arm64",
  arm: "arm",
}

const platform = platformMap[process.platform] ?? process.platform
const arch = archMap[process.arch] ?? process.arch
const binary = process.platform === "win32" ? "opencode.exe" : "opencode"
const source = join(opencodeRoot, "dist", `opencode-${platform}-${arch}`, "bin", binary)

if (!existsSync(source)) {
  throw new Error(`Runtime introuvable: ${source}. Lance d'abord: bun run build --single --skip-install --skip-embed-web-ui`)
}

const destDir = join(launcherRoot, "dist", "runtime")
const dest = join(destDir, binary)
mkdirSync(destDir, { recursive: true })
copyFileSync(source, dest)
if (process.platform !== "win32") chmodSync(dest, 0o755)
