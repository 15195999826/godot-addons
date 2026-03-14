class_name ReplayLogPrinter
## 纯静态工具类：录像日志打印

static func print_record(record: ReplayData.BattleRecord) -> void:
	print("==========================================")
	print("Battle Replay Log")
	print("==========================================")
	print("")
	print("## Meta Information")
	print("Battle ID: %s" % record.meta.battle_id)
	print("Recorded At: %s" % _format_timestamp(record.meta.recorded_at))
	print("Tick Interval: %sms" % record.meta.tick_interval)
	print("Total Frames: %d" % record.meta.total_frames)
	print("Result: %s" % record.meta.result)
	print("")

	print("## Initial Actors (%d)" % record.initial_actors.size())
	for actor_init: ReplayData.ActorInitData in record.initial_actors:
		print("  - %s (%s)" % [actor_init.display_name, actor_init.id])
		print("    Team: %s" % actor_init.team)
		if not actor_init.position.is_empty():
			print("    Position: %s" % str(actor_init.position))
		if not actor_init.tags.is_empty():
			print("    Tags: %s" % str(actor_init.tags.keys()))
	print("")

	print("## Timeline (%d frames with events)" % record.timeline.size())
	for frame_data: ReplayData.FrameData in record.timeline:
		if frame_data.events.is_empty():
			continue
		print("Frame %d (%d events):" % [frame_data.frame, frame_data.events.size()])
		for event: Dictionary in frame_data.events:
			_print_event(event, frame_data.frame)

	print("==========================================")
	print("==========================================")

static func _format_timestamp(timestamp: int) -> String:
	var datetime := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

static func _print_event(event: Dictionary, _frame: int) -> void:
	var kind := event.get("kind", "") as String
	var indent := "    "

	print("%s[%s] %s" % [indent, kind, str(event).substr(0, 100)])

	match kind:
		GameEvent.ACTOR_SPAWNED_EVENT:
			var e := GameEvent.ActorSpawned.from_dict(event)
			print("%s  Actor: %s (%s)" % [indent, e.actor_data.get("displayName", ""), e.actor_id])
		GameEvent.ACTOR_DESTROYED_EVENT:
			var e := GameEvent.ActorDestroyed.from_dict(event)
			print("%s  Actor: %s, Reason: %s" % [indent, e.actor_id, e.reason])
		"damage":
			var e := BattleEvents.DamageEvent.from_dict(event)
			print("%s  Source: %s -> Target: %s, Damage: %.0f" % [
				indent, e.source_actor_id, e.target_actor_id, e.damage
			])
		"heal":
			var e := BattleEvents.HealEvent.from_dict(event)
			print("%s  Target: %s, Heal: %.0f" % [indent, e.target_actor_id, e.heal_amount])
		GameEvent.ABILITY_GRANTED_EVENT:
			var e := GameEvent.AbilityGranted.from_dict(event)
			print("%s  Actor: %s, Ability: %s" % [indent, e.actor_id, e.ability.get("id", "")])
		GameEvent.ABILITY_REMOVED_EVENT:
			var e := GameEvent.AbilityRemoved.from_dict(event)
			print("%s  Actor: %s, Ability: %s" % [indent, e.actor_id, e.ability_instance_id])
		GameEvent.TAG_CHANGED_EVENT:
			var e := GameEvent.TagChanged.from_dict(event)
			print("%s  Actor: %s, Tag: %s, Stacks: %d -> %d" % [
				indent, e.actor_id, e.tag, e.old_count, e.new_count
			])
		GameEvent.STAGE_CUE_EVENT:
			var e := GameEvent.StageCue.from_dict(event)
			print("%s  Source: %s, Cue: %s" % [indent, e.source_actor_id, e.cue_id])
		_:
			for key in event.keys():
				if key != "kind" and key != "timestamp":
					print("%s  %s: %s" % [indent, key, str(event[key])])
