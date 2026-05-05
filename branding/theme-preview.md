# Thème Fabi — palette de référence

> Inspiration : une loutre flottant sur le dos au coucher de soleil sur l'océan.
> Couleurs chaudes (loutre, soleil) + bleus (océan) + crème (ventre de loutre).

| Token | Hex | Usage |
|---|---|---|
| `fabi_sunset` | `#FF8C42` | Couleur primaire — accents, titres, CTA, banner |
| `fabi_sunset_dim` | `#E07534` | Variante mode light |
| `fabi_ocean` | `#00B4D8` | Secondaire — sélection, info, swarm |
| `fabi_ocean_dim` | `#0086A8` | Variante mode light |
| `fabi_ocean_deep` | `#1A6FA8` | Borders, encadrés profonds |
| `fabi_cream` | `#FFE5B4` | Accent doux — ventre de loutre, highlights |
| `fabi_cream_dim` | `#E6CB99` | Variante |
| `fabi_otter` | `#8B5A3C` | Brun loutre — texte mode light, mascotte |
| `fabi_otter_light` | `#A77F5C` | Variante texte secondaire |
| `fabi_seafoam` | `#88C0A8` | Success — vert doux d'algue |
| `fabi_amber` | `#FFB347` | Warning |
| `fabi_salmon` | `#FF6B6B` | Error — saumon, pas rouge agressif |
| `fabi_text` | `#F5E6D3` | Texte principal sombre — crème lumineuse |
| `fabi_text_dim` | `#A77F5C` | Texte secondaire |
| `fabi_text_muted` | `#6B5A4A` | Texte très discret |
| `fabi_bg` | `none` | Inherit terminal background |
| `fabi_bg_panel` | `#1B1410` | Panels distincts (chocolat très sombre) |

## Aperçu par usage

### Banner / titre principal
- Fond : terminal (none)
- Texte titre : `fabi_sunset` (orange chaud)
- Mascotte loutre : `fabi_otter` (corps) + `fabi_cream` (ventre) + `fabi_ocean` (eau)

### Status bar / footer
- Fond : `fabi_bg_panel`
- Texte : `fabi_text_dim`
- Indicateur "connecté au swarm" : `fabi_seafoam` (success) ou `fabi_ocean`
- Compteur de peers : `fabi_cream`

### Chat / conversation
- Question utilisateur : `fabi_sunset` (proéminent, c'est toi qui parles)
- Réponse IA : `fabi_text` (lecture confortable)
- Code blocks : panel `fabi_bg_panel` avec border `fabi_ocean_deep`

### Erreurs et warnings
- Warning : `fabi_amber` (ambré, pas alarmant)
- Error : `fabi_salmon` (chaud, lisible, pas agressif comme un rouge pur)

## Pourquoi ces choix

- **Cohérence avec la mascotte** : la palette raconte une histoire (loutre + océan + sunset).
- **Chaleur** : les couleurs sont chaudes et accueillantes — Fabi est un IDE communautaire,
  pas un outil corporate froid.
- **Lisibilité** : `fabi_text` (#F5E6D3) sur fond sombre passe le contraste WCAG AA.
- **Mode light viable** : avec `fabi_otter` comme texte sur fond clair, ça fonctionne aussi.
- **Pas de rouge pur** : `fabi_salmon` au lieu de `#FF0000` pour les errors, plus doux,
  cohérent avec la palette chaude.

## À tester

- [ ] Lecture sur terminal blanc (gnome-terminal light)
- [ ] Lecture sur terminal noir (iTerm2 dark)
- [ ] Affichage avec couleurs ANSI 256 (qui dégrade `fabi_sunset` en orange ANSI le plus proche)
- [ ] Daltonisme deutéranopie : le contraste ocean/sunset reste lisible
- [ ] Daltonisme protanopie : success vs error reste différenciable (vert vs salmon)
