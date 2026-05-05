# branding/

Assets visuels de marque Fabi. Réutilisés par :

- `packages/fabi-cli/` (banner TUI, thème par défaut)
- L'installeur (futur)
- La landing page `voidswarm.io` (futur)

## Fichiers

| Fichier | Usage |
|---|---|
| `ascii-banner.txt` | Banner ASCII affiché au boot du CLI/TUI |
| `theme-fabi.json` | Thème de couleurs au format OpenCode |
| `theme-preview.md` | Aperçu visuel du thème (mémo des choix) |

## Convention

Quand on a besoin du banner ou du thème dans le code forké, **on importe depuis ce dossier**
plutôt que de dupliquer. Comme ça :

1. Modification = un seul endroit
2. Pas de conflit lors des syncs upstream (les fichiers d'origine restent intouchés autant que possible)
3. L'identité visuelle vit hors du code applicatif

Pour utiliser le thème dans OpenCode forké :

```bash
mkdir -p ~/.config/opencode/themes
cp branding/theme-fabi.json ~/.config/opencode/themes/
echo '{"theme": "fabi"}' > ~/.config/opencode/config.json
```

(à automatiser plus tard via un postinstall script.)
