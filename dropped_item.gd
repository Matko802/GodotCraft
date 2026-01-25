extends Node3D

var type: int
var count: int = 1
var velocity = Vector3.ZERO
var gravity = 20.0
var lifetime = 300.0 # 5 minutes
var pickup_delay = 0.1 # Reduced delay for immediate collection
var resting: bool = false
var time_passed: float = 0.0
var being_picked_up: bool = false
var target_player: Node3D = null

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
	elif type == 5: # Wood
		var smat = ShaderMaterial.new()
		smat.shader = shader
		smat.set_shader_parameter("top_texture", load("res://textures/oak_wood_top.png"))
		smat.set_shader_parameter("side_texture", load("res://textures/oak_wood_side.png"))
		smat.set_shader_parameter("bottom_texture", load("res://textures/oak_wood_top.png"))
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
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
		
	time_passed += delta
	
	if pickup_delay > 0:
		pickup_delay -= delta

	if not resting:
		# Simple gravity and collision
		velocity.y -= gravity * delta
		
		var space_state = get_world_3d().direct_space_state
		var next_pos = global_position + velocity * delta
		var query = PhysicsRayQueryParameters3D.create(global_position, next_pos)
		var result = space_state.intersect_ray(query)
		
		if result:
			if result.normal.y > 0.5: # Floor collision
				global_position = result.position + Vector3(0, 0.2, 0)
				velocity = Vector3.ZERO
				resting = true
			else: # Wall collision
				# Slide out of the wall and lose horizontal momentum, but keep falling
				global_position = result.position + result.normal * 0.1
				velocity.x = 0
				velocity.z = 0
		else:
			global_position = next_pos
	
	# Floating/Bobbing and Spin animation
	var bob = sin(time_passed * 3.0) * 0.1
	mesh_instance.position.y = bob
	mesh_instance.rotate_y(delta * 2.0)
	
	# Check for player pickup
	if pickup_delay <= 0:
		var players = get_tree().get_nodes_in_group("player")
		for player in players:
			var dist = global_position.distance_to(player.global_position)
			
			if dist < 0.6:
				if player.inventory.add_item(type, count):
					_play_pickup_sound()
					queue_free()
					return
			elif dist < 3.5: # Increased attraction range
				being_picked_up = true
				target_player = player
				# Stronger attraction effect
				var dir = (player.global_position + Vector3(0, 0.5, 0) - global_position).normalized()
				velocity = velocity.lerp(dir * 10.0, delta * 8.0)
				global_position += velocity * delta
				
				# Shrink animation when close
				var s = clamp(dist - 0.5, 0.1, 1.0)
				mesh_instance.scale = Vector3.ONE * s
				return # Only attract to one player

func _play_pickup_sound():
	var audio = AudioStreamPlayer.new()
	audio.stream = load("res://textures/Sounds/random/pop.ogg")
	audio.bus = "Master"
	# Create a temporary node in the world to play the sound
	get_tree().root.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
