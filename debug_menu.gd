extends Control

@onready var info_label = $MarginContainer/Label

var frame_times = []
const MAX_FRAMES = 1000

func _ready():
	visible = false

func _process(delta):
	frame_times.append(delta)
	if frame_times.size() > MAX_FRAMES:
		frame_times.pop_front()
		
	if not visible:
		return
		
	var player = get_tree().get_first_node_in_group("player")
	var state = get_node_or_null("/root/GameState")
	
	var fps = Engine.get_frames_per_second()
	var lows = _calculate_lows()
	
	var text = ""
	text += "GodotCraft build 0.0.8.0\n"
	text += "FPS: %d (1%%: %d, 0.1%%: %d)\n" % [fps, lows.one_percent, lows.zero_one_percent]
	
	if player:
		var pos = player.global_position
		text += "XYZ: %.3f / %.3f / %.3f\n" % [pos.x, pos.y, pos.z]
		
		var world = get_tree().get_first_node_in_group("world")
		if world:
			var cx = floor(pos.x / world.chunk_size)
			var cz = floor(pos.z / world.chunk_size)
			text += "Chunk: %d %d\n" % [cx, cz]
	
	if state:
		text += "Render Distance: %d\n" % state.render_distance
	
	text += "OS: %s\n" % OS.get_name()
	text += "RAM Usage: %.2f MB\n" % (OS.get_static_memory_usage() / 1048576.0)
	
	info_label.text = text

func _calculate_lows():
	if frame_times.is_empty():
		return {"one_percent": 0, "zero_one_percent": 0}
	
	var sorted_times = frame_times.duplicate()
	sorted_times.sort() # Slowest frames (largest deltas) will be at the end
	
	var count = sorted_times.size()
	var one_percent_count = max(1, int(count * 0.01))
	var zero_one_percent_count = max(1, int(count * 0.001))
	
	var one_percent_sum = 0.0
	for i in range(count - one_percent_count, count):
		one_percent_sum += sorted_times[i]
	var one_percent_avg_delta = one_percent_sum / one_percent_count
	
	var zero_one_percent_sum = 0.0
	for i in range(count - zero_one_percent_count, count):
		zero_one_percent_sum += sorted_times[i]
	var zero_one_percent_avg_delta = zero_one_percent_sum / zero_one_percent_count
	
	return {
		"one_percent": int(1.0 / one_percent_avg_delta) if one_percent_avg_delta > 0 else 0,
		"zero_one_percent": int(1.0 / zero_one_percent_avg_delta) if zero_one_percent_avg_delta > 0 else 0
	}

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible
