## Action 分层合同 validator V1
##
## file-grep + light parse 扫描，把 AI 生成代码的 Action 边界硬化。
##
## 检查项 (按 docs/reference/action-architecture.md):
## 1. core/actions / stdlib/actions / example/*/logic/actions 下新增 `class_name .*Action`
##    视为 public Primitive Action，必须进入 allowlist。
## 2. example/** / stdlib/** 新增 Action 不允许直接 extends Action.BaseAction;
##    必须继承 Action.PrimitiveAction / Action.FlowActionBase / Action.SkillLocalAction。
##    core 内部基类与既有历史类暂时 allowlist。
## 3. 内嵌 `_XxxAction extends Action.SkillLocalAction` 不允许使用 class_name。
##
## 用法:
##     var report := ActionArchitectureValidator.scan_repo()
##     # report.violations: Array[Dictionary] (file/line/category/message)
##     # report.allowlist_hits: Array[Dictionary] (allowlisted files actually present)
class_name ActionArchitectureValidator
extends RefCounted


const _PUBLIC_ACTION_DIRS := [
	"res://addons/logic-game-framework/core/actions/",
	"res://addons/logic-game-framework/stdlib/actions/",
]

const _EXAMPLE_LOGIC_ACTION_DIRS := [
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/",
	"res://addons/logic-game-framework/example/rts-auto-battle/logic/actions/",
	"res://addons/logic-game-framework/example/dota2-auto-battle/logic/actions/",
]

const _SKILL_FILE_DIRS := [
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/abilities/active/",
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/abilities/passives/",
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/abilities/buffs/",
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/abilities/shared/",
]

## allowlist: file path → { reason, migrate_by }
##
## 历史 Action 直接继承 Action.BaseAction，本次仅作硬化新代码，不要求统一迁移。
## migrate_by 写明后续可清理的边界（"none" = 当前合规，保留入口仅供文档用）。
const ALLOWLIST: Dictionary = {
	# core 内置基类与 NoopAction
	"res://addons/logic-game-framework/core/actions/Action.gd": {
		"reason": "core base classes (NoopAction is framework primitive)",
		"migrate_by": "none",
	},
	# §0.1 引入 LooseTagAction 后，TagAction 标 legacy facade；
	# 新增技能不应再 extend Action.BaseAction via TagAction 子类。
	"res://addons/logic-game-framework/core/actions/tag_action.gd": {
		"reason": "legacy TagAction facade (kept for back-compat)",
		"migrate_by": "phase-00 §0.1 LooseTagAction supersedes",
	},
	# §0.2: FlowAction 是 namespace wrapper (extends RefCounted)，
	# 内嵌 IfAction extends Action.FlowActionBase。class_name 以 Action 结尾仅作 API entry，
	# 不是 BaseAction 子类。
	"res://addons/logic-game-framework/core/actions/flow_action.gd": {
		"reason": "§0.2 FlowAction namespace; inner IfAction is FlowActionBase",
		"migrate_by": "none",
	},
	# §0.1: LooseTagAction 是 namespace wrapper (extends RefCounted)，
	# 内嵌 Apply / Remove 各自 extends Action.PrimitiveAction。class_name
	# 以 Action 结尾仅作 API entry，不是 BaseAction 子类。
	"res://addons/logic-game-framework/core/actions/loose_tag_action.gd": {
		"reason": "§0.1 LooseTagAction namespace; inner classes are PrimitiveAction",
		"migrate_by": "none",
	},
	"res://addons/logic-game-framework/stdlib/actions/launch_projectile_action.gd": {
		"reason": "historical primitive (used by Fireball / PreciseShot / Chain Lightning)",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/stdlib/actions/stage_cue_action.gd": {
		"reason": "historical primitive (broad use across hex example)",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/apply_buff_action.gd": {
		"reason": "historical hex primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/cancel_active_executions_action.gd": {
		"reason": "Phase A Stun: cancel target's in-flight active executions in buff on_apply",
		"migrate_by": "none (extends Action.PrimitiveAction; required because public class_name lives in public action dir)",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/spawn_actor_action.gd": {
		"reason": "Phase C0 Summon Totem: spawn CharacterActor (totem) at caster's free neighbor + grant passives",
		"migrate_by": "none (extends Action.PrimitiveAction; required because public class_name lives in public action dir)",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/spawn_fire_tile_action.gd": {
		"reason": "Phase C Fire Tile: spawn passable EnvironmentActor overlay (no grid.occupant) at target hex coord + grant pulse/lifetime passives",
		"migrate_by": "none (extends Action.PrimitiveAction; placement_mode abstraction follow-up)",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/apply_move_action.gd": {
		"reason": "historical hex primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/apply_shield_action.gd": {
		"reason": "historical hex primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/damage_action.gd": {
		"reason": "historical hex primitive (very broad use)",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/heal_action.gd": {
		"reason": "historical hex primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/poison_tick_action.gd": {
		"reason": "skill-specific tick action living in public action dir",
		"migrate_by": "future cleanup: inline as SkillLocalAction inside poison_buff",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/push_action.gd": {
		"reason": "historical hex primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/reflect_damage_action.gd": {
		"reason": "historical hex primitive (Thorns)",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/regenerate_action.gd": {
		"reason": "phase C public primitive: resource regen separate from heal pipeline (extends Action.PrimitiveAction directly)",
		"migrate_by": "n/a (already on the correct base; allowlisted because validator requires explicit registration for all public class_name actions)",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/start_move_action.gd": {
		"reason": "historical hex primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/hex-atb-battle/logic/actions/surge_tick_action.gd": {
		"reason": "skill-specific tick action living in public action dir",
		"migrate_by": "future cleanup: inline as SkillLocalAction inside surge_buff",
	},
	"res://addons/logic-game-framework/example/rts-auto-battle/logic/actions/rts_basic_attack_action.gd": {
		"reason": "historical RTS primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/dota2-auto-battle/logic/actions/dota2_attack_started_action.gd": {
		"reason": "historical dota2 lab primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
	"res://addons/logic-game-framework/example/dota2-auto-battle/logic/actions/dota2_damage_action.gd": {
		"reason": "historical dota2 lab primitive",
		"migrate_by": "future cleanup: convert to extends Action.PrimitiveAction",
	},
}


## 验证结果
class Report:
	extends RefCounted
	var violations: Array[Dictionary] = []
	var allowlist_hits: Array[String] = []

	func is_clean() -> bool:
		return violations.is_empty()

	func summary() -> String:
		var lines: Array[String] = []
		lines.append("[ActionArchitectureValidator] violations=%d allowlist_used=%d" % [violations.size(), allowlist_hits.size()])
		for v in violations:
			lines.append("  - [%s] %s:%d %s" % [v.category, v.file, v.line, v.message])
		return "\n".join(lines)


static func scan_repo() -> Report:
	var report := Report.new()
	for dir in _PUBLIC_ACTION_DIRS + _EXAMPLE_LOGIC_ACTION_DIRS + _SKILL_FILE_DIRS:
		_scan_action_dir(dir, report)
	return report


static func _scan_action_dir(dir_path: String, report: Report) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".gd"):
			var full := dir_path + name
			_scan_action_file(full, report)
		name = d.get_next()
	d.list_dir_end()


static func _scan_action_file(file_path: String, report: Report) -> void:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var lines := text.split("\n")
	var allowlisted := ALLOWLIST.has(file_path)
	if allowlisted:
		report.allowlist_hits.append(file_path)

	var has_public_class_name := false
	var public_class_name := ""
	var public_class_line := -1
	var direct_base_action_line := -1
	var current_class_name := ""
	var current_class_line := -1
	var skip_execution_state_guard := file_path.ends_with("/execution_context.gd") \
		or file_path.ends_with("/action_architecture_validator.gd")

	for i in range(lines.size()):
		var raw_line := lines[i]
		var stripped := raw_line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue

		if stripped.begins_with("class "):
			var class_part := stripped.substr(len("class ")).strip_edges()
			var token_end := class_part.find(":")
			if token_end >= 0:
				class_part = class_part.substr(0, token_end)
			token_end = class_part.find(" ")
			if token_end >= 0:
				class_part = class_part.substr(0, token_end)
			current_class_name = class_part
			current_class_line = i + 1

		# 1. class_name 在文件首层声明 (不缩进)
		if not raw_line.begins_with("\t") and not raw_line.begins_with(" "):
			if stripped.begins_with("class_name "):
				var name_part := stripped.substr(len("class_name ")).strip_edges()
				var token_end := name_part.find(" ")
				if token_end >= 0:
					name_part = name_part.substr(0, token_end)
				if name_part.ends_with("Action") and not name_part.begins_with("_"):
					public_class_name = name_part
					has_public_class_name = true
					public_class_line = i + 1

		# 2. extends Action.BaseAction / extends BaseAction (顶层)
		#    这些是历史代码，allowlist 豁免
		if (stripped == "extends Action.BaseAction" or stripped == "extends BaseAction"):
			# 顶层 (column 0) 或 缩进一级 (内嵌 class) 都要看
			if direct_base_action_line < 0:
				direct_base_action_line = i + 1

		if stripped == "extends Action.SkillLocalAction":
			if not current_class_name.begins_with("_"):
				report.violations.append({
					"file": file_path,
					"line": current_class_line if current_class_line > 0 else i + 1,
					"category": "skill_local_action_must_be_private",
					"message": "SkillLocalAction 必须是技能/ buff 文件内的私有内嵌 class，命名需以 '_' 开头；got '%s'。" % current_class_name,
				})

		if not skip_execution_state_guard \
				and (stripped.contains(".execution_state") or stripped.begins_with("execution_state[")):
			report.violations.append({
				"file": file_path,
				"line": i + 1,
				"category": "direct_execution_state_access_not_allowed",
				"message": "禁止直接读写 execution_state；必须通过 ExecutionContext.set_execution_state/get_execution_state，以强制 namespaced key。",
			})

	# 顶层 class_name 必须在 allowlist 中（基础设施明确的入口）
	if has_public_class_name and not allowlisted:
		# 仅当文件在 PUBLIC_ACTION_DIRS / EXAMPLE_LOGIC_ACTION_DIRS 下才校验
		report.violations.append({
			"file": file_path,
			"line": public_class_line,
			"category": "public_class_name_missing_from_allowlist",
			"message": "class_name '%s' 出现在 public action 目录但未在 ALLOWLIST 中；新增 Action 必须继承 Action.PrimitiveAction / FlowActionBase / SkillLocalAction，且明确登记进 allowlist。" % public_class_name,
		})

	# 顶层 extends BaseAction 必须 allowlist; 否则要求换基类
	if direct_base_action_line > 0 and not allowlisted:
		report.violations.append({
			"file": file_path,
			"line": direct_base_action_line,
			"category": "direct_extends_base_action_not_allowed",
			"message": "禁止应用层直接 extends Action.BaseAction；改成 extends Action.PrimitiveAction / FlowActionBase / SkillLocalAction，或登记进 allowlist 并写明 migrate_by。",
		})


## 给单一文件跑 validator (便于 spot-check / test 个案)
static func scan_file(file_path: String) -> Report:
	var report := Report.new()
	_scan_action_file(file_path, report)
	return report
