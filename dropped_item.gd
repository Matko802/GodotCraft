extends Area3D

var type: int
var count: int = 1
var velocity = Vector3.ZERO
var item_gravity = 20.0
var lifetime = 300.0 # 5 minutes
var pickup_delay = 0.1 # Reduced delay for immediate collection
var resting: bool = false
var time_passed: float = 0.0
var being_picked_up: bool = false
var target_player: Node3D = null
var pickup_animation_time: float = 0.0
const PICKUP_ANIMATION_DURATION: float = 0.3

var block_textures = {
	0: preload("res://textures/stone.png"),
	1: preload("res://textures/dirt.png"),
	2: preload("res://textures/grass_side.png"),
	3: preload("res://textures/Sand.png"),
	4: preload("res://textures/bedrock.png"),
	5: preload("res://textures/oak_wood_side.png"),
	6: preload("res://textures/leaves.png")
}

@onready var mesh_instance = $MeshInstance3D

func _ready():
	add_to_group("dropped_items")
	
	# Setup collision for item pickup
	collision_layer = 0  # Not on any physics layer
	collision_mask = 0   # Don't collide with physics
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.3
	collision_shape.shape = sphere
	add_child(collision_shape)
	
	if type == 9: # Torch
		var world = get_tree().get_first_node_in_group("world")
		if world and world.torch_mesh:
			mesh_instance.mesh = world.torch_mesh
			mesh_instance.material_override = world.torch_material
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_instance.scale = Vector3.ONE * 0.6
		return

	# Construct a perfect mini-block using the same logic as the world
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var faces = [
		{"dir": Vector3.UP, "verts": [Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.DOWN, "verts": [Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5)], "uvs": [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]},
		{"dir": Vector3.LEFT, "verts": [Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.RIGHT, "verts": [Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.FORWARD, "verts": [Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.BACK, "verts": [Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
	]
	
	for face in faces:
		st.set_normal(face.dir)
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(face.uvs[i])
			st.add_vertex(face.verts[i] * 0.3) # Scaling here
	
	mesh_instance.mesh = st.commit()
	
	var mat: Material
	var shader = load("res://voxel.gdshader")
	
	if type == 2: # Grass
		var smat = ShaderMaterial.new()
		smat.shader = shader
		smat.set_shader_parameter("top_texture", load("res://textures/grass_top.png"))
		smat.set_shader_parameter("side_texture", load("res://textures/grass_side.png"))
		smat.set_shader_parameter("bottom_texture", load("res://textures/dirt.png"))
		mat = smat
	elif type == 5 or type == 11 or type == 12: # Wood
		var smat = ShaderMaterial.new()
		smat.shader = load("res://voxel_rotated.gdshader") # Use rotated shader for logs
		smat.set_shader_parameter("top_texture", load("res://textures/oak_wood_top.png"))
		smat.set_shader_parameter("side_texture", load("res://textures/oak_wood_side.png"))
		smat.set_shader_parameter("bottom_texture", load("res://textures/oak_wood_top.png"))
		
		var uv = Vector3(0, 1, 0)
		if type == 11: uv = Vector3(1, 0, 0)
		if type == 12: uv = Vector3(0, 0, 1)
		smat.set_shader_parameter("up_vector", uv)
		mat = smat
	else:
		var smat = ShaderMaterial.new()
		smat.shader = shader
		var tex = block_textures.get(type, preload("res://textures/stone.png"))
		# Force all faces to show the same texture for standard blocks
		smat.set_shader_parameter("top_texture", tex)
		smat.set_shader_parameter("side_texture", tex)
		smat.set_shader_parameter("bottom_texture", tex)
		mat = smat
	
	mesh_instance.material_override = mat
	
	# Random initial rotation
	rotation_degrees = Vector3(0, randf() * 360, 0)

func _process(delta):
	# Handle pickup animation
	if being_picked_up:
		pickup_animation_time += delta
		var progress = pickup_animation_time / PICKUP_ANIMATION_DURATION
		
		if progress >= 1.0:
			queue_free()
			return
		
		# Shrink and fade out
		var scale_factor = 1.0 - progress
		mesh_instance.scale = Vector3.ONE * scale_factor
		
		# Fade out by adjusting material transparency
		if mesh_instance.material_override:
			var mat = mesh_instance.material_override.duplicate() as Material
			if mat is StandardMaterial3D:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var col = mat.albedo_color
				col.a = 1.0 - progress
				mat.albedo_color = col
			mesh_instance.material_override = mat
		
		# Move towards player slightly
		if target_player and is_instance_valid(target_player):
			var direction = (target_player.global_position - global_position).normalized()
			global_position += direction * 8.0 * delta
		
		return
	
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
		
	time_passed += delta
	
	if pickup_delay > 0:
		pickup_delay -= delta

	# Gravity and Movement
	var world = get_tree().get_first_node_in_group("world")
	
	# If resting, check if there is still a block below
	if resting and world:
		var below_pos = Vector3i(floor(global_position.x), floor(global_position.y - 0.1), floor(global_position.z))
		var block_below = world.get_block(below_pos)
		if block_below == -1 or block_below == 7 or block_below == 8: # Air or Water
			resting = false

	if not resting or being_picked_up:
		var in_water = false
		if world:
			var current_block_pos = Vector3i(floor(global_position.x), floor(global_position.y), floor(global_position.z))
			var block_type = world.get_block(current_block_pos)
			if block_type == 7 or block_type == 8: # Water or Water Flow
				in_water = true

		if not resting:
			if in_water:
				# Buoyancy: items float up in water
				velocity.y = move_toward(velocity.y, 1.5, delta * 15.0)
				# Horizontal drag in water
				velocity.x = move_toward(velocity.x, 0, delta * 2.0)
				velocity.z = move_toward(velocity.z, 0, delta * 2.0)
			else:
				velocity.y -= item_gravity * delta
		else:
			# Slight upward force to help it slide over small bumps while being pulled
			velocity.y = move_toward(velocity.y, 0, delta * 10.0)
		
		# Safety check: if we are inside a solid block, push us up
		if world:
			var current_block_pos = Vector3i(floor(global_position.x), floor(global_position.y), floor(global_position.z))
			var block_type = world.get_block(current_block_pos)
			if block_type >= 0 and block_type != 7 and block_type != 8 and block_type != 9: # Not air, water, or torch
				global_position.y = ceil(global_position.y) + 0.1
				velocity.y = 0
				resting = true

		var space_state = get_world_3d().direct_space_state
		var next_pos = global_position + velocity * delta
		# Start raycast slightly above current position to detect blocks we might be slightly inside of
		var ray_start = global_position + Vector3(0, 0.2, 0)
		var query = PhysicsRayQueryParameters3D.create(ray_start, next_pos)
		# Only collide with world (Layer 1)
		query.collision_mask = 1
		var result = space_state.intersect_ray(query)
		
		if result:
			if result.normal.y > 0.5: # Floor collision
				global_position.y = result.position.y + 0.05
				velocity.y = 0
				resting = true
				# Add friction to horizontal velocity
				velocity.x *= 0.5
				velocity.z *= 0.5
			else: # Wall collision
				global_position = result.position + result.normal * 0.1
				velocity = velocity.bounce(result.normal) * 0.3
		else:
			global_position = next_pos
			# If we are falling and not currently marked as resting
			if velocity.y < -0.1:
				resting = false
	
	# Secondary fall-through prevention using world data directly
	if not resting and world:
		var feet_pos = Vector3i(floor(global_position.x), floor(global_position.y), floor(global_position.z))
		var feet_block = world.get_block(feet_pos)
		if feet_block >= 0 and feet_block != 7 and feet_block != 8 and feet_block != 9:
			global_position.y = ceil(global_position.y) + 0.05
			velocity.y = 0
			resting = true
	
	# Floating/Bobbing and Spin animation
	var bob = 0.2 + sin(time_passed * 3.0) * 0.1
	mesh_instance.position.y = bob
	mesh_instance.rotate_y(delta * 2.0)
	
	# Check for pickup by proximity to player
	var player = get_tree().get_first_node_in_group("player")
	if player and pickup_delay <= 0 and not being_picked_up:
		var distance = global_position.distance_to(player.global_position)
		if distance < 1.5:  # Pickup radius of 1.5 units
			# Only collect if player has space
			if player.inventory.can_add_item(type, count):
				var added = player.inventory.add_item(type, count)
				if added > 0:
					_play_pickup_sound()
					count -= added
					
					# Start pickup animation
					being_picked_up = true
					target_player = player
					pickup_animation_time = 0.0
					
					# Disable physics during pickup animation
					resting = true
					velocity = Vector3.ZERO
					
					if count <= 0:
						# Item fully picked up, will be freed during animation
						return

func _play_pickup_sound():
	var sound_path = "res://textures/Sounds/random/pop.ogg"
	var stream = null
	var state = get_node_or_null("/root/GameState")
	if state:
		stream = state.get_sound(sound_path)
	
	if not stream:
		if not OS.has_feature("web"):
			stream = load(sound_path)
			
	if not stream:
		return
	
	var audio = AudioStreamPlayer.new()
	audio.stream = stream
	if AudioServer.get_bus_index("Pickup") != -1:
		audio.bus = "Pickup"
	else:
		audio.bus = "Master"
	# Create a temporary node in the world to play the sound
	get_tree().root.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
