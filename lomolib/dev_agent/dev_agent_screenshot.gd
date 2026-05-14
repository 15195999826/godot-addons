class_name DevAgentScreenshot

## Viewport screenshot capture for DevAgent sessions.
##
## Defaults are tuned for AI-agent consumption:
## - 960px wide JPEG q=80 ≈ 25–40 KB / 张, Anthropic vision token 消耗约为
##   1920×1080 PNG 的一半 (服务端不再二次缩放)。
## - 真要原始保真度 (布局回归、像素精度比对) 时 caller 传 width=0 + format=png。


const DEFAULT_WIDTH := 960
const DEFAULT_FORMAT := "jpeg"
const DEFAULT_QUALITY := 80


static func capture_viewport(
	ctx: Node,
	screenshots_dir: String,
	file_stem: String,
	options: Dictionary = {},
) -> Dictionary:
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

	var target_width: int = int(options.get("width", DEFAULT_WIDTH))
	var format: String = str(options.get("format", DEFAULT_FORMAT)).to_lower()
	if format == "jpg":
		format = "jpeg"
	if format != "png" and format != "jpeg":
		return {
			"ok": false,
			"message": "unsupported screenshot format: %s (use png or jpeg)" % format,
		}
	var quality: int = clampi(int(options.get("quality", DEFAULT_QUALITY)), 1, 100)

	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var original_size := image.get_size()
	var resized := false
	if target_width > 0 and original_size.x > target_width:
		var aspect: float = float(original_size.y) / float(original_size.x)
		var target_height: int = maxi(1, int(round(float(target_width) * aspect)))
		image.resize(target_width, target_height, Image.INTERPOLATE_BILINEAR)
		resized = true

	var extension := "png" if format == "png" else "jpg"
	var user_path := "%s/%s.%s" % [screenshots_dir, _safe_file_stem(file_stem), extension]
	var save_error: int
	if format == "png":
		save_error = image.save_png(user_path)
	else:
		save_error = image.save_jpg(user_path, float(quality) / 100.0)
	if save_error != OK:
		return {
			"ok": false,
			"message": "failed to save screenshot: %s" % user_path,
			"data": { "error": save_error },
		}

	var saved_size := image.get_size()
	var global_path := ProjectSettings.globalize_path(user_path)
	var file_bytes: int = 0
	var file := FileAccess.open(user_path, FileAccess.READ)
	if file != null:
		file_bytes = file.get_length()
		file.close()
	print("[DevAgent] screenshot: %s (%dx%d %s, %.1f KB)" % [
		global_path, saved_size.x, saved_size.y, format, float(file_bytes) / 1024.0,
	])
	return {
		"ok": true,
		"message": "screenshot captured (%dx%d %s, %.1f KB)" % [
			saved_size.x, saved_size.y, format, float(file_bytes) / 1024.0,
		],
		"data": {
			"format": format,
			"width": saved_size.x,
			"height": saved_size.y,
			"original_width": original_size.x,
			"original_height": original_size.y,
			"resized": resized,
			"quality": quality if format == "jpeg" else 0,
			"bytes": file_bytes,
		},
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
