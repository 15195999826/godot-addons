## Dota2WaveSpawner - 建 actor + 应用 config→AttributeSet + 挂 controller（不发 intent）
##
## README.md（Controller / Intent 模型 节）「WaveSpawner Boundary」：spawner **不是**命令源，不发 intent。
## 只做：建 unit actor → 应用兵种 config / AttributeSet 值 → 放到出生点 → 装基础攻击
## Ability → 注册移动体 → 挂 Dota2LaneCreepController → 登记进 procedure/world。
## 新 controller 起始无 current intent；其首个 logic tick 自行决策（通常建 LaneMarchIntent）。
##
## 共享对象无状态：static 方法，无实例字段。
class_name Dota2WaveSpawner
extends RefCounted


## 给某队刷一波 lane creep。返回本波生成的 actor 列表。
## global_spawn_base：跨波累积的出生序号基址，喂给 controller 做决策错峰（% 3）。
static func spawn_wave(
	world: Dota2WorldGameplayInstance,
	procedure: Dota2AutoBattleProcedure,
	team_id: int,
	global_spawn_base: int,
) -> Array[Dota2UnitActor]:
	var spawned: Array[Dota2UnitActor] = []
	var composition := Dota2LaneConfig.get_wave_composition()
	for slot_index in range(composition.size()):
		var unit_type: Dota2UnitTypeConfig.UnitType = composition[slot_index]
		var actor := Dota2UnitActor.new(unit_type)
		actor.set_team_id(team_id)
		actor.position_2d = Dota2LaneConfig.get_unit_spawn_pos(team_id, slot_index)

		# add_actor 分配 id 并触发 _on_id_assigned（sync ability_set / attribute_set owner）。
		world.add_actor(actor)
		# id 已就位 → 装基础攻击 Ability（owner_actor_id 正确）。
		actor.equip_basic_attack()
		# 注册 sim-nav 移动体（position 已设好）。
		procedure.movement_adapter.register_unit(actor)
		# 挂 lane creep controller（起始无 intent；首 tick 自行决策）。
		var spawn_index := global_spawn_base + slot_index
		var controller := Dota2LaneCreepController.new(actor.get_id(), team_id, spawn_index)
		procedure.register_controller(actor.get_id(), controller)
		procedure.add_unit_to_team(actor, team_id)

		GameWorld.event_collector.push(Dota2BattleEvents.make_unit_spawned(
			actor.get_id(), team_id, actor.get_unit_type_id(),
			actor.position_2d, actor.attribute_set.max_hp,
		))
		spawned.append(actor)
	return spawned
