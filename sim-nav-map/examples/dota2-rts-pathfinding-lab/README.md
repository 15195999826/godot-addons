# Dota2 RTS Pathfinding Lab

> **Status: LAYER 2 COMMAND-SOURCE SMOKE (2026-05-15).**
> Layer 1 manual frontend exists and is usable for investigation. Multi-unit
> command feel has a narrow command-layer fanout baseline. Layer 2 now has a
> deterministic automatic command-source smoke driver; it still does not own
> movement policy.

This lab is a Dota2/LoL-style movement-policy example for `sim-nav-map`:
continuous-space movement on a navigation grid with static and dynamic
obstructions.

## Current Baseline

- Manual scene: `frontend/dota2_pathfinding_lab.tscn`
- Visible Layer 2 demo scene: `frontend/dota2_ai_command_demo.tscn`
- Baseline reference: the `addons` submodule commit containing this README,
  tracked by the parent repo commit that points at it.
- Implemented: manual controls, explicit motion FSM, ticket lifecycle
  diagnostics, same-tick command-layer target fanout, local short-detour
  subgoals, debug HUD, JSON export, DevAgent debug adapter, and
  `dota2lab/smoke`.
- Verification: `./tools/run_tests.ps1 dota2lab/smoke` passes with
  `PASS 6 / FAIL 0 / TIMEOUT 0`.
- Known state: single-unit movement remains a strict hard-block baseline.
  Multi-unit commands are a lab convenience with target fanout, not formation
  or group movement. Narrow-gap and mixed-obstacle scenarios can still end in
  bounded `FAILED` states.
- Layer 1.1 movement-feel contract:
  [docs/design-notes/movement-feel-policy.md](docs/design-notes/movement-feel-policy.md)
- Layer 2 automatic command-source plan:
  [docs/design-notes/layer-2-ai-control-plan.md](docs/design-notes/layer-2-ai-control-plan.md)

## Visible Demo

Open `frontend/dota2_ai_command_demo.tscn` in the Godot editor and press F6.
It uses the same renderer as the manual lab scene, but starts an automatic
Layer 2 command-source script on load. The script repeatedly demonstrates lane
movement, target switching, chase/retreat, and cancel commands, then loops.

## Motion Contract (v2)

Full contract: [docs/design-notes/movement-feel-policy.md](docs/design-notes/movement-feel-policy.md).

- Units are real obstacles (no phasing), but a unit-blocked step first retries
  with a ½-cell clearance relax (brush-past margin), then tries a validated
  **tangential slide** around the blocker — a moving unit never parks against
  another unit. Only when both fail does it escalate to a short-detour subgoal.
- **Crowded arrive**: a blocked unit already within a crowd ring of its goal
  completes; a group ordered to one point settles as concentric rings.
- **HOLDING**: when the recovery budget is spent, the unit keeps its order,
  holds position, and retries a long path at a bounded rate. Removing a
  blocker lets it resume by itself. `FAILED` exists only for statically
  unreachable goals — other units in the way never terminally fail an order
  (`max_retry_exceeded` no longer exists).
- No push pressure: sliding moves only the mover, blockers are never displaced.
- Commands are individual per unit.
- Units keep authoritative facing. They use the Dota2 `11.5°` action cone:
  movement can start once the next waypoint is inside that front cone, then the
  unit keeps rotating while moving. The raw Dota2 `0.6` per `0.03s` turn-rate
  reference is kept in code, but the lab default runs at half-speed so the small
  facing arrows do not look like instant turns.
- Multi-unit commands may fan out one click target into deterministic nearby
  per-unit targets. All independent move orders start on the command tick.
- `sim-nav-map` core stays policy-free; slide, relax, crowd-arrive, holding,
  retry, and repath policy live in this lab.

## Controls

- `1`: command/select mode. Left-click selects; drag selects; right-click moves.
- `2`: place static obstacle.
- `3`: place non-mobile blocker unit.
- `4`: erase nearest editable obstacle or blocker.
- `A`: select all mobile units.
- `C`: clear traces.
- `E`: export JSON debug snapshot.
- `R`: reset scene.
- `Space`: pause or resume.

## Debug

Run the smoke group:

```powershell
./tools/run_tests.ps1 dota2lab/smoke
```

The scene can also run with DevAgent Debug Mode:

```text
--dev-agent
--dev-agent-session=<id>
```

Supported raw DevAgent ops include `capture`, `click_at`, `drag_at`, `tap_key`,
`inspect_controls`, `inspect_tree`, and `dump_node`. Scene ops:

- `dump_scene_state`
- `export_debug_log`

The HUD distinguishes active path source: long paths are green, short paths are
cyan, and the last short subgoal is shown as a cyan ring for selected units.
Each unit also draws a facing arrow; orange means it is currently rotating
before movement.

## Development Docs

- Active route: [docs/development-plan.md](docs/development-plan.md)
- Movement-feel contract: [docs/design-notes/movement-feel-policy.md](docs/design-notes/movement-feel-policy.md)
- Layer 2 AI control plan: [docs/design-notes/layer-2-ai-control-plan.md](docs/design-notes/layer-2-ai-control-plan.md)
- Historical motion design: [docs/design-notes/motion-controller-design.md](docs/design-notes/motion-controller-design.md)

Keep this README short. Put new development decisions, evidence, and repair
plans in `docs/development-plan.md`.
