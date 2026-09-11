## BattleActor - 参与战斗管线的 Actor 基类。
##
## Actor 保持中性（只有 id / team / 位置 / 录像钩子）；「带 AbilitySet 的 actor」是
## opt-in 的一等公民，骨架住这里：死亡锁存、owner id 同步、录像默认订阅。
##
## 基类**不**声明 ability_set / attribute_set 字段：子类各持强类型字段，经协变返回的
## get_ability_set() / get_attribute_set() 暴露基类视图。这样专属代码（Strike 读 atk）
## 仍可 actor.attribute_set.atk 直访而不被基类 shadow。两个 getter 默认返回 null——
## 纯数据 actor（overworld 玩家 / NPC）继承本类只为共享位置与录像形状，不带战斗设施。
##
## 所有方法对 null set 做真实分支而非仅断言：Log.assert_crash 在 debug 构建下只中止
## 自己那一帧，挡不住半成品对象继续被调用。
class_name BattleActor
extends Actor


## 死亡判定读的属性名。这是 core 唯一的属性名假设。
## 换容器（血不在 get_attribute_set() 那份 raw 里）覆盖 _hp_source() 即可；
## 换属性名要覆盖 has_hp() + get_current_hp() 这一对——check_death() 只经这两个虚函数取值。
const HP_ATTRIBUTE := "hp"


## 队伍 ID（-1 = 未分配）。字符串 _team 是 Actor 基类的对外形态，两者由 set_team_id 同步。
var team_id: int = -1

## 死亡锁存：check_death / mark_dead 只会置位，解闩只走 set_death_latch(false)。
var _is_dead: bool = false


# ========== 公共合同（子类按需覆盖，协变返回收窄类型） ==========

## 本 actor 的 AbilitySet；纯数据 actor 返回 null。
func get_ability_set() -> AbilitySet:
	return null


## 本 actor 的 AttributeSet；纯数据 actor 返回 null。
func get_attribute_set() -> BaseGeneratedAttributeSet:
	return null


# ========== 生命周期 ==========

## ID 被 add_actor 分配后，同步 ability_set / attribute_set 内引用的 owner id。
func _on_id_assigned() -> void:
	var ability_set := get_ability_set()
	if ability_set != null:
		ability_set.bind_owner(get_id())
	var attrs := get_attribute_set()
	if attrs != null:
		attrs.actor_id = get_id()


## 血条来源：读得到 hp 时返回底层 RawAttributeSet，否则 null。
## has_hp() / get_current_hp() / check_death() 三者共用它——改属性名或换取值方式
## 只需覆盖这一个钩子。
func _hp_source() -> RawAttributeSet:
	var attrs := get_attribute_set()
	if attrs == null:
		return null
	var raw := attrs.get_raw()
	if raw == null or not raw.has_attribute(HP_ATTRIBUTE):
		return null
	return raw


## 是否有可读的 hp 属性。check_death 用它区分「没血条」与「血条为 0」——
## 只看 get_current_hp() 的 0.0 会把纯数据 actor 判成尸体。
func has_hp() -> bool:
	return _hp_source() != null


## 当前 HP。无 attribute_set 或未定义 hp 属性时返回 0。
func get_current_hp() -> float:
	var raw := _hp_source()
	return raw.get_current_value(HP_ATTRIBUTE) if raw != null else 0.0


## 数据驱动死亡判定；返回是否**首次**进入死亡态（供调用方发一次死亡事件）。
## 没有血条的纯数据 actor 恒返回 false。
func check_death() -> bool:
	if _is_dead or not has_hp():
		return false
	if get_current_hp() > 0.0:
		return false
	_is_dead = true
	return true


## 显式锁存死亡（伤害结算后直接判定的路径）；返回是否首次。
func mark_dead() -> bool:
	if _is_dead:
		return false
	_is_dead = true
	return true


## 直接写死亡闩。**唯一**允许把 true 拨回 false 的入口——「从 HP 复活」「读档按 HP
## 重建 downed」这类规则是项目层知识，core 不定义它们，但也不该逼项目层去写基类私有字段。
func set_death_latch(value: bool) -> void:
	_is_dead = value


func is_dead() -> bool:
	return _is_dead


## 死亡的 actor 不再响应 pre / post handler（反伤 / 护盾 / 吸血等被动死后失效）。
## 项目层按事件豁免就覆盖它（如让死者响应自己的 death，亡语才触发得了）。
func is_event_responsive(_event_dict: Dictionary, _phase: String) -> bool:
	return not _is_dead


# ========== 队伍 ==========

func set_team_id(p_team_id: int) -> void:
	team_id = p_team_id
	set_team(str(p_team_id))


func get_team_id() -> int:
	return team_id


## 录像里的队伍号。未入队即 -1（Actor 基类解析空 _team 会给出 0，那是「A 队」，
## 与「没队伍」不是一回事）；确实想录 0 的 actor 覆盖本方法说清楚。
func _get_team_int() -> int:
	return team_id


# ========== 录像支持 ==========

## 全属性快照 {name: current_value}；子类可扩展（如追加 facing）。
func get_attribute_snapshot() -> Dictionary:
	var attrs := get_attribute_set()
	if attrs == null:
		return {}
	var raw := attrs.get_raw()
	if raw == null:
		return {}
	return raw.snapshot_current_values()


func get_ability_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ability_set := get_ability_set()
	if ability_set == null:
		return result
	for ability in ability_set.get_abilities():
		result.append({
			"instance_id": ability.id,
			"config_id": ability.config_id,
		})
	return result


func get_tag_snapshot() -> Dictionary:
	var ability_set := get_ability_set()
	if ability_set == null:
		return {}
	return ability_set.get_all_tags()


## 默认录像订阅：属性 / ability / 生命周期三条。子类可 super 后追加自定义订阅。
func setup_recording(ctx: RecordingContext) -> Array[Callable]:
	var unsubscribes: Array[Callable] = []
	var attrs := get_attribute_set()
	if attrs != null:
		unsubscribes.append_array(RecordingUtils.record_attribute_changes(attrs, ctx))
	var ability_set := get_ability_set()
	if ability_set != null:
		unsubscribes.append_array(RecordingUtils.record_ability_set_changes(ability_set, ctx))
	unsubscribes.append_array(RecordingUtils.record_actor_lifecycle(self, ctx))
	return unsubscribes


# ========== 序列化 ==========

## 公共字段（id / type / team / 属性 raw / is_dead）。位置形态是项目知识，子类追加。
func serialize() -> Dictionary:
	var base := serialize_base()
	var attrs := get_attribute_set()
	base["attribute_set"] = attrs.get_raw().serialize() if attrs != null else {}
	base["is_dead"] = _is_dead
	return base


# ========== 协议查询 ==========

## 安全获取任意 Actor 的 AbilitySet：非 BattleActor（或纯数据 BattleActor）返回 null。
## 框架层拿到的是 Actor 基类引用，用这里而非 has_method 探测。
static func ability_set_of(actor: Actor) -> AbilitySet:
	var battle_actor := actor as BattleActor
	if battle_actor == null:
		return null
	return battle_actor.get_ability_set()
