# SC2 RTS Pathfinding Lab

> **Status: PLANNING.** Code not yet started. This README captures the design
> decisions reached during planning so future-Claude (or future-you) can resume
> without re-deriving them.

This lab is the planned StarCraft II-style movement-policy example for
`sim-nav-map`. It sits alongside `0ad-rts-pathfinding-lab` (push-pressure
dynamics) and `dota2-rts-pathfinding-lab` (single-unit hard-block) as the
**mid-complexity** of the three planned lab variants.

## Three-Lab Complexity Gradient

| Lab | Collision policy | Command model | Algorithmic pressure point | Target unit density |
|---|---|---|---|---|
| `0ad-rts-pathfinding-lab` | hard + push pressure dynamics | individual, with formation commands | per-frame push force solver | 100–300 |
| **`sc2-rts-pathfinding-lab`** (this lab) | hard, no push | group / cluster commands | command-level cluster pathfinding | 20–100 |
| `dota2-rts-pathfinding-lab` (planned) | hard, no push | individual per unit | none — low density solves it | 10–40 |

The three labs are intentionally **independent**: they share `sim-nav-map` core
(long path / vertex path / obstruction / LoS) but their `logic/` directories do
**not** share base classes. The motion abstraction point differs too sharply
between paradigms to be unified.

## Motion Contract (SC2 paradigm)

- **Collision = hard block all units, including allies.** Same as
  `dota2-rts-pathfinding-lab`. No phasing, no push pressure.
- **No per-frame separation dynamics.** When a unit attempts to step into an
  occupied cell, it stops; the *intelligence* lives at the command layer, not
  at the motion layer.
- **Group / cluster movement is the defining feature.** A single move command
  can target multiple units. The command layer is responsible for:
  - **Cluster pathfinding.** Compute one long path for a cluster
    representative, reuse it for nearby cluster members where possible.
  - **Destination packing.** Distribute target slots across the destination
    area so the group does not converge on a single point.
  - **Arrival formation.** As the cluster nears the destination, individual
    unit slots are committed and units fan out to their assigned spots.
- **Bumped-then-repath** is the fallback at the motion layer (same as
  `dota2-rts-pathfinding-lab`); with cluster movement this should be **rare**
  — most arrivals should resolve via the destination packing layer.

Motion controller LOC estimate: **~600–900 lines** (motion is similar to
`dota2-rts-pathfinding-lab` but the cluster / command layer is more involved;
cluster code lives in separate files under `logic/`).

## Reference Source — Not Available

Unlike `0ad-rts-pathfinding-lab` (which has `docs/references/0ad-source/`),
**there is no off-the-shelf open-source reference for SC2-style group
movement.** SC2 is closed-source and the technique is described mainly in
Blizzard GDC talks and indirect academic literature.

Likely starting points for *design discussion* — not for direct porting:

- HPA\* (Hierarchical Pathfinding A\*) for cluster representative path.
- Flow fields (Supreme Commander 2 / Planet Wars style) as an alternative
  cluster representation.
- RVO2 / ORCA literature for local separation — **important caveat**: only
  consult for *cluster-internal* destination packing or arrival fanning; do
  not slip back into push-pressure dynamics at the motion layer.

Design is to be developed *in this lab* and recorded in
`docs/design-notes/`.

## Two-Layer Architecture

Same structure as `dota2-rts-pathfinding-lab`:

```text
                  sc2-rts-pathfinding-lab
                            │
            ┌───────────────┴───────────────┐
            │                               │
       Layer 1 (manual)              Layer 2 (AI control)
       frontend/                     ai/    [not started]
            │                               │
            └───────────────┬───────────────┘
                            │
            shared logic/ (motion / collision / cluster / pathfind)
```

Layer 1 is the current scope; Layer 2 is frozen until Layer 1 is approved.

**Layer separation rule:**

> `logic/` must not know whether its `move_to(units[], target)` caller is a
> human or an AI. Layer 2 may only call public command APIs; it may not edit
> `logic/` internals.

## Layer 1 Approval Criteria

Layer 1 is "OK" — and Layer 2 may then start — when **all** of the following
hold:

1. **Group arrival completeness.** Commanding a 12-unit group to a clear
   destination, all 12 reach their assigned destination slot within bounded
   time.
2. **Cluster path reuse.** When a cluster moves together, individual unit
   long-path requests are reused / shared across cluster members.
   Path-request count per cluster should be order-of-magnitude lower than
   per-unit path counts (concrete threshold TBD during implementation).
3. **Destination packing correctness.** Group destination spreads across the
   target area; no two units share a final slot.
4. **Narrow corridor traversal.** A 12-unit group commanded through a
   corridor wide enough for 2 units file-walks through, no permanent
   deadlock.
5. **Mixed-size unit grouping.** A group containing units of two different
   footprints / radii reaches the destination without one size class jamming
   the other.

**Plus**: every corner case the developer discovers during manual play must be
converted to a scripted smoke in `tests/smoke/`.

## Layer 2 (AI control) — Open Question

For `dota2-rts-pathfinding-lab`, Layer 2 corresponds directly to the planned
MOBA auto-battle end-game.

For **this lab Layer 2 is purely a study target** — does SC2 group-movement
add anything when each AI controls its own unit? The MOBA auto-battle goal
does **not** need group movement (each unit has an AI-decided move order, no
group command), so Layer 2 here may be **dropped entirely** based on Layer 1
findings.

## Planned Directory Layout

```text
sc2-rts-pathfinding-lab/
├── README.md                          (this file)
├── docs/
│   └── design-notes/                  (cluster pathfinding, destination
│                                      packing, etc.)
├── logic/
│   ├── sc2_lab_world.gd
│   ├── sc2_lab_unit.gd
│   ├── sc2_lab_motion_controller.gd
│   ├── sc2_lab_move_order.gd
│   ├── sc2_lab_cluster.gd             (cluster representation)
│   ├── sc2_lab_cluster_planner.gd     (cluster long-path + dest. packing)
│   └── sc2_lab_pathfinder_wrapper.gd
├── frontend/
│   ├── sc2_pathfinding_lab.tscn
│   └── sc2_pathfinding_lab.gd
├── ai/                                (empty until / unless Layer 2)
└── tests/
    ├── test_groups.json
    ├── smoke/
    │   └── (Layer 1 regression smokes)
    └── ai_smoke/                      (empty until / unless Layer 2)
```

## Controls (planned, follows `0ad-rts-pathfinding-lab` conventions, extends for group selection)

- `1`: command mode. Left-click selects, **drag selects forms a cluster**,
  right-click issues a group move command. No selection ⇒ moves all mobile
  units as one cluster.
- `2`: place static obstacle.
- `3`: place non-mobile blocker unit.
- `4`: erase the nearest editable obstacle / blocker.
- `A`: select all mobile units (as one cluster).
- `Ctrl+1..9`: bind current selection to a hotkey group (SC2 hotkey
  conventions).
- `1..9` (with selection bound): recall hotkey group.
- `C`: clear traces.
- `R`: reset scene.
- `Space`: pause / resume simulation.
- `Export log`: write a JSON debug snapshot.

## Smoke (planned)

```powershell
./tools/run_tests.ps1 sc2lab/smoke
```

## Out of Scope (Things This Lab Will Not Do)

- Push pressure / dynamics (use `0ad-rts-pathfinding-lab` for that).
- Single-unit-only command paradigm (use `dota2-rts-pathfinding-lab` for
  that).
- Phasing / friendly walk-through.
- Real-time RVO / ORCA at the motion layer (motion stays "stop on hard
  block").
- Replication of any specific SC2 game mechanic (buildings, abilities, fog
  of war, economy) — this is a *pathfinding* lab.
