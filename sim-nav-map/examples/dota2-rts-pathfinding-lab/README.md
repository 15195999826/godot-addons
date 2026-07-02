# Dota2 RTS Pathfinding Lab

> **Status: FABLE MOTION (2026-07-02).**
> The motion system was rebuilt from scratch. Paths know only the static
> world; unit-vs-unit avoidance is a per-tick positional separation solve.
> Two unit states (IDLE / MOVING), synchronous planning, and every order
> terminates in bounded time.

This lab is a Dota2/LoL-style movement-policy example for `sim-nav-map`:
continuous-space movement on a navigation grid with static obstructions and
contact-resolved unit collision.

## Try It

- Manual scene: `frontend/dota2_pathfinding_lab.tscn` — open in the Godot
  editor, press F6. Right-click to move, drag to select, keys 2/3/4 to edit
  the map live.
- Auto demo: `frontend/dota2_ai_command_demo.tscn` — F6 and watch a scripted
  Layer 2 command source drive lane moves, target switches, chase/retreat,
  and cancel on a loop.

## Motion Model (Fable)

Full design: [docs/design-notes/fable-motion-design.md](docs/design-notes/fable-motion-design.md).

- **One movement rule**: turn toward the tracking point (turn-rate capped),
  walk along facing with a continuous alignment speed ramp (Dota2 action-cone
  feel, no binary gate). No sideways displacement exists anywhere. Contact
  steering (default on, panel toggle) extends this to squeezing past
  non-yielding bodies: the desired heading biases around the contact so the
  unit walks around it — facing follows the squeeze instead of the body
  translating sideways.
- **Commit-then-resolve**: units step by intent, then an iterative separation
  solve splits overlapping pairs (pushability-weighted, head-on lateral bias)
  and projects bodies out of statics/bounds. Overlap cannot persist.
- Push flavor is a live-tunable engine setting (`pushability_moving` /
  `pushability_idle`): **Soft (LoL)** movers shove idle units aside;
  **Hard (Dota2)** stopped units are solid bodies (creep-blocking works).
  The lab panel has sliders + presets; integrating projects set the fields
  on their `Dota2LabMotionEngine`. Movers always lane-sort through opposing
  streams and round unpushable blockers via contact sliding.
- **Bounded termination**: arrive / arrive-partial (canonicalized goal) /
  arrive-crowded (goal buried in a crowd) / one replan then stalled-fail.
  There is no holding state and no forever-retry.
- Group commands fan one click out into deterministic nearby per-unit targets
  (command-layer concern, in `Dota2LabWorld`).
- `sim-nav-map` core stays policy-free; all movement policy lives in
  `logic/dota2_lab_motion_engine.gd`.

`example/dota2-auto-battle` (LGF) drives the same engine through
`Dota2MovementAdapter`.

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

Coverage: move basics (arrival/canonicalization/cancel/no-sideways guard),
separation invariant (head-on, squads crossing, coincident spawn, static
projection), crowds and blockers, stall watchdog, target fanout, AI command
source, frontend UI ops.

The scene can also run with DevAgent Debug Mode:

```text
--dev-agent
--dev-agent-session=<id>
```

Supported raw DevAgent ops include `capture`, `click_at`, `drag_at`, `tap_key`,
`inspect_controls`, `inspect_tree`, and `dump_node`. Scene ops:

- `dump_scene_state`
- `export_debug_log`

HUD reading: selected units draw their remaining path in green; each unit has
a facing arrow (orange while turn-limited), a state dot (grey IDLE / green
MOVING), and a red ring only for hard-failed orders (`no_path` / `stalled` —
a cancel is not an error). The Motion panel shows the live separation-solve
residual, which should read 0.00 at rest.

## Development Docs

- Motion design: [docs/design-notes/fable-motion-design.md](docs/design-notes/fable-motion-design.md)
- Layer 2 AI control plan: [docs/design-notes/layer-2-ai-control-plan.md](docs/design-notes/layer-2-ai-control-plan.md)
- Route history: [docs/development-plan.md](docs/development-plan.md)
