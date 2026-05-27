## Cone debug overlay action - checked cells fill + boundary/guide segments.
class_name FrontendConeDebugOverlayAction
extends FrontendVisualAction


var cue_id: String = ""
var cell_polygons: Array[PackedVector3Array] = []
var boundary_segments: Array[PackedVector3Array] = []
var fill_color: Color = Color.WHITE
var boundary_color: Color = Color.WHITE


func _init(
	p_cue_id: String,
	p_cell_polygons: Array[PackedVector3Array],
	p_boundary_segments: Array[PackedVector3Array],
	p_fill_color: Color,
	p_boundary_color: Color,
	p_duration: float,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.CONE_DEBUG_OVERLAY, p_duration, p_delay)
	cue_id = p_cue_id
	cell_polygons = p_cell_polygons
	boundary_segments = p_boundary_segments
	fill_color = p_fill_color
	boundary_color = p_boundary_color
