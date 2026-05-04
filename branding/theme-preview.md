# Thème Void-Swarm — palette de référence

| Token | Hex | Usage |
|---|---|---|
| `swarm_cyan` | `#00FFD1` | Couleur primaire — accents, titres, links |
| `swarm_cyan_dim` | `#00B894` | Variante moins saturée pour le mode light |
| `swarm_purple` | `#7C3AED` | Secondaire — borders, sélection |
| `swarm_purple_dim` | `#5B21B6` | Variante mode light |
| `swarm_pink` | `#F472B6` | Accent — sparingly |
| `swarm_amber` | `#FBBF24` | Warnings |
| `swarm_red` | `#EF4444` | Errors |
| `swarm_green` | `#10B981` | Success |
| `swarm_fg` | `#E5E7EB` | Texte principal |
| `swarm_fg_muted` | `#6B7280` | Texte secondaire |
| `swarm_bg` | `none` | Inherit terminal background |
| `swarm_bg_panel` | `#0F172A` | Panels distincts |

## Pourquoi ces choix

- **Cyan + violet** : palette "swarm/network/sci-fi" qui évoque le distribué et le mesh.
- **Background `none`** : on hérite du terminal de l'utilisateur. Le thème reste lisible en clair comme en sombre.
- **Pas de marron / jaune saturé** : on évite de ressembler à OpenCode (qui a déjà 20+ thèmes mainstream).
- **Contraste WCAG AA** sur fond sombre vérifié pour `swarm_fg` sur `swarm_bg_panel`.

## À tester

- [ ] Lecture sur terminal blanc (gnome-terminal light)
- [ ] Lecture sur terminal noir (iTerm2 dark)
- [ ] Affichage avec couleurs ANSI (256 colors vs truecolor)
- [ ] Daltonisme — le cyan/violet est OK, le rouge/vert pour success/error idem (variantes saturées différentes)
