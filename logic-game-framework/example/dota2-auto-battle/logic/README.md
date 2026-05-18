# Logic (M1 implemented)

> M1 已落地：`actors/` `controllers/` `ability/` `actions/` `ai/` `config/`
> `movement/` `systems/` `attributes/`。变更见 [../CHANGELOG.md](../CHANGELOG.md)。
> 下列为原始规划，保留作设计追溯。

Planned contents:

- `actors/`: unit actors and runtime state.
- `attributes/`: DOTA2 actor AttributeSets and any example-local attribute
  schema/generated files.
- `controllers/`: per-unit brains, persistent current intents, and intent
  lifecycle state.
- `config/`: unit type and skill metadata.
- `ai/`: lane brain and targeting intent.
- `actions/`: combat actions and state mutations.
- `systems/`: lane waves, targeting, combat, death cleanup.
- `movement/`: adapter from battle intent to movement implementation.

Logic should depend on core/LGF, but frontend should only read logic state or
events.

Actor stats should use LGF AttributeSet. Do not add per-stat forwarding getters
to actors. The long-term AttributeSet target is example-local config/output, but
M1 may temporarily use the shared example generator/config with clearly prefixed
DOTA2 names if that is the current practical route. That coupling must be
documented as debt and must not change existing hex/rts semantics.

M1/M2 should not introduce a command/order layer. Autonomous units use
controllers that decide only when needed, store a persistent `current_intent`,
and let movement/ability systems advance that intent every fixed tick. Systems,
Abilities, and Actions remain the only mutation authority.
