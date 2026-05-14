# Dota2 RTS Pathfinding Lab

> **Status: BASELINE CAPTURED (2026-05-13).**
> Layer 1 manual frontend exists and is usable for investigation, but it is not
> approved as good-feel behavior. Layer 2 AI control stays frozen.

This lab is a Dota2/LoL-style movement-policy example for `sim-nav-map`:
continuous-space movement on a navigation grid with static and dynamic
obstructions.

## Current Baseline

- Manual scene: `frontend/dota2_pathfinding_lab.tscn`
- Baseline commits: parent repo `2229aad`, `addons` submodule `7cc09df`
- Implemented: manual controls, explicit motion FSM, debug HUD, JSON export,
  DevAgent debug adapter, and `dota2lab/smoke`.
- Known state: the current motion behavior can feel poor and can produce
  bug-like failures during target switching or group movement. Treat that as
  the baseline to stabilize, not as an approved final feel.

## Motion Contract

- Hard-block all units, including allies.
- No push pressure, no friendly walk-through, no phasing.
- Blocked movement stops and asks for a repath.
- Commands are individual per unit.
- `sim-nav-map` core stays policy-free; retry, stop, repath, and failure policy
  live in this lab.

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

## Development Docs

- Active route: [docs/development-plan.md](docs/development-plan.md)
- Historical motion design: [docs/design-notes/motion-controller-design.md](docs/design-notes/motion-controller-design.md)

Keep this README short. Put new development decisions, evidence, and repair
plans in `docs/development-plan.md`.
