extends MeshInstance3D

var velocity = Vector3.ZERO
var gravity = 20.0
var lifetime = 1.5
var resting = false

func _ready():
	# Random rotation speed
	rotation_degrees = Vector3(randf()*360, randf()*360, randf()*360)

func _process(delta):
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
	elif lifetime < 0.5:
		# Fade out
		var mat = material_override
		if mat:
			mat.albedo_color.a = lifetime * 2.0

	if resting:
		return

	velocity.y -= gravity * delta
	
	# Collision detection using RayCast
	var space_state = get_world_3d().direct_space_state
	var current_pos = global_position
	var target_pos = current_pos + velocity * delta
	
	# Raycast slightly further to prevent tunneling
	var query = PhysicsRayQueryParameters3D.create(current_pos, target_pos)
	var result = space_state.intersect_ray(query)
	
	if result:
		if result.normal.y > 0.5: # Floor collision
			global_position = result.position + result.normal * 0.05
			velocity = Vector3.ZERO
			resting = true
		else: # Wall collision
			# Slide out of wall, lose horizontal speed, but keep falling
			global_position = result.position + result.normal * 0.05
			velocity.x = 0
			velocity.z = 0
	else:
		global_position += velocity * delta

	rotate_x(delta * 5.0)
	rotate_y(delta * 5.0)
