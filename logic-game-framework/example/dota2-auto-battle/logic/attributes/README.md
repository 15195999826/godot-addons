# Attributes — M1 implemented (shared generator + DOTA2 prefix, temporary debt)

## Current M1 state

The AttributeSet family is live and used by `Dota2UnitActor`:

- `Dota2BattleActorAttributeSet` — common battle-actor stats: `hp`, `max_hp`,
  with `hp <= max_hp` cross-attribute clamp owned by the AttributeSet (not actor
  setter code). Base of the family; future `Dota2TowerActor` /
  `Dota2BuildingActor` extend the same base view.
- `Dota2UnitAttributeSet` extends `Dota2BattleActorAttributeSet` — unit stats:
  `move_speed`, `attack_damage`, `attack_range`, `attack_interval_ms`,
  `aggro_range`.

`armor` is intentionally **not** generated yet: `actor-attributes.md` says keep
it planned-but-unused rather than invent a fake formula before a damage model
needs it. `Dota2TowerAttributeSet` / `Dota2BuildingAttributeSet` are not in M1
but the base→unit family shape does not block adding them later.

Spawn order sets `max_hp` before `hp` (`Dota2UnitActor._init`) so the
cross-clamp never clips a high-HP unit against the default max.

## Generator route taken (route 3) — TEMPORARY TECHNICAL DEBT

M1 uses **route 3** from `docs/design-notes/actor-attributes.md`: clearly
DOTA2-prefixed definitions added to the shared example generator config, and
generated into the shared example output directory:

- config (single source of truth):
  `addons/logic-game-framework/example/attributes/attributes_config.gd`
  → `"Dota2BattleActor"` and `"Dota2Unit"` set entries (DOTA2-prefixed).
- generated output:
  `addons/logic-game-framework/example/attributes/generated/dota2_battle_actor_attribute_set.gd`
  and `dota2_unit_attribute_set.gd`.

The generated files follow `AttributeSetGeneratorScript`'s exact emit format and
are reproducible by running that EditorScript in the editor against the shared
config (it is an `EditorScript`, so it cannot run in a `--headless` game
process; the editor's *File ▸ Run* / Tools menu regenerates byte-identical
output).

**Why this is debt:** the shared `example/attributes` config/output couples all
examples (hex / rts / dota2) through one config and one generated folder. The
long-term target is example-local ownership:

```
example/dota2-auto-battle/logic/attributes/attributes_config.gd
example/dota2-auto-battle/logic/attributes/generated/
```

**Debt invariants honored:** names are DOTA2-prefixed; existing hex/rts
generated names and semantics are unchanged; existing hex generated files are
not migrated (that is a separate future task, not M1).
