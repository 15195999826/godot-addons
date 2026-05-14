# DevAgent Debug Mode Spec

> Status: v1 implemented baseline.
>
> Audience: future Codex/Claude sessions that will implement the `lomolib`
> example and create scene-specific debug adapters.
>
> Scope: development-time real-run debugging for Godot scenes. This is not a
> regression test framework.

## 1. Purpose

DevAgent Debug Mode lets an AI assistant drive a real running Godot scene during
development. It exists for three workflows:

1. Validate a newly developed feature once in a real scene, with screenshots and
   runtime evidence.
2. Debug UI interaction and layout from the user's perspective.
3. Explore an issue interactively by sending one command at a time, inspecting
   the current state, and deciding the next step from screenshots or dumps.

The important property is that the scene stays alive. A script can bootstrap the
scene into a useful state, but the primary workflow is interactive: observe,
operate, inspect, capture, repeat.

## 2. Non-Goals

DevAgent Debug Mode must not become:

- A CI or required regression test path.
- A replacement for `tools/run_tests.ps1`, smoke scenes, or deterministic
  logic tests.
- A production feature or player-facing automation system.
- A hidden shortcut that bypasses the real player input path when the goal is UI
  or user-experience validation.
- A framework-level dependency for game logic.

It can produce useful evidence, but it does not need stable PASS/FAIL semantics.
Long run time, manual interpretation, and exploratory branching are expected.

## 3. Design Principles

### 3.1 Debug layer, not game layer

The bridge is development tooling. It should live in `addons/lomolib` as reusable
debug infrastructure, while each game scene owns only a small adapter describing
scene-specific operations.

Game logic should not depend on DevAgent classes. DevAgent may depend on normal
scene APIs, input handlers, and debug-friendly read-only state access.

### 3.2 Real input first

For UI and user-path validation, DevAgent must inject real Godot input events via
`Viewport.push_input()`:

- mouse click, drag, wheel
- keyboard key press/release
- text input where needed

This is different from calling `button.pressed.emit()`, `_on_pressed()`, or game
commands directly. Real input covers Control hit testing, `mouse_filter`,
disabled state, modal windows, focus, `_gui_input`, `_input`,
`_unhandled_input`, and raycast paths.

Direct command APIs are allowed only when the debugging goal is pure logic or
state setup, not UI/user-path validation.

### 3.3 Raw operations plus scene operations

Every scene should support raw operations:

- `click_at`
- `drag_at`
- `tap_key`
- `wait_frames`
- `capture`
- `inspect_tree`
- `dump_node`

Scene-specific operations are optional accelerators:

- RTS: `select_units`, `right_click_world`, `click_minimap`
- Hex battle: `click_hex`, `select_actor`, `open_skill_menu`
- Editor tool: `click_timeline_keyframe`, `open_context_menu`

The raw layer must remain available because exploratory debugging often starts
before the correct semantic operation is known.

### 3.4 Observe before changing code

The bridge should make it cheap to inspect real runtime state before modifying
implementation code. At minimum it should support screenshots, node/control
dumps, and selected scene state dumps. The expected loop is:

```text
send command -> read outbox -> open screenshot/dump -> decide next command
```

## 4. Architecture

```text
Codex / developer
  -> user://dev-agent/sessions/<session-id>/inbox.jsonl

Godot DevAgentBridge
  -> reads commands
  -> calls DevAgentInputDriver / DevAgentScreenshot / DevAgentInspector
  -> delegates optional semantic ops to current DevAgentSceneOps
  -> writes outbox + artifacts

Codex / developer
  -> reads outbox.jsonl
  -> opens screenshots / dumps
  -> sends next command
```

Planned reusable modules:

```text
addons/lomolib/dev_agent/
  dev_agent_bridge.gd          # lifecycle, file protocol, command dispatch
  dev_agent_input_driver.gd    # Viewport.push_input wrappers
  dev_agent_screenshot.gd      # viewport capture to PNG
  dev_agent_inspector.gd       # node tree/control/state dumps
  dev_agent_scene_ops.gd       # base class or protocol for scene adapters

addons/lomolib/dev_agent/example/
  dev_agent_demo.tscn
  dev_agent_demo.gd
  demo_scene_agent_ops.gd
```

The exact file names can change during implementation, but the boundary should
remain: generic bridge in `lomolib/dev_agent`, scene-specific adapters outside
the generic layer or inside the example folder.

The v1 baseline uses these exact names and includes a runnable example under
`addons/lomolib/dev_agent/example/`.

## 5. Runtime Enablement

DevAgent Debug Mode must be opt-in. Acceptable activation mechanisms:

- command-line flag such as `--dev-agent`
- project setting such as `debug/dev_agent/enabled`
- exported property on a development-only bootstrap node

Default behavior must be disabled. Exported builds should not enable the bridge
unless a developer intentionally wires it in.

The first implementation can use a visible demo scene instead of universal
autoload installation. Avoid adding global autoloads until the workflow proves
useful.

## 6. Session Artifacts

Each run writes one session directory:

```text
user://dev-agent/sessions/<session-id>/
  inbox.jsonl
  outbox.jsonl
  screenshots/
  node-dumps/
  state-dumps/
```

`session-id` should be timestamp-based and stable for the running scene. Every
outbox entry should include:

- `id`: command id copied from inbox
- `op`: operation name
- `ok`: bool
- `time_msec`: monotonic runtime timestamp if available
- `message`: short human-readable result
- `artifacts`: array of generated file paths, if any

Paths printed in logs should use `ProjectSettings.globalize_path()` so Codex can
open files directly from Windows.

## 7. Command Protocol

JSON Lines keeps the protocol simple. One command per line.

Base command shape:

```json
{"id":"cmd-001","op":"capture","label":"initial"}
```

Initial generic operations:

| op | Required fields | Notes |
|---|---|---|
| `wait_frames` | `frames` | Await process frames before returning. |
| `capture` | `label` | Await `RenderingServer.frame_post_draw`, save PNG. |
| `click_at` | `x`, `y`, optional `button` | Coordinates are viewport coordinates. |
| `drag_at` | `from_x`, `from_y`, `to_x`, `to_y`, optional `button`, `steps` | Sends down, motion events, up. |
| `tap_key` | `key` | Key can start as a string mapped by helper. |
| `inspect_tree` | optional `root` | Dumps node tree with class/name/path. |
| `inspect_controls` | optional `root` | Dumps Control paths, rects, visibility, disabled/focus hints. |
| `dump_node` | `path` | Dumps selected public/debug properties. |

Optional scene operation:

```json
{"id":"cmd-020","op":"scene","name":"right_click_world","args":{"x":12.0,"z":30.0}}
```

Scene ops must be implemented by a scene adapter. If the current scene does not
support the requested operation, the bridge returns `ok=false` with a clear
message and leaves the scene running.

## 8. Input Injection Contract

`DevAgentInputDriver` should wrap input injection rather than scattering
`InputEvent*` construction across scenes.

Click contract:

```gdscript
static func click_at(ctx: Node, pos: Vector2, button_index: int = MOUSE_BUTTON_LEFT) -> void:
    var viewport := ctx.get_viewport()

    var press := InputEventMouseButton.new()
    press.button_index = button_index
    press.pressed = true
    press.position = pos
    press.global_position = pos
    viewport.push_input(press)

    var release := InputEventMouseButton.new()
    release.button_index = button_index
    release.pressed = false
    release.position = pos
    release.global_position = pos
    viewport.push_input(release)
```

Implementation notes:

- For SubViewport or embedded viewport work, use `Viewport.push_input(event,
  true)` when positions are already local to that viewport.
- For non-default viewport displays, call `notify_mouse_entered()` before mouse
  events if needed.
- Await layout frames before clicking Controls by rect.
- In headless mode, window size may default to a tiny value; for visual dev
  runs prefer editor/windowed execution, not pure headless.

## 9. Screenshot Contract

Screenshot capture should use the current viewport:

```gdscript
await RenderingServer.frame_post_draw
var image := node.get_viewport().get_texture().get_image()
# optional downscale + format choice, then save
image.resize(target_w, target_h, Image.INTERPOLATE_BILINEAR)
image.save_jpg(path, quality / 100.0)   # or image.save_png(path)
```

Command shape (all fields optional):

```json
{"id":"cmd-009","op":"capture","label":"after_battle","width":960,"format":"jpeg","quality":80}
```

Defaults (v1.1):

- `width`: 960 px. `width: 0` keeps the raw viewport size; any positive value
  scales the image down preserving aspect (no upscale).
- `format`: `"jpeg"` (alias `"jpg"`). PNG is opt-in for lossless / pixel-precise
  regression — file size jumps ~5× and Anthropic vision doesn't benefit.
- `quality`: 80 (JPEG only, clamped 1–100).

The result `data` carries `format`, `width`, `height`, `original_width`,
`original_height`, `resized`, `quality`, and `bytes` so the agent can confirm
what it actually got.

Rules:

- Save to the session `screenshots/` directory.
- Include label and command id in the filename. Extension follows the format.
- Print/globalize the path + size summary in outbox and Godot logs.
- Do not capture every frame; capture only on command to avoid GPU readback
  overhead.
- Prefer the default 960 px JPEG. Bigger ≠ more usable for the vision model
  (server-side tiles a max of ~1568 px long edge regardless); raise only for
  small-font readability or pixel-diff regression.

## 10. Inspector Contract

The inspector should start boring and reliable:

- node path
- class name
- visibility
- process mode
- for `Control`: global rect, visible-in-tree, focus owner, disabled if present
- for `Node3D`: global position, visible if present

Scene adapters may expose richer dumps, for example selected unit id, active
skill id, current command, hovered actor, popup state, or raycast result.

Avoid broad reflection that logs huge object graphs. The output should be useful
for the next debugging decision, not a full save file.

## 11. Scene Adapter Contract

`DevAgentSceneOps` can be a base class or static protocol. The first
implementation can keep it simple:

```gdscript
class_name DevAgentSceneOps
extends Node

func get_supported_ops() -> PackedStringArray:
    return []

func run_scene_op(op_name: StringName, args: Dictionary) -> Dictionary:
    return {
        "ok": false,
        "message": "unsupported scene op: %s" % op_name,
    }
```

Adapters should:

- translate semantic requests into real input when the semantic request is about
  player behavior;
- call game command APIs only for setup/logic probes where UI validation is not
  the goal;
- expose small, named state dumps rather than direct references to internal
  objects;
- fail loudly when a requested target cannot be found.

## 12. LomoLib Example Requirements

The first example should prove the workflow, not the whole future system.

Minimum demo:

1. A simple scene with a camera, a few clickable objects, and a small Control UI.
2. `DevAgentBridge` enabled by an exported property or command-line flag.
3. Raw commands:
   - capture initial screen
   - click a UI button
   - click/drag in viewport
   - tap Escape
   - inspect controls
4. One scene-specific command, such as `select_demo_object`.
5. Clear log output showing the session directory and artifact paths.

Do not couple the example to RTS or Hex battle. Those should be later consumers
of the pattern.

## 13. Skill Requirements

Create a repo-local skill after the example exists. The skill should be invoked
when the user asks to add DevAgent Debug Mode to a scene.

The skill should instruct Codex to:

1. Read this spec and the `lomolib/dev_agent/example`.
2. Inspect the target scene's current input path before editing.
3. Decide which operations must be raw input and which can be scene-specific.
4. Add the smallest possible adapter for the target scene.
5. Add startup instructions and artifact locations.
6. Run one manual/dev-agent session if the environment supports a visible Godot
   window.

The skill must not tell Codex to add regression tests unless the user explicitly
asks for them.

## 14. Implementation Plan

### Phase 1: Spec and minimal library skeleton

- Done in v1: added this spec and `addons/lomolib/dev_agent/` generic classes.
- Activation remains local/opt-in; no autoload or production wiring is added.

### Phase 2: LomoLib example

- Done in v1: `dev_agent/example/dev_agent_demo.tscn` demonstrates raw input,
  screenshot, inspector commands, and one scene-specific adapter.
- Done in v1: `dev_agent/example/README.md` documents running the demo and
  sending commands.

### Phase 3: Repo-local skill

- Done in v1: `.agents/skills/dev-agent-scene-debug-mode/SKILL.md` points to
  this spec and the example, with raw input / scene ops / artifact / non-goal
  checklist.

### Phase 4: First real scene adapter

- Pick one real scene only after the library example is working.
- Prefer a UI-heavy scene first, because `Viewport.push_input` provides the most
  immediate value there.
- Keep adapter code outside core game logic.

## 15. Acceptance for v1

The v1 feature is acceptable when:

- A developer can launch the demo scene in editor/windowed mode with DevAgent
  enabled.
- Codex can append commands to `inbox.jsonl` while the scene remains running.
- Godot writes structured outbox results.
- `capture`, `click_at`, `tap_key`, and `inspect_controls` work.
- Screenshots and dumps are saved under a single session directory and paths are
  easy to open from Codex.
- The normal game/plugin behavior is unchanged when DevAgent is disabled.

## 16. Open Questions

- Should the first command transport be polling JSONL or local HTTP? JSONL is
  simpler and easier to audit; HTTP is more interactive but adds runtime surface.
- Should the bridge be a node manually added to scenes or a plugin-provided
  helper that can inject itself?
- How much property dumping should the generic inspector expose before it
  becomes noisy or unsafe?
- Should screenshot capture support SubViewport targets in v1, or only the root
  viewport?
- The v1 skill lives under `.agents/skills/` only. Add a Claude mirror later
  only if a future workflow explicitly needs it.
