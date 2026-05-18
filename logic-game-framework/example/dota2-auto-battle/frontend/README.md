# Frontend Skeleton

Planned contents:

- `dota2_lane_battle.tscn`
- live world view
- unit views
- HP bars
- attack/death feedback
- debug panels for tick/catch-up telemetry, selected actor state, current
  intent, movement state, basic attack Ability state, and recent events

Frontend must be read-only with respect to battle decisions. It can request scene
setup or debug controls, but it must not mutate combat, targeting, or movement
state directly.

Frontend render frames may run a small private logic clock block with elapsed
real time, but they do not own logic state. Rendering can interpolate snapshots;
it must not feed interpolated state back into combat decisions.

The first visible scene should favor observability over polish. It should make
the ARAM-like lane fight easy to debug: actor id/team/type, HP/maxHP, current
intent kind/status/target, next decision tick, movement/path/block reason,
basic attack cooldown/timeline state, and warning-level catch-up telemetry should
be visible or quickly inspectable.
