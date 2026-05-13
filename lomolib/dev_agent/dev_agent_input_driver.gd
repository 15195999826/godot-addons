class_name DevAgentInputDriver

## Real Godot input injection helpers for development-time debugging.


static func click_at(ctx: Node, pos: Vector2, button_index: int = MOUSE_BUTTON_LEFT) -> Dictionary:
	var viewport := ctx.get_viewport()
	if viewport == null:
		return {
			"ok": false,
			"message": "no viewport available for click_at",
		}

	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	viewport.push_input(motion)
	await ctx.get_tree().process_frame

	var press := InputEventMouseButton.new()
	press.button_index = button_index
	press.pressed = true
	press.position = pos
	press.global_position = pos
	viewport.push_input(press)
	await ctx.get_tree().process_frame

	var release := InputEventMouseButton.new()
	release.button_index = button_index
	release.pressed = false
	release.position = pos
	release.global_position = pos
	viewport.push_input(release)
	await ctx.get_tree().process_frame

	return {
		"ok": true,
		"message": "clicked at %.1f, %.1f" % [pos.x, pos.y],
		"data": {
			"x": pos.x,
			"y": pos.y,
			"button": button_index,
		},
	}


static func drag_at(ctx: Node, from_pos: Vector2, to_pos: Vector2, button_index: int = MOUSE_BUTTON_LEFT, steps: int = 8) -> Dictionary:
	var viewport := ctx.get_viewport()
	if viewport == null:
		return {
			"ok": false,
			"message": "no viewport available for drag_at",
		}

	var safe_steps := maxi(1, steps)
	var press := InputEventMouseButton.new()
	press.button_index = button_index
	press.pressed = true
	press.position = from_pos
	press.global_position = from_pos
	viewport.push_input(press)
	await ctx.get_tree().process_frame

	var last_pos := from_pos
	for i in range(1, safe_steps + 1):
		var weight := float(i) / float(safe_steps)
		var pos := from_pos.lerp(to_pos, weight)
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.relative = pos - last_pos
		motion.button_mask = _button_mask_for(button_index)
		viewport.push_input(motion)
		last_pos = pos
		await ctx.get_tree().process_frame

	var release := InputEventMouseButton.new()
	release.button_index = button_index
	release.pressed = false
	release.position = to_pos
	release.global_position = to_pos
	viewport.push_input(release)
	await ctx.get_tree().process_frame

	return {
		"ok": true,
		"message": "dragged from %.1f, %.1f to %.1f, %.1f" % [from_pos.x, from_pos.y, to_pos.x, to_pos.y],
		"data": {
			"from_x": from_pos.x,
			"from_y": from_pos.y,
			"to_x": to_pos.x,
			"to_y": to_pos.y,
			"button": button_index,
			"steps": safe_steps,
		},
	}


static func tap_key(ctx: Node, key_text: String) -> Dictionary:
	var viewport := ctx.get_viewport()
	if viewport == null:
		return {
			"ok": false,
			"message": "no viewport available for tap_key",
		}

	var keycode := keycode_from_string(key_text)
	if keycode == KEY_NONE:
		return {
			"ok": false,
			"message": "unsupported key: %s" % key_text,
		}

	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	press.unicode = _unicode_for_key(key_text)
	viewport.push_input(press)
	await ctx.get_tree().process_frame

	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	release.unicode = _unicode_for_key(key_text)
	viewport.push_input(release)
	await ctx.get_tree().process_frame

	return {
		"ok": true,
		"message": "tapped key: %s" % key_text,
		"data": {
			"key": key_text,
			"keycode": keycode,
		},
	}


static func mouse_button_from_value(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return value as int

	var text := str(value).strip_edges().to_lower()
	match text:
		"", "left", "mouse_left", "1":
			return MOUSE_BUTTON_LEFT
		"right", "mouse_right", "2":
			return MOUSE_BUTTON_RIGHT
		"middle", "mouse_middle", "3":
			return MOUSE_BUTTON_MIDDLE
		_:
			return MOUSE_BUTTON_LEFT


static func keycode_from_string(key_text: String) -> Key:
	var text := key_text.strip_edges()
	if text.is_empty():
		return KEY_NONE

	match text.to_upper():
		"ESC", "ESCAPE":
			return KEY_ESCAPE
		"ENTER", "RETURN":
			return KEY_ENTER
		"SPACE", "SPACEBAR":
			return KEY_SPACE
		"TAB":
			return KEY_TAB
		"BACKSPACE":
			return KEY_BACKSPACE
		"DELETE":
			return KEY_DELETE
		"UP":
			return KEY_UP
		"DOWN":
			return KEY_DOWN
		"LEFT":
			return KEY_LEFT
		"RIGHT":
			return KEY_RIGHT

	var keycode := OS.find_keycode_from_string(text)
	if keycode != KEY_NONE:
		return keycode

	if text.length() == 1:
		return OS.find_keycode_from_string(text.to_upper())

	return KEY_NONE


static func _unicode_for_key(key_text: String) -> int:
	var text := key_text.strip_edges()
	if text.length() == 1:
		return text.unicode_at(0)
	return 0


static func _button_mask_for(button_index: int) -> int:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
		_:
			return 0
