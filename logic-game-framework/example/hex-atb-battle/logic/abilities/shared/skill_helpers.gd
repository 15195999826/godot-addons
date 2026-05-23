## 各技能文件共用的 trigger filter / resolver 工具
##
## 这些函数逻辑与具体技能无关（通用 ability activate 过滤、投射物命中过滤、
## hex 坐标→Vector3 转换等），所以抽到一个独立 helper class，避免在每个技能文件里复制。
##
## 使用规约：
##   - 以 `ability_activate_filter` / `projectile_hit_filter` 为**函数引用**传给 TriggerConfig
##     （不要加括号；GDScript 会把 `ClassName.static_func` 包成 Callable）
##   - `target_coord_from_event()` / `owner_position_resolver()` / `target_position_resolver()`
##     必须**调用**（加括号），每次返回一个新的 Resolver 对象
class_name HexBattleSkillHelpers


# ========== Trigger Filter ==========

## 匹配当前 Ability 实例的激活事件
static func ability_activate_filter(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var ability: Ability = ctx.ability
	if ability == null:
		return false
	var event := GameEvent.AbilityActivate.from_dict(event_dict)
	return event.ability_instance_id == ability.id


## 匹配投射物命中事件
## 同时匹配 source_actor_id（发射者）和 ability_config_id（技能来源），
## 确保只有本技能发出的投射物才触发命中响应。
static func projectile_hit_filter(event_dict: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var ability: Ability = ctx.ability
	if ability == null:
		Log.warning("ProjectileHitFilter", "ctx.ability is null, skipping filter")
		return false
	var event := GameEvent.ProjectileHit.from_dict(event_dict)
	return event.source_actor_id == ctx.owner_actor_id \
		and event.ability_config_id == ability.config_id


# ========== Resolver ==========

## 从事件中读 target_coord Dictionary
static func target_coord_from_event() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var evt := ctx.get_current_event()
		return evt.get("target_coord", {}) as Dictionary
	)


## 从 Ability owner 获取位置（hex 坐标转 Vector3）
static func owner_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if owner_id == "":
			return Vector3.ZERO
		var actor := GameWorld.get_actor(owner_id)
		if actor == null or not (actor is CharacterActor):
			return Vector3.ZERO
		var char_actor := actor as CharacterActor
		if not char_actor.hex_position.is_valid():
			return Vector3.ZERO
		return Vector3(char_actor.hex_position.q, char_actor.hex_position.r, 0)
	)


## 从当前事件目标获取位置（hex 坐标转 Vector3）
static func target_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var event := ctx.get_current_event()
		var target_actor_id: String = event.get("target_actor_id", "")
		if target_actor_id == "":
			return Vector3.ZERO
		var actor := GameWorld.get_actor(target_actor_id)
		if actor == null or not (actor is CharacterActor):
			return Vector3.ZERO
		var char_actor := actor as CharacterActor
		if not char_actor.hex_position.is_valid():
			return Vector3.ZERO
		return Vector3(char_actor.hex_position.q, char_actor.hex_position.r, 0)
	)
