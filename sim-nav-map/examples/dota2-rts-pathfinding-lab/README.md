# Dota2 RTS Pathfinding Lab

> **Status: PHASE C BASELINE (2026-05-14).**
> Layer 1 manual frontend exists and is usable for investigation. Multi-unit
> command feel now has a narrow command-layer fanout baseline. Layer 2 AI
> control stays frozen.

This lab is a Dota2/LoL-style movement-policy example for `sim-nav-map`:
continuous-space movement on a navigation grid with static and dynamic
obstructions.

## Current Baseline

- Manual scene: `frontend/dota2_pathfinding_lab.tscn`
- Baseline reference: the `addons` submodule commit containing this README,
  tracked by the parent repo commit that points at it.
- Implemented: manual controls, explicit motion FSM, ticket lifecycle
  diagnostics, command-layer target fanout, deterministic command release
  scheduling, debug HUD, JSON export, DevAgent debug adapter, and
  `dota2lab/smoke`.
- Verification: `./tools/run_tests.ps1 dota2lab/smoke` passes with
  `PASS 4 / FAIL 0 / TIMEOUT 0`.
- Known state: single-unit movement remains a strict hard-block baseline.
  Multi-unit commands are a lab convenience with target fanout, not formation
  or group movement. Narrow-gap and mixed-obstacle scenarios can still end in
  bounded `FAILED` states.

## Motion Contract

- Hard-block all units, including allies.
- No push pressure, no friendly walk-through, no phasing.
- Blocked movement stops and asks for a repath.
- Commands are individual per unit.
- Multi-unit commands may fan out one click target into deterministic nearby
  per-unit targets and release those independent orders over a short cadence.
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
