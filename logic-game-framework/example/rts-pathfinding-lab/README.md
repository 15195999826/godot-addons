# RTS Pathfinding Lab

This is an isolated experiment for 0 A.D.-style pathfinding ideas. It is not a production pattern for `rts-auto-battle`.

## Scope

- `logic/`: headless pathfinding and movement simulation.
- `frontend/`: playable Godot scene using the same logic.
- `tests/`: smoke tests for path shape and movement metrics.

The lab keeps logic and presentation separated so path behavior can be tested without opening the editor.

## Play

Open:

```text
addons/logic-game-framework/example/rts-pathfinding-lab/frontend/rts_pathfinding_lab.tscn
```

Controls:

- `1`: select/move mode.
- Left click: select one unit.
- Left drag: box select units.
- Right click: move selected units. If nothing is selected, all blue units move.
- `2`: place static obstacle mode, then left click to place.
- `3`: place red blocker mode, then left click to place.
- `4`: erase mode, then left click near an obstacle/blocker.
- `A`: select all blue units.
- `C`: clear movement traces.
- `R`: reset the default scenario.
- `Space`: pause/resume.
- `G`: toggle group filter.
- `D`: toggle dynamic unit avoidance.

## Smoke

```powershell
./tools/run_tests.ps1 rtslab/smoke
```
