## SkillPreviewWorldGI - 技能预览常驻世界
##
## HexWorldGameplayInstance 的 skill_preview 子类：一个 skill_preview session
## 常驻一个实例（UI 打开时 create，关闭时 destroy），编辑态增删 actor 走
## world.add_actor / remove_actor 触发 FrontendWorldView 响应式刷新；点 START
## 走 queue_preview + start_battle -> SkillPreviewProcedure -> battle_finished。
##
## 提供 reset() 以支持"连续跑多场预览"。base WorldGameplayInstance /
## HexWorldGameplayInstance 不含 reset API —— reset 是编辑态 / 测试场景的需求，
## 不是框架 API，故放在子类里。
##
## 多 actor 时间轴模型: queue_preview 接收 Array[ActorSetup], 每个 setup
## 包含 passives + track (keyframe 列表)。procedure 在 start() 立即 drain
## time_ms<=0 的 keyframe, tick_once 按 logic_time 调度后续。
##
## 详见 docs/design-notes/2026-04-19-world-as-single-instance.md 阶段 3。
class_name SkillPreviewWorldGI
extends HexWorldGameplayInstance


# ========== 字段 ==========

# 预存下一次 start_battle 的 setups；_create_battle_procedure 读出并组装 procedure。
# 每条 setup = {actor_id: String, passives: Array[AbilityConfig], track: Array[Dictionary]}
# 每条 keyframe = {time_ms: int, ability_config: AbilityConfig, target_id: String}
var _queued_setups: Array[Dictionary] = []
var _queued_allow_empty_track: bool = false


# ========== 初始化 ==========

func _init(id_value: String = "") -> void:
	super._init(id_value if id_value != "" else IdGenerator.generate("skill_preview_world"))
	type = "skill_preview_world"


# ========== Reset ==========

## 清空 actor / grid / systems，让同一个 world 可以再次配置 + add_actor + start_battle。
##
## 每个被移除的 actor emit actor_removed，WorldView 自动回收对应 unit view；
## 不走 remove_actor 以省略逐个清 grid occupant 的开销 —— 反正 grid 字段也一起清掉。
## _state 不动 —— start_battle 由 _active_battle 单例保护，不依赖 _state 流转；
## _logic_time 清零方便录像时间戳起点稳定。
func reset() -> void:
	# 先 emit, 再 clear —— emit 不 mutate _actors, 不需要中转 array。
	for a in _actors:
		actor_removed.emit(a.get_id())
	_actors.clear()
	_actor_id_2_actor_dic.clear()
	_systems.clear()
	grid = null
	_logic_time = 0.0
	_queued_setups = []
	_queued_allow_empty_track = false


# ========== Preview 参数 ==========

## 预存下一次 start_battle 用的 actor setups。调方在 start_battle 前调用一次。
##
## actor_setups[i] = {
##   "actor_id": String,
##   "passives": Array[AbilityConfig],
##   "track":    Array[Dictionary],   # 见 keyframe 格式
## }
## keyframe = {
##   "time_ms":        int,           # 触发时刻 (>=0; <=0 在 procedure.start() 末尾立即 drain)
##   "ability_config": AbilityConfig,
##   "target_id":      String,        # "" 表无 target
## }
##
## allow_empty_track=true 允许所有 actor track 全空 (纯被动验证场景)；
## 默认 false 时至少有一个 actor 必须有非空 track —— 阻止"忘配 action"静默成空跑。
func queue_preview(
	actor_setups: Array[Dictionary],
	allow_empty_track: bool = false,
) -> void:
	# duplicate(true) 防御调方后续 mutate 反向影响 world 缓存; passives / track 数组
	# 也是嵌套 dict, 浅拷贝不足以隔离。
	_queued_setups = actor_setups.duplicate(true)
	_queued_allow_empty_track = allow_empty_track


# ========== Procedure 工厂 ==========

## 消费预存的 setups 构造 SkillPreviewProcedure。消费后清空，避免下一场战斗
## 误用上一场的配置 —— 必须每场前重新 queue_preview。
##
## assert 链:
## 1. setups 至少一条 (即使纯被动也得有 actor 在场上)
## 2. 每条 setup.actor_id 能解析到 world.get_actor
## 3. 每条 keyframe 的 ability_config 非 null
## 4. has_any_keyframe or _queued_allow_empty_track —— 阻止静默空跑
func _create_battle_procedure(participants: Array[Actor]) -> BattleProcedure:
	Log.assert_crash(
		not _queued_setups.is_empty(),
		"SkillPreviewWorldGI",
		"start_battle called without a preceding queue_preview — _queued_setups is empty"
	)

	var has_any_keyframe := false
	for setup in _queued_setups:
		var actor_id: String = setup.get("actor_id", "") as String
		Log.assert_crash(
			actor_id != "" and get_actor(actor_id) != null,
			"SkillPreviewWorldGI",
			"setup.actor_id unresolved in world: %s" % actor_id
		)
		var track: Array = setup.get("track", []) as Array
		if not track.is_empty():
			has_any_keyframe = true
		for kf in track:
			var ability_cfg = (kf as Dictionary).get("ability_config")
			Log.assert_crash(
				ability_cfg != null and ability_cfg is AbilityConfig,
				"SkillPreviewWorldGI",
				"keyframe.ability_config null/invalid for actor %s" % actor_id
			)

	Log.assert_crash(
		has_any_keyframe or _queued_allow_empty_track,
		"SkillPreviewWorldGI",
		"queue_preview: no actor has a non-empty track — set allow_empty_track=true if intentional"
	)

	var procedure := SkillPreviewProcedure.new(
		self,
		participants,
		_queued_setups,
		_queued_allow_empty_track,
	)
	_queued_setups = []
	_queued_allow_empty_track = false
	return procedure
