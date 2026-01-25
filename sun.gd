extends Sprite3D

@onready var light = get_node("../DefaultLight")

func _process(_delta):
	var player = get_tree().get_first_node_in_group("player")
	if player and light:
		var camera = player.get_node("Camera3D")
		if camera:
			# Position the sun far away in the direction opposite to the light's forward vector
			var light_dir = -light.global_transform.basis.z.normalized()
			global_position = camera.global_position + light_dir * 100.0
			# Make it look at the camera (it's a billboard anyway, but good for orientation)
			look_at(camera.global_position)
