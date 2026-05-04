## Action Lock Status - 短时禁止主动开始行动
##
## 通用控制槽:
## - `cant_act` 只挡 actor 主动发起下一次行动
## - 不影响被动、受击、buff tick、post-damage handler
## - 不 cancel 已经 in-flight 的 ability timeline
class_name HexBattleActionLockStatus


const CONFIG_ID := "status_action_lock"
const TAG_ACTION_LOCKED := "action_locked"
const TAG_CANT_ACT := "cant_act"
const TAG_CONTROL := "control"
const TAG_STATUS := "status"

const REASON_DISPLACEMENT_STAGGER := "displacement_stagger"

const BASE_DURATION_MS := 250.0
const PER_DISTANCE_DURATION_MS := 200.0
const COLLISION_ACTION_LOCK_BONUS_MS := 0.0


class StatusTagConfig:
	extends AbilityComponentConfig

	var _tags: Dictionary = {}

	func _init(tags_value: Dictionary) -> void:
		_tags = tags_value.duplicate(true)

	func create_component() -> AbilityComponent:
		return TagComponent.new({ "tags": _tags })


static func compute_displacement_duration_ms(actual_distance: int, collision_bonus_ms: float = 0.0) -> float:
	return BASE_DURATION_MS + PER_DISTANCE_DURATION_MS * float(maxi(1, actual_distance)) + collision_bonus_ms


static func create_config(duration_ms: float, reason: String = "", reason_tag: String = "") -> AbilityConfig:
	var ability_tags: Array[String] = [TAG_STATUS, TAG_CONTROL, TAG_ACTION_LOCKED]
	if not reason_tag.is_empty():
		ability_tags.append(reason_tag)

	var component_tags := {
		TAG_ACTION_LOCKED: 1,
		TAG_CANT_ACT: 1,
	}
	if not reason_tag.is_empty():
		component_tags[reason_tag] = 1

	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("行动锁定")
		.description("短时无法主动开始行动")
		.ability_tags(ability_tags)
		.meta("duration_ms", duration_ms)
		.meta("reason", reason)
		.component_config(StatusTagConfig.new(component_tags))
		.component_config(TimeDurationConfig.new(duration_ms))
		.build()
	)
