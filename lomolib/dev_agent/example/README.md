# DevAgent Debug Mode Example

This demo proves the development-only JSONL workflow for `addons/lomolib/dev_agent`.
It is not a regression test and should not be wired into CI.

## Run

Open and run this scene in the Godot editor:

```text
res://addons/lomolib/dev_agent/example/dev_agent_demo.tscn
```

The output panel prints the session paths:

```text
[DevAgentDemo] inbox:  C:\...\user_data\Inkmon\dev-agent\sessions\<session-id>\inbox.jsonl
[DevAgentDemo] outbox: C:\...\user_data\Inkmon\dev-agent\sessions\<session-id>\outbox.jsonl
```

## Send Commands

Append one JSON object per line to `inbox.jsonl` while the scene is still running:

```jsonl
{"id":"cmd-001","op":"capture","label":"initial"}
{"id":"cmd-002","op":"inspect_controls","label":"controls"}
{"id":"cmd-003","op":"click_at","x":80,"y":100}
{"id":"cmd-004","op":"tap_key","key":"Escape"}
{"id":"cmd-005","op":"scene","name":"select_demo_object","args":{"id":"alpha"}}
{"id":"cmd-006","op":"dump_node","path":"/root/DevAgentDemo/StatusLabel","label":"status"}
```

PowerShell example:

```powershell
Add-Content -LiteralPath "C:\...\inbox.jsonl" -Value '{"id":"cmd-001","op":"capture","label":"initial"}'
```

Read `outbox.jsonl` for structured results. Screenshots and dumps are written under:

```text
user://dev-agent/sessions/<session-id>/
  screenshots/
  node-dumps/
  state-dumps/
```

## Adapter Boundary

`demo_scene_agent_ops.gd` is intentionally scene-specific. Keep reusable file
protocol, input injection, screenshots, and generic inspectors in
`addons/lomolib/dev_agent/`; keep game or scene strategy in each scene adapter.
