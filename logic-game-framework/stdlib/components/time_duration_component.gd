class_name TimeDurationComponent
extends AbilityComponent

const EXPIRE_REASON_TIME_DURATION = "time_duration"

var initial_duration: float
var remaining: float

func _init(duration_ms: float) -> void:
	initial_duration = duration_ms
	remaining = duration_ms
	type = "TimeDurationComponent"

func on_tick(dt: float) -> void:
	if _state == "expired":
		return

	remaining -= dt
	if remaining <= 0.0:
		_trigger_expiration()

func _trigger_expiration() -> void:
	mark_expired()
	if _ability:
		_ability.expire(EXPIRE_REASON_TIME_DURATION)

func get_remaining() -> float:
	return maxf(0.0, remaining)

func get_initial_duration() -> float:
	return initial_duration

func get_progress() -> float:
	return 1.0 - remaining / initial_duration

func refresh() -> void:
	remaining = initial_duration
	_state = "active"

func extend(amount_ms: float) -> void:
	remaining += amount_ms

func serialize() -> Dictionary:
	return {
		"initialDuration": initial_duration,
		"remaining": remaining,
	}

func deserialize(data: Dictionary) -> void:
	remaining = float(data.get("remaining", 0.0))
