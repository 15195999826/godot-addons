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
## 详见 docs/design-notes/2026-04-19-world-as-single-instance.md 阶段 3。
class_name SkillPreviewWorldGI
extends HexWorldGameplayInstance


# ========== 字段 ==========

# 预存下一次 start_battle 的 preview 参数；_create_battle_procedure 读出并组装 procedure。
var _queued_caster_id: String = ""
var _queued_ability_config: AbilityConfig = null
var _queued_target_id: String = ""
var _queued_passives: Array[AbilityConfig] = []


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
	_queued_caster_id = ""
	_queued_ability_config = null
	_queued_target_id = ""
	_queued_passives = []


# ========== Preview 参数 ==========

## 预存下一次 start_battle 用的 preview 参数。调方在 start_battle 前调用一次。
func queue_preview(
	caster_id: String,
	ability_config: AbilityConfig,
	target_id: String = "",
	passives: Array[AbilityConfig] = [],
) -> void:
	_queued_caster_id = caster_id
	_queued_ability_config = ability_config
	_queued_target_id = target_id
	# duplicate 防御调方后续 mutate 传入数组反向影响 world 缓存
	_queued_passives = passives.duplicate()


# ========== Procedure 工厂 ==========

## 消费预存的 preview 参数构造 SkillPreviewProcedure。消费后清空，避免
## 下一场战斗误用上一场的技能 —— 必须每场前重新 queue_preview。
## assert 防 "忘 queue_preview 直接 start_battle" 静默跑 null ability 的坑。
func _create_battle_procedure(participants: Array[Actor]) -> BattleProcedure:
	Log.assert_crash(
		_queued_ability_config != null,
		"SkillPreviewWorldGI",
		"start_battle called without a preceding queue_preview — ability_config is null"
	)
	var procedure := SkillPreviewProcedure.new(
		self,
		participants,
		_queued_caster_id,
		_queued_ability_config,
		_queued_target_id,
		_queued_passives,
	)
	_queued_caster_id = ""
	_queued_ability_config = null
	_queued_target_id = ""
	_queued_passives = []
	return procedure
