## VisualDirector - 表演实例（Node）
##
## 持翻译员注册表 / 步进器 / 账本 / 更新器四件，pump() 是所有表演实例共用的一趟 tick：
##   事件直改 → 翻译 → 入步进器 → 推进账本时间 → 步进 → 记账（活跃 + 本趟完成）→ 到期清理 + hp 追赶 → flush
## 只发信号、不持 view：账本的 7 条信号原样转发，项目 view 层订阅后按自己的投影定位节点。
##
## 事件从哪来由子类定：录像回放走 ReplayDirector（帧时钟按录像帧取事件喂 pump）；live 项目继承本类，
## 自己攒本帧事件后调 pump，账本 / 步进器的 live 入口（VisualState.seed_actor / despawn_actor /
## set_actor_position，ActionStepper.cancel_for_actor / has_actor_action）经 _state / _stepper 直达。
## 四件在 _init 建好、不依赖入树：建好 Director 就能 updater.register_handler 登记项目私有卡片。
class_name VisualDirector
extends Node


# ========== 信号（转发自 VisualState） ==========

signal actor_state_changed(actor_id: String, state: ActorVisualState)
signal actor_spawned(actor_id: String, state: ActorVisualState)
signal actor_died(actor_id: String)
signal actor_despawned(actor_id: String)
signal effect_spawned(kind: StringName, payload: VisualEffectPayload.Effect)
signal effect_updated(kind: StringName, effect_id: String, progress: float, payload: VisualEffectPayload.Effect)
signal effect_removed(kind: StringName, effect_id: String)


# ========== 组件 ==========

## 翻译员注册表（项目用工厂函数装好，经构造函数交进来）
var _registry: TranslatorRegistry

## 步进器
var _stepper: ActionStepper

## 账本
var _state: VisualState

## 更新器（记账规则）；项目私有卡片在建好 Director 后 updater.register_handler 挂进来
var updater: VisualUpdater


# ========== 生命周期 ==========

func _init(registry: TranslatorRegistry, animation_config: AnimationConfig = null) -> void:
	Log.assert_crash(registry != null, "VisualDirector", "缺翻译员注册表 —— 没有翻译员的表演实例翻不出任何卡片")
	_registry = registry
	_stepper = ActionStepper.new()
	_state = VisualState.new(animation_config)
	updater = VisualUpdater.new()

	_state.actor_state_changed.connect(_on_actor_state_changed)
	_state.actor_spawned.connect(_on_actor_spawned)
	_state.actor_died.connect(_on_actor_died)
	_state.actor_despawned.connect(_on_actor_despawned)
	_state.effect_spawned.connect(_on_effect_spawned)
	_state.effect_updated.connect(_on_effect_updated)
	_state.effect_removed.connect(_on_effect_removed)


func _exit_tree() -> void:
	if _state != null:
		_state.actor_state_changed.disconnect(_on_actor_state_changed)
		_state.actor_spawned.disconnect(_on_actor_spawned)
		_state.actor_died.disconnect(_on_actor_died)
		_state.actor_despawned.disconnect(_on_actor_despawned)
		_state.effect_spawned.disconnect(_on_effect_spawned)
		_state.effect_updated.disconnect(_on_effect_updated)
		_state.effect_removed.disconnect(_on_effect_removed)

	_state = null
	_stepper = null
	_registry = null
	updater = null


# ========== 共享 tick 体 ==========

## 一趟 tick：events 是本趟要处理的逻辑事件（按发生顺序；没有就传空数组），delta_ms 是本趟推进的表演时间。
## 生命周期事件（actor_spawned / actor_destroyed / max_hp）由更新器先直改账本，翻译员才能用最新的只读视图；
## 事件源播完后照样每趟调（空事件），让在飞卡片走完、hp 追赶收敛。
func pump(delta_ms: float, events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		updater.apply_event(_state, event)
		var query := _state.as_query()
		_stepper.enqueue(_registry.translate(event, query))

	_state.advance_time(int(delta_ms))

	var result := _stepper.tick(delta_ms)
	if result.has_changes:
		# 先活跃卡片，再本趟完成的：终值最后落账
		updater.apply_actions(_state, result.active_actions)
		updater.apply_actions(_state, result.completed_this_tick)

	# 到期效果出账 + visual_hp 朝 target_hp 收敛：与卡片无关，每趟都跑
	updater.tick_time(_state, delta_ms)

	_state.flush_dirty_actors()


# ========== 读账本 ==========

## Actor 状态快照（actor_id -> ActorVisualState 深拷贝）
func get_actors_snapshot() -> Dictionary:
	return _state.get_actors_snapshot()


## 逻辑平面坐标（含在飞插值）；像素 / 3D 投影由持棋盘几何的 view 层做
func get_actor_position(actor_id: String) -> Vector2:
	return _state.get_actor_position(actor_id)


func get_screen_shake_offset() -> Vector2:
	return _state.get_screen_shake_offset()


## 在飞卡片数（0 = 动画已排空）
func get_action_count() -> int:
	return _stepper.get_action_count()


# ========== 信号转发 ==========

func _on_actor_state_changed(actor_id: String, state: ActorVisualState) -> void:
	actor_state_changed.emit(actor_id, state)


func _on_actor_spawned(actor_id: String, state: ActorVisualState) -> void:
	actor_spawned.emit(actor_id, state)


func _on_actor_died(actor_id: String) -> void:
	actor_died.emit(actor_id)


func _on_actor_despawned(actor_id: String) -> void:
	actor_despawned.emit(actor_id)


func _on_effect_spawned(kind: StringName, payload: VisualEffectPayload.Effect) -> void:
	effect_spawned.emit(kind, payload)


func _on_effect_updated(kind: StringName, effect_id: String, progress: float, payload: VisualEffectPayload.Effect) -> void:
	effect_updated.emit(kind, effect_id, progress, payload)


func _on_effect_removed(kind: StringName, effect_id: String) -> void:
	effect_removed.emit(kind, effect_id)
