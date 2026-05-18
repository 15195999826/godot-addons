# Attributes Skeleton

Planned contents:

- `Dota2BattleActorAttributeSet`: common battle actor stats such as `hp` and
  `max_hp`, plus shared combat stats such as `armor` if the damage model uses it
  across units, towers, and buildings.
- `Dota2UnitAttributeSet`: unit stats such as `attack_damage`, `move_speed`,
  `attack_range`, `attack_interval_ms`, and `aggro_range`; common `armor` is
  inherited from `Dota2BattleActorAttributeSet` if the damage model uses it.
- `Dota2TowerAttributeSet`: tower combat stats such as `attack_damage`,
  `attack_range`, `attack_interval_ms`, `projectile_speed`, and `aggro_range`.
- `Dota2BuildingAttributeSet`: non-unit attackable building stats; it should
  inherit common HP/armor but should not inherit unit movement stats.
- optional example-local `attributes_config.gd` and `generated/` directory when
  the LGF AttributeSet generator supports per-example ownership.

This directory should model an AttributeSet family, not a unit-only attribute
bag. Add a stat to the shared battle set only when every relevant battle actor
can use that stat coherently. Otherwise add it to the concrete actor family's
typed AttributeSet.

Preferred long-term ownership is example-local config/output under this
directory. Until the generator boundary is fixed, M1 may use one of these
temporary routes:

- example-local generated files if the generator is refactored first;
- generated-compatible classes that directly extend `BaseGeneratedAttributeSet`;
- clearly prefixed DOTA2 entries in the shared
  `addons/logic-game-framework/example/attributes/attributes_config.gd` path if
  that is the current practical route.

If the shared path is used, it must be documented as temporary debt and must not
change existing hex/rts generated names or semantics.
