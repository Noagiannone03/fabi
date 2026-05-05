# Architecture Decision Records (ADRs)

Décisions techniques importantes prises pour Fabi, archivées par numéro.

Format : on n'écrit pas un ADR pour chaque décision triviale. On en écrit pour les
choix qui :
- Sont **structurants** (auront des conséquences pendant ≥ 6 mois)
- Sont **non-évidents** (un futur lecteur ne devinera pas pourquoi ce choix)
- Ont eu des **alternatives sérieusement considérées**

## Index

| # | Titre | Date | Statut |
|---|---|---|---|
| [001](./001-fork-strategy.md) | Stratégie de fork pour OpenCode et Parallax | 2026-05-04 | accepté (modalités révisées par ADR 002) |
| [002](./002-pivot-fork-actif.md) | Pivot vers fork actif et appropriation du code OpenCode | 2026-05-05 | accepté |

## Convention

- Numérotation séquentielle : 001, 002, 003…
- Filename : `NNN-titre-court-en-kebab.md`
- Statuts possibles : `proposé`, `accepté`, `rejeté`, `superseded by ADR-XXX`
- On **n'efface jamais** un ADR — on le marque comme `superseded` si un nouveau
  remplace celui-ci.

## Template suggéré

```markdown
# ADR NNN — Titre

- **Date** : YYYY-MM-DD
- **Statut** : proposé / accepté / rejeté
- **Décideur** : Nom

## Contexte
...

## Question
...

## Options évaluées
### A. ...
### B. ...

## Décision
...

## Conséquences
### Positives
...
### Négatives à surveiller
...

## Ré-évaluation
À refaire si ...

## Références
...
```
