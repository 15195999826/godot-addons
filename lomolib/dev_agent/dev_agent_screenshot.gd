class_name DevAgentScreenshot

## Viewport screenshot capture for DevAgent sessions.


static func capture_viewport(ctx: Node, screenshots_dir: String, file_stem: String) -> Dictionary:
	var viewport := ctx.get_viewport()
	if viewport == null:
		return {
			"ok": false,
			"message": "no viewport available for capture",
		}

	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(screenshots_dir))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return {
			"ok": false,
			"message": "failed to create screenshot directory: %s" % screenshots_dir,
			"data": { "error": dir_error },
		}

	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var user_path := "%s/%s.png" % [screenshots_dir, _safe_file_stem(file_stem)]
	var save_error := image.save_png(user_path)
	if save_error != OK:
		return {
			"ok": false,
			"message": "failed to save screenshot: %s" % user_path,
			"data": { "error": save_error },
		}

	var global_path := ProjectSettings.globalize_path(user_path)
	print("[DevAgent] screenshot: %s" % global_path)
	return {
		"ok": true,
		"message": "screenshot captured",
		"artifacts": [
			{
				"kind": "screenshot",
				"path": user_path,
				"global_path": global_path,
			},
		],
	}


static func _safe_file_stem(value: String) -> String:
	var result := value.strip_edges()
	if result.is_empty():
		result = "capture"

	for token in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", " "]:
		result = result.replace(token, "_")

	return result
