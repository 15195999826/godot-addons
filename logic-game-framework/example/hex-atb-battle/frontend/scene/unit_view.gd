## UnitView - 单位视图(组装根)
##
## 只管理"和 actor 整体表演强绑定"的部分:
##   - body mesh + 队伍/环境材质
##   - 受击闪白 / tint
##   - 死亡动画(影响 root scale/position/visible)
##   - 位置插值
##
## 所有 attached visual(血条 / 护盾条 / buff 行 / 名字)拆到独立子 view,
## update_state() 时 fan-out 给它们各自的 update_from_state(state)。
## 加新 attached visual = 加一个子 view + 在 _ready 装配 + 在 update_state 加一行。
class_name FrontendUnitView
extends Node3D


# ========== 信号 ==========

## 死亡动画完成
signal death_animation_finished(actor_id: String)


# ========== 导出属性 ==========

## 单位半径
@export var unit_radius: float = 0.5


# ========== 节点引用 ==========

var _mesh_instance: MeshInstance3D
var _base_material: StandardMaterial3D

## attached visual 子 view(在 _ready 装配)
var _hp_bar_view: FrontendHpBarView
var _shield_bar_view: FrontendShieldBarView
var _buff_row_view: FrontendBuffRowView
var _name_label_view: FrontendNameLabelView
## Phase F: 朝向箭头. _ready 装配, set_environment_style 中隐藏 (env 不显示 facing).
var _facing_indicator_view: FrontendFacingIndicatorView


# ========== 状态 ==========

var _actor_id: String = ""
var _team: int = 0
## 逻辑世界坐标(BattleAnimator 每帧通过 set_world_position 推过来,= hex 转出的格中心)
var _target_position: Vector3 = Vector3.ZERO
## 朝 _target_position 收敛的平滑位置(每 tick lerp);bump 不走这条,避免被平滑掉
var _smoothed_position: Vector3 = Vector3.ZERO
## bump 临时偏移(撞墙 / 撞单位时叠在 _smoothed_position 之上,逻辑位置不变)
var _bump_offset: Vector3 = Vector3.ZERO
var _death_tween: Tween
var _environment_kind: String = ""
## 死亡动画 once 策略 flag。play_death() 是 transition event 入口,但同一战斗内
## 的非战斗事件(动画系统重入 / debug 重 wire)仍可能触发多次,view 自己挡 once。
var _death_played: bool = false


# ========== 初始化 ==========

func _ready() -> void:
	_create_mesh()
	_hp_bar_view = FrontendHpBarView.new()
	add_child(_hp_bar_view)
	_shield_bar_view = FrontendShieldBarView.new()
	add_child(_shield_bar_view)
	_buff_row_view = FrontendBuffRowView.new()
	add_child(_buff_row_view)
	_name_label_view = FrontendNameLabelView.new()
	add_child(_name_label_view)
	_facing_indicator_view = FrontendFacingIndicatorView.new()
	add_child(_facing_indicator_view)
	_target_position = position
	_smoothed_position = position


func _process(delta: float) -> void:
	# 死亡动画期间 (_death_tween 在 tween position:y) 让 tween 独占 position,
	# 否则会和这里的 lerp 互相覆盖。
	if _death_played:
		return
	# _smoothed_position 朝 _target_position 收敛(原 lerp 行为),
	# 最终 position = 平滑值 + bump_offset(bump 不走 lerp,避免撞击手感被吃掉)。
	_smoothed_position = _smoothed_position.lerp(_target_position, delta * 15.0)
	position = _smoothed_position + _bump_offset


func _create_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = unit_radius
	sphere.height = unit_radius * 2.0
	_mesh_instance.mesh = sphere
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = Color.WHITE
	_mesh_instance.material_override = _base_material
	add_child(_mesh_instance)


# ========== 公共方法 ==========

## 初始化单位
func initialize(
	p_actor_id: String,
	display_name: String,
	team: int,
	max_hp: float,
	current_hp: float,
	actor_type: String = "Character",
	facing_direction: int = 0
) -> void:
	_actor_id = p_actor_id
	_team = team
	_update_team_color()

	# 用初始 state 同步给子 view,避免每个子 view 各自 initialize 接口爆炸
	var initial_state := FrontendActorRenderState.new()
	initial_state.id = p_actor_id
	initial_state.type = actor_type
	initial_state.display_name = display_name
	initial_state.team = team
	initial_state.visual_hp = current_hp
	initial_state.target_hp = current_hp
	initial_state.max_hp = max_hp
	initial_state.is_alive = current_hp > 0
	initial_state.facing_direction = posmod(facing_direction, 6)
	_hp_bar_view.update_from_state(initial_state)
	_shield_bar_view.update_from_state(initial_state)
	_buff_row_view.update_from_state(initial_state)
	_name_label_view.update_from_state(initial_state)
	_facing_indicator_view.update_from_state(initial_state)


func set_environment_style(kind: String) -> void:
	_environment_kind = kind
	if _mesh_instance != null:
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.85, 0.9)
		_mesh_instance.mesh = box
		_mesh_instance.position = Vector3(0.0, 0.4, 0.0)
	if _base_material != null:
		_base_material.albedo_color = Color(0.45, 0.42, 0.36)
	if _hp_bar_view != null:
		_hp_bar_view.set_hidden(true)
	if _shield_bar_view != null:
		_shield_bar_view.visible = false
	if _name_label_view != null:
		var override := "StoneWall" if kind == "stone_wall" else kind
		_name_label_view.set_override_text(override)
	# Phase F: env actor 不显示朝向箭头 (per spec).
	if _facing_indicator_view != null:
		_facing_indicator_view.visible = false


## 获取 Actor ID
func get_actor_id() -> String:
	return _actor_id


## 给 smoke 测试用,避免 poke 内部 _buff_label 字段。
func get_buff_row_view() -> FrontendBuffRowView:
	return _buff_row_view


## Phase F: 给 smoke 测试用 (verify env actor 不显示朝向箭头).
func get_facing_indicator_view() -> FrontendFacingIndicatorView:
	return _facing_indicator_view


## 同步可覆盖 state(hp / flash / tint / buffs)。一次性动画(死亡 / 复活)走
## play_death / revive 公共方法,不在这里推断 transition。
func update_state(new_state: FrontendActorRenderState) -> void:
	_hp_bar_view.update_from_state(new_state)
	_shield_bar_view.update_from_state(new_state)
	_buff_row_view.update_from_state(new_state)
	_name_label_view.update_from_state(new_state)
	_facing_indicator_view.update_from_state(new_state)
	_update_flash_effect(new_state.flash_progress)
	_update_tint_color(new_state.tint_color)
	_bump_offset = new_state.bump_offset
	_apply_bump_squish(new_state.bump_squish)


## 设置世界位置
func set_world_position(new_world_pos: Vector3) -> void:
	_target_position = new_world_pos


# ========== 内部方法 ==========

## team 0 → 蓝, 1 → 红, 其他(含 environment) → 棕。
func _get_team_base_color() -> Color:
	if _team == 0:
		return Color(0.2, 0.6, 1.0)
	if _team == 1:
		return Color(1.0, 0.3, 0.3)
	return Color(0.45, 0.42, 0.36)


func _update_team_color() -> void:
	if _base_material:
		_base_material.albedo_color = _get_team_base_color()


func _update_flash_effect(flash_progress: float) -> void:
	if _base_material:
		_base_material.albedo_color = _get_team_base_color().lerp(Color.WHITE, flash_progress)


## 更新染色
func _update_tint_color(tint_color: Color) -> void:
	if _base_material and tint_color != Color.WHITE:
		_base_material.albedo_color = _base_material.albedo_color.blend(tint_color)


## 把 bump squish 应用到 mesh(只压 mesh,不压 unit_view 整体 — HP 条 / buff 行 / 名字
## 留在原位,只有身体被撞凹下去)。死亡动画走 self.scale,不与本 squish 冲突。
func _apply_bump_squish(squish: Vector3) -> void:
	if _mesh_instance == null:
		return
	_mesh_instance.scale = squish


## 播放死亡动画(once 策略)。已播过则忽略 — 用于 transition event 入口,调方
## (BattleAnimator._on_actor_died)不需要做幂等。
func play_death() -> void:
	if _death_played:
		return
	_death_played = true
	_death_tween = create_tween()
	_death_tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.5)
	_death_tween.parallel().tween_property(self, "position:y", position.y - 0.5, 0.5)
	_death_tween.tween_callback(_on_death_animation_finished)


## 复活:取消死亡 tween,恢复 visible/scale,清 once flag 让下次 play_death 可再起播。
## 由 Animator.reset() 在 playback session control 路径上遍历 view 调用,
## 不通过 Director event(reset 是 session 控制,不是战斗内复活)。
func revive() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	visible = true
	scale = Vector3.ONE
	_death_played = false
	# 重置 bump 残留,避免上一段录像的 bump_offset 拖到这次播放
	_bump_offset = Vector3.ZERO
	if _mesh_instance != null:
		_mesh_instance.scale = Vector3.ONE


func _on_death_animation_finished() -> void:
	death_animation_finished.emit(_actor_id)
	visible = false


func _exit_tree() -> void:
	# 清理死亡动画 Tween
	if _death_tween:
		_death_tween.kill()
