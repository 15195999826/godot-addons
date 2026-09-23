## 各技能文件共用的 trigger precheck / resolver 工具
##
## 这些函数逻辑与具体技能无关（通用 ability activate 匹配、投射物命中匹配、
## hex 坐标→Vector3 转换等），所以抽到一个独立 helper class，避免在每个技能文件里复制。
##
## 使用规约：
##   - 以 `ability_activate_precheck` / `projectile_hit_precheck` 为**函数引用**传给 `TriggerConfig.new(kind).precheck(...)`
##     （不要加括号；GDScript 会把 `ClassName.static_func` 包成 Callable）
##   - `target_coord_from_event()` / `owner_position_resolver()` / `target_position_resolver()`
##     必须**调用**（加括号），每次返回一个新的 Resolver 对象
class_name HexBattleSkillHelpers


# ========== Trigger Precheck（只看事件 + 三个 id，不要 ctx）==========

## 匹配当前 Ability 实例的激活事件
static func ability_activate_precheck(event_dict: Dictionary, h: HandlerContext) -> bool:
	return str(event_dict.get("ability_instance_id", "")) == h.ability_id


## 匹配本技能发出的投射物命中：source_actor_id（发射者）是 owner、ability_config_id（技能来源）是本 config。
## 走 precheck：不是自己的弹在重建 context 之前就跳过——满场几十个订阅者时这是 post 扇出的大头。
static func projectile_hit_precheck(event_dict: Dictionary, h: HandlerContext) -> bool:
	return str(event_dict.get("source_actor_id", "")) == h.owner_id \
		and str(event_dict.get("ability_config_id", "")) == h.config_id


# ========== Caster 解析 ==========

## 从 ctx 解析 caster CharacterActor(ability owner)。
## 拿不到(无 ability_ref / 不在 world / 非 Character)返回 null;
## **不判死活** —— 需要"活的 caster"由调用方自查 is_dead()(有的场景只要坐标)。
## 此前"取 owner_id → 判空 → get_actor → is CharacterActor → cast"五行式在
## 各 resolver / action 里逐字重复, 收口到此。
static func caster(ctx: ExecutionContext) -> CharacterActor:
	var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if owner_id.is_empty():
		return null
	var actor := GameWorld.get_actor(owner_id)
	if actor == null or not (actor is CharacterActor):
		return null
	return actor as CharacterActor


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
		var char_actor := caster(ctx)
		if char_actor == null or not char_actor.hex_position.is_valid():
			return Vector3.ZERO
		return Vector3(char_actor.hex_position.q, char_actor.hex_position.r, 0)
	)


## caster.atk 伤害 resolver: 随施法者 atk 缩放 (× mult)。
## 过去每个 atk-scaled 技能各自抄一份 byte-identical 闭包 (strike/angle_cone/
## grid_cone/knockback_punch/lifesteal/piercing_line/wall_breaker; shadow_step ×1.5),
## 集中到此。固定值伤害用 Resolvers.float_val(x) 直接写, 不需 helper。
static func caster_atk_damage(mult: float = 1.0) -> FloatResolver:
	return Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
		var char_actor := caster(ctx)
		if char_actor == null:
			return 0.0
		return char_actor.attribute_set.atk * mult
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
