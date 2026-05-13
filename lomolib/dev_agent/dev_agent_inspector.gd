class_name DevAgentInspector

## Small, bounded runtime dumps for deciding the next DevAgent command.


static func inspect_tree(root: Node, max_depth: int = 8) -> Dictionary:
	return {
		"root": str(root.get_path()),
		"max_depth": max_depth,
		"tree": _inspect_tree_node(root, 0, max_depth),
	}


static func inspect_controls(root: Node, include_hidden: bool = false) -> Dictionary:
	var controls: Array[Dictionary] = []
	_collect_controls(root, include_hidden, controls)
	return {
		"root": str(root.get_path()),
		"include_hidden": include_hidden,
		"count": controls.size(),
		"controls": controls,
	}


static func dump_node(target: Node) -> Dictionary:
	var dump := _node_base(target)
	dump["groups"] = _groups_to_array(target)
	dump["child_count"] = target.get_child_count()
	dump["children"] = _child_names(target)

	if target is Control:
		dump["control"] = _control_data(target as Control)
	if target is Node2D:
		var node_2d := target as Node2D
		dump["node_2d"] = {
			"global_position": _vector2_to_dict(node_2d.global_position),
			"rotation": node_2d.global_rotation,
			"scale": _vector2_to_dict(node_2d.global_scale),
		}
	if target is Node3D:
		var node_3d := target as Node3D
		dump["node_3d"] = {
			"global_position": _vector3_to_dict(node_3d.global_position),
			"visible": node_3d.visible,
			"visible_in_tree": node_3d.is_visible_in_tree(),
		}
	if target is Label:
		dump["label"] = { "text": (target as Label).text }
	if target is BaseButton:
		var button := target as BaseButton
		dump["button"] = {
			"text": button.text,
			"disabled": button.disabled,
			"button_pressed": button.button_pressed,
		}

	return dump


static func _inspect_tree_node(target: Node, depth: int, max_depth: int) -> Dictionary:
	var entry := _node_base(target)
	entry["depth"] = depth

	if target is CanvasItem:
		var canvas_item := target as CanvasItem
		entry["visible"] = canvas_item.visible
		entry["visible_in_tree"] = canvas_item.is_visible_in_tree()
	elif target is Node3D:
		var node_3d := target as Node3D
		entry["visible"] = node_3d.visible
		entry["visible_in_tree"] = node_3d.is_visible_in_tree()

	var children: Array[Dictionary] = []
	if depth < max_depth:
		for child in target.get_children():
			var child_node := child as Node
			if child_node != null:
				children.append(_inspect_tree_node(child_node, depth + 1, max_depth))
	entry["children"] = children

	return entry


static func _collect_controls(target: Node, include_hidden: bool, controls: Array[Dictionary]) -> void:
	if target is Control:
		var control := target as Control
		if include_hidden or control.is_visible_in_tree():
			controls.append(_control_data(control))

	for child in target.get_children():
		var child_node := child as Node
		if child_node != null:
			_collect_controls(child_node, include_hidden, controls)


static func _node_base(target: Node) -> Dictionary:
	var script_path := ""
	var script := target.get_script()
	if script is Resource:
		script_path = (script as Resource).resource_path

	var parent_path := ""
	if target.get_parent() != null:
		parent_path = str(target.get_parent().get_path())

	return {
		"name": target.name,
		"path": str(target.get_path()),
		"parent": parent_path,
		"class": target.get_class(),
		"script": script_path,
		"process_mode": target.process_mode,
	}


static func _control_data(control: Control) -> Dictionary:
	var focus_owner := control.get_viewport().gui_get_focus_owner()
	var data := _node_base(control)
	data["rect"] = _rect2_to_dict(control.get_global_rect())
	data["visible"] = control.visible
	data["visible_in_tree"] = control.is_visible_in_tree()
	data["mouse_filter"] = control.mouse_filter
	data["focus_mode"] = control.focus_mode
	data["has_focus"] = focus_owner == control

	if control is BaseButton:
		var button := control as BaseButton
		data["text"] = button.text
		data["disabled"] = button.disabled
	elif control is Label:
		data["text"] = (control as Label).text
	elif control is LineEdit:
		data["text"] = (control as LineEdit).text

	return data


static func _child_names(target: Node) -> Array[String]:
	var names: Array[String] = []
	for child in target.get_children():
		var child_node := child as Node
		if child_node != null:
			names.append(child_node.name)
	return names


static func _groups_to_array(target: Node) -> Array[String]:
	var groups: Array[String] = []
	for group in target.get_groups():
		groups.append(str(group))
	return groups


static func _rect2_to_dict(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


static func _vector2_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


static func _vector3_to_dict(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}
