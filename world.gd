extends Node3D

@export var chunk_size = 16
@export var chunk_height = 64
@export var world_seed = "GodotCraft"
@export var render_distance = 4

enum BlockType { STONE, DIRT, GRASS, SAND, BEDROCK, WOOD, LEAVES, WATER, WATER_FLOW }

const BLOCK_TEXTURES = {
	0: "res://textures/stone.png",
	1: "res://textures/dirt.png",
	2: "res://textures/grass_side.png",
	3: "res://textures/Sand.png",
	4: "res://textures/bedrock.png",
	5: "res://textures/oak_wood_side.png",
	6: "res://textures/leaves.png"
}

const BLOCK_SOUNDS = {
	"stone": [
		"res://textures/Sounds/block_broke/stone1.ogg",
		"res://textures/Sounds/block_broke/stone2.ogg",
		"res://textures/Sounds/block_broke/stone3.ogg",
		"res://textures/Sounds/block_broke/stone4.ogg"
	],
	"gravel": [
		"res://textures/Sounds/block_broke/gravel1.ogg",
		"res://textures/Sounds/block_broke/gravel2.ogg",
		"res://textures/Sounds/block_broke/gravel3.ogg",
		"res://textures/Sounds/block_broke/gravel4.ogg"
	],
	"grass": [
		"res://textures/Sounds/block_breaking/grass1.ogg",
		"res://textures/Sounds/block_breaking/grass2.ogg",
		"res://textures/Sounds/block_breaking/grass3.ogg",
		"res://textures/Sounds/block_breaking/grass4.ogg"
	],
	"sand": [
		"res://textures/Sounds/block_breaking/sand1.ogg",
		"res://textures/Sounds/block_breaking/sand2.ogg",
		"res://textures/Sounds/block_breaking/sand3.ogg",
		"res://textures/Sounds/block_breaking/sand4.ogg"
	],
	"wood": [
		"res://textures/Sounds/block_breaking/wood1.ogg",
		"res://textures/Sounds/block_breaking/wood2.ogg",
		"res://textures/Sounds/block_breaking/wood3.ogg",
		"res://textures/Sounds/block_breaking/wood4.ogg"
	]
}

const TYPE_TO_SOUND = {
	BlockType.STONE: "stone",
	BlockType.DIRT: "gravel",
	BlockType.GRASS: "grass",
	BlockType.SAND: "sand",
	BlockType.WOOD: "wood",
	BlockType.LEAVES: "grass"
}

const DROPPED_ITEM_SCENE = preload("res://dropped_item.tscn")

var world_data = {} # {Vector2i: {Vector3i: type}}
var water_levels = {} # {Vector2i: {Vector3i: level}}
var chunks = {} # {Vector2i: Node3D}
var chunk_data_status = {} # {Vector2i: bool}
var noise = FastNoiseLite.new()
var biome_noise = FastNoiseLite.new()
var water_timer = 0.0
var water_update_queue = {} # Using dictionary as a set: {Vector3i: bool}
var water_tick_timer = 0.0
var water_frame = 0

var last_player_chunk = Vector2i(999, 999)
var chunks_data_to_generate = [] 
var chunks_data_to_generate_set = {}
var chunks_to_generate = [] 
var chunks_to_generate_set = {} 
var chunks_needing_rebuild = {} # {Vector2i: bool}
var generation_speed = 1 # Chunks per frame to mesh (main thread part)
var data_gen_limit = 4 # Max concurrent data gen tasks
var active_data_tasks = 0
var active_mesh_tasks = {} # {Vector2i: task_id}
var chunk_meshed_status = {} # {Vector2i: bool}
var mesh_throttle_timer = 0.0

var spawn_pos = Vector3(8, 40, 8)
var world_mutex = Mutex.new()

# Time system (0 to 24000, 24000 ticks = 20 minutes)
var time: float = 6000.0 # Start at Noon
const TICKS_PER_SECOND = 20.0
const MAX_TIME = 24000.0

@onready var sun = $DefaultLight
@onready var world_env = $WorldEnvironment
@onready var celestial_bodies = $CelestialBodies

var is_loading = true
var total_spawn_chunks = 0

# Materials
var materials = {}

const SEA_LEVEL = 12

const FACES = [
	{
		"dir": Vector3i.UP, 
		"verts": [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)], 
		"uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)], 
		"normal": Vector3.UP
	},
	{
		"dir": Vector3i.DOWN, 
		"verts": [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)], 
		"uvs": [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)], 
		"normal": Vector3.DOWN
	},
	{
		"dir": Vector3i.LEFT, 
		"verts": [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)], 
		"uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)], 
		"normal": Vector3.LEFT
	},
	{
		"dir": Vector3i.RIGHT, 
		"verts": [Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)], 
		"uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)], 
		"normal": Vector3.RIGHT
	},
	{
		"dir": Vector3i.FORWARD, 
		"verts": [Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)], 
		"uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)], 
		"normal": Vector3.FORWARD
	},
	{
		"dir": Vector3i.BACK, 
		"verts": [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)], 
		"uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)], 
		"normal": Vector3.BACK
	},
]

func get_block(world_pos: Vector3i):
	var cx = floor(float(world_pos.x) / chunk_size)
	var cz = floor(float(world_pos.z) / chunk_size)
	var c_pos = Vector2i(cx, cz)
	
	world_mutex.lock()
	var chunk = world_data.get(c_pos)
	var type = -1
	if chunk:
		type = chunk.get(world_pos, -1)
	world_mutex.unlock()
	return type

func get_highest_block_y(x: int, z: int) -> int:
	var cx = floor(float(x) / chunk_size)
	var cz = floor(float(z) / chunk_size)
	var c_pos = Vector2i(cx, cz)
	
	var highest_y = SEA_LEVEL
	world_mutex.lock()
	var chunk = world_data.get(c_pos)
	if chunk:
		for pos in chunk:
			if pos.x == x and pos.z == z:
				# We want to spawn on solid blocks, not water
				var type = chunk[pos]
				if type != BlockType.WATER and type != BlockType.WATER_FLOW:
					highest_y = max(highest_y, pos.y)
	world_mutex.unlock()
	return highest_y

func set_block(world_pos: Vector3i, type):
	if type == -1:
		remove_block(world_pos)
		return
		
	var cx = floor(float(world_pos.x) / chunk_size)
	var cz = floor(float(world_pos.z) / chunk_size)
	var c_pos = Vector2i(cx, cz)
	
	world_mutex.lock()
	if not world_data.has(c_pos):
		world_data[c_pos] = {}
	world_data[c_pos][world_pos] = type
	world_mutex.unlock()
	
	_update_chunk_at(world_pos)
	_schedule_water_update(world_pos)
	for face in FACES:
		_schedule_water_update(world_pos + face.dir)

func remove_block(world_pos: Vector3i):
	var cx = floor(float(world_pos.x) / chunk_size)
	var cz = floor(float(world_pos.z) / chunk_size)
	var c_pos = Vector2i(cx, cz)
	
	world_mutex.lock()
	var chunk = world_data.get(c_pos)
	if chunk and chunk.has(world_pos):
		var type = chunk[world_pos]
		
		spawn_break_particles(Vector3(world_pos), type)
		play_break_sound(Vector3(world_pos), type)
		
		chunk.erase(world_pos)
		
		var w_chunk = water_levels.get(c_pos)
		if w_chunk:
			w_chunk.erase(world_pos)
			
		world_mutex.unlock()
		_update_chunk_at(world_pos)
		_schedule_water_update(world_pos)
		for face in FACES:
			_schedule_water_update(world_pos + face.dir)
	else:
		world_mutex.unlock()

const DEBRIS_SCRIPT = preload("res://debris.gd")

func spawn_break_particles(pos: Vector3, type: int):
	if type == BlockType.WATER or type == BlockType.WATER_FLOW: return
	
	var tex_path = BLOCK_TEXTURES.get(type, "res://textures/stone.png")
	var texture = null
	if ResourceLoader.exists(tex_path):
		texture = load(tex_path)
	
	# Spawn 8 debris chunks
	for i in range(8):
		var debris = MeshInstance3D.new()
		# Use QuadMesh for 2D look
		var quad = QuadMesh.new()
		quad.size = Vector2(0.125, 0.125)
		debris.mesh = quad
		
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.roughness = 1.0
		mat.albedo_texture = texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED # Always face camera
		
		# Random UV offset to make chunks look different
		mat.uv1_offset = Vector3(randf(), randf(), 0)
		mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
		
		debris.material_override = mat
		debris.set_script(DEBRIS_SCRIPT)
		
		add_child(debris)
		
		# Start near the center of the block but spread out
		var offset = Vector3(randf()-0.5, randf()-0.5, randf()-0.5) * 0.5
		debris.global_position = pos + Vector3(0.5, 0.5, 0.5) + offset
		
		# Pop up slightly and fall
		debris.velocity = Vector3(randf() - 0.5, randf() * 2.0, randf() - 0.5) * 2.0

func play_break_sound(pos: Vector3, type: int):
	var category = TYPE_TO_SOUND.get(type, "stone")
	var sound_paths = BLOCK_SOUNDS.get(category, BLOCK_SOUNDS["stone"])
	var sound_path = sound_paths[randi() % sound_paths.size()]
	
	var audio = AudioStreamPlayer3D.new()
	audio.stream = load(sound_path)
	audio.bus = "Master"
	# Minecraft-like attenuation: very audible up to unit_size, then fades
	audio.unit_size = 15.0 
	audio.max_distance = 64.0
	audio.attenuation_filter_cutoff_hz = 20000.0 # No muffling
	add_child(audio)
	# Center of the block - must set after add_child for global_position to work
	audio.global_position = pos + Vector3(0.5, 0.5, 0.5)
	audio.play()
	audio.finished.connect(audio.queue_free)

func play_place_sound(pos: Vector3, type: int):
	# Usually placement sounds are the same as break/hit sounds in these games
	var category = TYPE_TO_SOUND.get(type, "stone")
	# We use "block_breaking" sounds for placement as they are the standard "thud"
	var sound_paths = BLOCK_SOUNDS.get(category, BLOCK_SOUNDS["stone"])
	var sound_path = sound_paths[randi() % sound_paths.size()]
	
	var audio = AudioStreamPlayer3D.new()
	audio.stream = load(sound_path)
	audio.bus = "Master"
	audio.unit_size = 12.0
	audio.max_distance = 48.0
	audio.pitch_scale = randf_range(0.8, 1.2) # Vary pitch for placement
	add_child(audio)
	# Center of the block
	audio.global_position = pos + Vector3(0.5, 0.5, 0.5)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _schedule_water_update(pos: Vector3i):
	if pos.y < 0 or pos.y >= chunk_height * 2: return
	water_update_queue[pos] = true

func _update_chunk_at(world_pos: Vector3i):
	var cx = floor(float(world_pos.x) / chunk_size)
	var cz = floor(float(world_pos.z) / chunk_size)
	var c_pos = Vector2i(cx, cz)
	
	if chunks.has(c_pos):
		# Rebuild current chunk
		_rebuild_chunk(c_pos)
	
	# Check if we need to update neighbors (if block is on edge)
	var local_x = world_pos.x - (cx * chunk_size)
	var local_z = world_pos.z - (cz * chunk_size)
	
	if local_x == 0: _rebuild_chunk(Vector2i(cx - 1, cz))
	if local_x == chunk_size - 1: _rebuild_chunk(Vector2i(cx + 1, cz))
	if local_z == 0: _rebuild_chunk(Vector2i(cx, cz - 1))
	if local_z == chunk_size - 1: _rebuild_chunk(Vector2i(cx, cz + 1))

func _rebuild_chunk(c_pos: Vector2i):
	# Don't queue-free immediately to avoid flickering while building
	# Instead, we will replace the node once the new one is ready
	create_chunk(c_pos.x, c_pos.y)

func _ready():
	add_to_group("world")
	var state = get_node_or_null("/root/GameState")
	if state:
		world_seed = state.world_seed
		render_distance = state.render_distance
	
	noise.seed = hash(world_seed)
	noise.frequency = 0.005
	noise.fractal_octaves = 5
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	biome_noise.seed = hash(world_seed) + 1234
	biome_noise.frequency = 0.003
	biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	_setup_materials()
	
	# Prepare loading screen
	if has_node("LoadingLayer"):
		$LoadingLayer.visible = true
		$LoadingLayer/ProgressBar.value = 0
		
	# Disable player until world is ready
	if has_node("Player"):
		$Player.set_physics_process(false)
		$Player.set_process(false)
		$Player.visible = false
		if $Player.has_node("HUD"):
			$Player/HUD.visible = false

	if state and state.current_save_name != "":
		var data = state.load_game_data(state.current_save_name)
		if data:
			_load_world_data(data)
	else:
		if has_node("Player"):
			$Player.global_position = spawn_pos
	
	# Initial player chunk for progress tracking
	var p_pos = spawn_pos
	if has_node("Player"):
		p_pos = $Player.global_position
	last_player_chunk = Vector2i(floor(p_pos.x / chunk_size), floor(p_pos.z / chunk_size))

	_update_sun_rotation()

	# Calculate total spawn chunks for progress bar, but we'll finish earlier
	total_spawn_chunks = (render_distance * 2 + 1) * (render_distance * 2 + 1)
	
	# Immediately trigger chunk updates
	update_chunks(p_pos)

func _load_world_data(data):
	world_mutex.lock()
	if data.has("seed"):
		world_seed = data["seed"]
		noise.seed = hash(world_seed)
		biome_noise.seed = hash(world_seed) + 1234
	
	if data.has("world_data"):
		world_data = data["world_data"]
		
	if data.has("chunk_data_status"):
		chunk_data_status = data["chunk_data_status"]
	world_mutex.unlock()
	
	if data.has("player_pos") and has_node("Player"):
		var p_pos = data["player_pos"]
		$Player.global_position = p_pos
		$Player.rotation = data.get("player_rot", Vector3.ZERO)
		
	if data.has("inventory") and has_node("Player/Inventory"):
		var inv = $Player/Inventory
		inv.hotbar = data["inventory"]["hotbar"]
		inv.inventory = data["inventory"]["inventory"]
		inv.inventory_changed.emit()
		
	if data.has("time"):
		time = data["time"]
		
	var state = get_node_or_null("/root/GameState")
	if state:
		if data.has("rules"):
			state.rules = data["rules"]
		if data.has("ops"):
			state.ops = data["ops"]
		if data.has("gamemode"):
			state.gamemode = data["gamemode"]
	
	if data.has("dropped_items"):
		# Clear existing dropped items if any
		for item in get_tree().get_nodes_in_group("dropped_items"):
			item.queue_free()
			
		for d in data["dropped_items"]:
			# Ensure we don't spawn items if they were somehow invalid
			if d.get("type", -1) == -1: continue
			
			var item = DROPPED_ITEM_SCENE.instantiate()
			item.type = d["type"]
			item.count = d.get("count", 1)
			add_child(item)
			item.global_position = d["pos"]
			item.velocity = d.get("vel", Vector3.ZERO)
			# Prevent immediate pickup when loading
			item.pickup_delay = 1.0 

func _update_sun_rotation():
	if not sun or not celestial_bodies: return
	
	# Position following player
	var player = get_tree().get_first_node_in_group("player")
	if player:
		celestial_bodies.global_position = player.global_position

	# Rotation: 0 is sunrise, 6000 is noon, 12000 is sunset, 18000 is midnight
	var angle = (time / MAX_TIME) * 360.0
	celestial_bodies.rotation_degrees.x = angle
	
	# Light rotation should match the sun's position
	# When sun is at 90 degrees (overhead), light should point down (-90)
	sun.rotation_degrees.x = -angle
	sun.rotation_degrees.y = 180.0

	# Adjust light intensity and environment based on time
	var is_day = time < 12000
	var cycle_pos = time / 12000.0 if is_day else (time - 12000.0) / 12000.0
	var strength = sin(cycle_pos * PI)
	
	# Light energy: bright at day, dim at night but still visible
	sun.light_energy = strength * (1.1 if is_day else 0.2) + 0.15
	sun.light_color = Color(1.0, 0.95, 0.8).lerp(Color(0.5, 0.5, 0.8), 0.0 if is_day else 1.0)
	
	if world_env:
		var env = world_env.environment
		var day_sky = Color(0.5, 0.7, 1.0)
		var night_sky = Color(0.1, 0.1, 0.15) # Brighter night sky
		
		var sky_color = night_sky.lerp(day_sky, strength if is_day else 0.0)
		var horizon_color = sky_color.darkened(0.1)
		
		env.sky.sky_material.sky_top_color = sky_color
		env.sky.sky_material.sky_horizon_color = horizon_color
		env.sky.sky_material.ground_bottom_color = horizon_color
		env.sky.sky_material.ground_horizon_color = horizon_color
		
		# Set ambient light to around 40% at night to keep everything visible
		env.ambient_light_energy = strength * (1.0 if is_day else 0.4) + 0.15
		env.ambient_light_color = Color(1, 1, 1).lerp(Color(0.4, 0.4, 0.6), 0.0 if is_day else 1.0)
		
		# Adjust fog for atmospheric depth
		# Volumetric fog is Forward+ only, so we avoid setting it if not needed
		# But we can still adjust basic fog if it were enabled
		pass

func save_game():
	var state = get_node_or_null("/root/GameState")
	if state and state.current_save_name != "":
		# Hide UI for screenshot
		var hud = get_node_or_null("Player/HUD")
		var pause_layer = get_node_or_null("Player/PauseLayer")
		if hud: hud.visible = false
		if pause_layer: pause_layer.visible = false
		
		# Wait for render frame to ensure UI is hidden in capture
		await RenderingServer.frame_post_draw
		
		var img = get_viewport().get_texture().get_image()
		# Resize to small thumbnail to speed up save_png
		img.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		
		# Restore UI immediately so user doesn't see flicker
		if hud: hud.visible = true
		if pause_layer: pause_layer.visible = true

		var inv_data = {"hotbar": [], "inventory": []}
		if has_node("Player/Inventory"):
			var inv = $Player/Inventory
			inv_data["hotbar"] = inv.hotbar
			inv_data["inventory"] = inv.inventory

		var dropped_items_data = []
		for item in get_tree().get_nodes_in_group("dropped_items"):
			if is_instance_valid(item):
				dropped_items_data.append({
					"type": item.type,
					"count": item.count,
					"pos": item.global_position,
					"vel": item.velocity
				})

		world_mutex.lock()
		var data = {
			"seed": world_seed,
			"world_data": world_data.duplicate(),
			"chunk_data_status": chunk_data_status.duplicate(),
			"player_pos": $Player.global_position,
			"player_rot": $Player.rotation,
			"inventory": inv_data,
			"rules": state.rules.duplicate(),
			"ops": state.ops.duplicate(),
			"gamemode": state.gamemode,
			"dropped_items": dropped_items_data,
			"time": time
		}
		world_mutex.unlock()
		
		var save_name = state.current_save_name
		var thumb_path = state.SAVES_DIR + save_name + ".png"
		var state_id = state.get_instance_id()
		
		# Use WorkerThreadPool for background saving to prevent freeze
		WorkerThreadPool.add_task(func():
			img.save_png(thumb_path)
			var inner_state = instance_from_id(state_id)
			if inner_state:
				inner_state.save_game(save_name, data)
			print("Threaded save complete: ", save_name)
		)


func _setup_materials():
	var types = {
		BlockType.STONE: {"color": Color.WHITE, "tex": "res://textures/stone.png"},
		BlockType.DIRT: {"color": Color.WHITE, "tex": "res://textures/dirt.png"},
		BlockType.SAND: {"color": Color(0.85, 0.85, 0.85), "tex": "res://textures/Sand.png"},
		BlockType.BEDROCK: {"color": Color.WHITE, "tex": "res://textures/bedrock.png"},
		BlockType.LEAVES: {"color": Color.WHITE, "tex": "res://textures/leaves.png"},
		BlockType.WATER: {"color": Color(1, 1, 1, 0.6), "tex": "res://textures/water0.png"},
		BlockType.WATER_FLOW: {"color": Color(1, 1, 1, 0.6), "tex": "res://textures/water0.png"}
	}
	
	for type in types:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = types[type]["color"]
		var texture_path = types[type]["tex"]
		if ResourceLoader.exists(texture_path):
			mat.albedo_texture = load(texture_path)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if type == BlockType.WATER or type == BlockType.WATER_FLOW:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[type] = mat
	
	# Grass Multi-texture
	var grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://voxel.gdshader")
	if ResourceLoader.exists("res://textures/grass_top.png"):
		grass_mat.set_shader_parameter("top_texture", load("res://textures/grass_top.png"))
	if ResourceLoader.exists("res://textures/grass_side.png"):
		grass_mat.set_shader_parameter("side_texture", load("res://textures/grass_side.png"))
	if ResourceLoader.exists("res://textures/dirt.png"):
		grass_mat.set_shader_parameter("bottom_texture", load("res://textures/dirt.png"))
	materials[BlockType.GRASS] = grass_mat

	# Wood Multi-texture
	var wood_mat = ShaderMaterial.new()
	wood_mat.shader = load("res://voxel.gdshader")
	if ResourceLoader.exists("res://textures/oak_wood_top.png"):
		wood_mat.set_shader_parameter("top_texture", load("res://textures/oak_wood_top.png"))
		wood_mat.set_shader_parameter("bottom_texture", load("res://textures/oak_wood_top.png"))
	if ResourceLoader.exists("res://textures/oak_wood_side.png"):
		wood_mat.set_shader_parameter("side_texture", load("res://textures/oak_wood_side.png"))
	materials[BlockType.WOOD] = wood_mat

	# Sun & Moon setup
	var sun_node = get_node_or_null("CelestialBodies/Sun")
	if sun_node:
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = load("res://textures/sky/sun.png")
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sun_node.material_override = mat
		
	var moon_node = get_node_or_null("CelestialBodies/Moon")
	if moon_node:
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = load("res://textures/sky/moon.png")
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		moon_node.material_override = mat

func _process(delta):
	if not is_loading:
		# Update time
		time += delta * TICKS_PER_SECOND
		if time >= MAX_TIME:
			time -= MAX_TIME
		_update_sun_rotation()

	if is_loading:
		_update_loading_progress()
		var p_pos = spawn_pos
		if has_node("Player"): p_pos = $Player.global_position
		_process_generation_queue(p_pos)
		return

	if has_node("Player"):
		var player_pos = $Player.global_position
		var p_x = floor(player_pos.x / chunk_size)
		var p_z = floor(player_pos.z / chunk_size)
		var current_p_chunk = Vector2i(p_x, p_z)
		
		if current_p_chunk != last_player_chunk:
			last_player_chunk = current_p_chunk
			update_chunks(player_pos)
			_unload_distant_chunks(player_pos) # Only unload when moving
		
		# Process queue once per frame when playing to maintain high FPS
		_process_generation_queue(player_pos)

	# Animated water
	water_timer += delta
	if water_timer >= 0.5:
		water_timer = 0.0
		water_frame = 1 - water_frame
		var tex_path = "res://textures/water" + str(water_frame) + ".png"
		if ResourceLoader.exists(tex_path):
			materials[BlockType.WATER].albedo_texture = load(tex_path)
			materials[BlockType.WATER_FLOW].albedo_texture = load(tex_path)

	# Water Simulation
	water_tick_timer += delta
	if water_tick_timer >= 0.2:
		water_tick_timer = 0.0
		_tick_water()


func _update_loading_progress():
	var p_pos = spawn_pos
	if has_node("Player"): p_pos = $Player.global_position
	
	var p_x = floor(p_pos.x / chunk_size)
	var p_z = floor(p_pos.z / chunk_size)
	
	var loaded_count = 0
	var data_ready_count = 0
	for x in range(p_x - render_distance, p_x + render_distance + 1):
		for z in range(p_z - render_distance, p_z + render_distance + 1):
			var c_pos = Vector2i(x, z)
			if chunk_meshed_status.has(c_pos):
				loaded_count += 1
			if chunk_data_status.get(c_pos) == true:
				data_ready_count += 1
	
	if has_node("LoadingLayer/StatusLabel"):
		if data_ready_count < total_spawn_chunks:
			$LoadingLayer/StatusLabel.text = "Generating Terrain Data: %d / %d" % [data_ready_count, total_spawn_chunks]
		else:
			$LoadingLayer/StatusLabel.text = "Building World Meshes: %d / %d" % [loaded_count, total_spawn_chunks]

	var progress = (float(loaded_count) / total_spawn_chunks) * 100
	if has_node("LoadingLayer/ProgressBar"):
		$LoadingLayer/ProgressBar.value = progress
	
	# Finish loading as soon as a minimal area is ready (user requested 2 chunks)
	# We'll check if at least 2 chunks in the immediate vicinity are meshed.
	if loaded_count >= 2 or loaded_count >= total_spawn_chunks:
		_finish_loading()

func _finish_loading():
	is_loading = false
	if has_node("LoadingLayer"):
		$LoadingLayer.visible = false
	
	if has_node("Player"):
		var p = $Player
		# Find highest block at current position if player is at default spawn
		if p.global_position == spawn_pos:
			var hy = get_highest_block_y(int(spawn_pos.x), int(spawn_pos.z))
			p.global_position.y = hy + 2.0
			
		p.set_physics_process(true)
		p.set_process(true)
		p.visible = true
		if p.has_node("HUD"):
			p.get_node("HUD").visible = true
		
	print("World loaded!")

func update_chunks(player_pos):
	var p_x = floor(player_pos.x / chunk_size)
	var p_z = floor(player_pos.z / chunk_size)
	var p_c_pos = Vector2(p_x, p_z)
	
	# Pass 1: Queue Data Generation (radius + 2 to ensure neighbors for meshing are always available)
	var data_radius = render_distance + 2
	var added_data = false
	for x in range(p_x - data_radius, p_x + data_radius + 1):
		for z in range(p_z - data_radius, p_z + data_radius + 1):
			var c_pos = Vector2i(x, z)
			if not chunk_data_status.has(c_pos) and not chunks_data_to_generate_set.has(c_pos):
				chunks_data_to_generate.append(c_pos)
				chunks_data_to_generate_set[c_pos] = true
				added_data = true
	
	if added_data:
		chunks_data_to_generate.sort_custom(func(a, b):
			return a.distance_squared_to(p_c_pos) < b.distance_squared_to(p_c_pos)
		)
	
	# Pass 2: Queue Mesh Generation
	var added_mesh = false
	for x in range(p_x - render_distance, p_x + render_distance + 1):
		for z in range(p_z - render_distance, p_z + render_distance + 1):
			var c_pos = Vector2i(x, z)
			if chunk_meshed_status.has(c_pos) or chunks_to_generate_set.has(c_pos) or active_mesh_tasks.has(c_pos):
				continue
			
			chunks_to_generate.append(c_pos)
			chunks_to_generate_set[c_pos] = true
			added_mesh = true
			
	if added_mesh:
		chunks_to_generate.sort_custom(func(a, b):
			return a.distance_squared_to(p_c_pos) < b.distance_squared_to(p_c_pos)
		)

func _process_generation_queue(_player_pos):
	var self_id = get_instance_id()
	
	var current_gen_speed = generation_speed
	var current_data_gen_limit = data_gen_limit
	
	if is_loading:
		current_gen_speed = 16 # Faster meshing during load
		current_data_gen_limit = 24
	else:
		current_gen_speed = 1
		current_data_gen_limit = 2

	# 1. Process Data Generation
	if not chunks_data_to_generate.is_empty() and active_data_tasks < current_data_gen_limit:
		var to_start = min(chunks_data_to_generate.size(), current_data_gen_limit - active_data_tasks)
		for _i in range(to_start):
			var c_pos = chunks_data_to_generate.pop_front()
			chunks_data_to_generate_set.erase(c_pos)
			active_data_tasks += 1
			WorkerThreadPool.add_task(func(): 
				var world = instance_from_id(self_id)
				if world:
					world.generate_chunk_data(c_pos.x, c_pos.y)
					world.call_deferred("_on_data_task_finished")
			)

	# 2. Process Mesh Generation
	if not chunks_to_generate.is_empty():
		var processed = 0
		var remaining = []
		
		# Throttle in-game generation to avoid lag
		if not is_loading:
			mesh_throttle_timer += get_process_delta_time()
			if mesh_throttle_timer < 0.1: # Only try to mesh 10 chunks per second max
				return
			mesh_throttle_timer = 0.0

		var effective_gen_speed = current_gen_speed if is_loading else 1
		
		# During loading, we process in bulk. In game, we check a few per frame.
		var check_limit = 100 if is_loading else 10
		var checked = 0
		
		while not chunks_to_generate.is_empty() and processed < effective_gen_speed and checked < check_limit:
			var c_pos = chunks_to_generate.pop_front()
			checked += 1
			
			if chunk_meshed_status.has(c_pos):
				chunks_to_generate_set.erase(c_pos)
				continue

			if chunk_data_status.get(c_pos) == true:
				# Neighbor check: only mesh if 1-ring is ready
				var neighbors_ready = true
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						if not chunk_data_status.has(c_pos + Vector2i(dx, dz)):
							neighbors_ready = false
							break
					if not neighbors_ready: break
				
				if neighbors_ready:
					chunks_to_generate_set.erase(c_pos)
					create_chunk(c_pos.x, c_pos.y)
					processed += 1
				else:
					remaining.append(c_pos)
			else:
				remaining.append(c_pos)
		
		# Put remaining back at the front for next frame
		while not remaining.is_empty():
			chunks_to_generate.push_front(remaining.pop_back())


func _on_data_task_finished():
	active_data_tasks -= 1

func _unload_distant_chunks(player_pos):
	var p_x = int(player_pos.x / chunk_size)
	var p_z = int(player_pos.z / chunk_size)
	var unload_dist = render_distance + 2
	
	var to_remove = []
	for c_pos in chunks:
		if abs(c_pos.x - p_x) > unload_dist or abs(c_pos.y - p_z) > unload_dist:
			to_remove.append(c_pos)
			
	for c_pos in to_remove:
		if chunks[c_pos]:
			chunks[c_pos].queue_free()
		chunks.erase(c_pos)
		chunk_meshed_status.erase(c_pos)

func generate_chunk_data(cx, cz):
	var c_pos = Vector2i(cx, cz)
	var chunk_blocks = {}
	
	for x in range(chunk_size):
		for z in range(chunk_size):
			var world_x = cx * chunk_size + x
			var world_z = cz * chunk_size + z
			var noise_val = (noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
			noise_val = pow(noise_val, 3.5)
			var height = int(noise_val * chunk_height * 1.5) + 6
			
			var biome_val = biome_noise.get_noise_2d(world_x, world_z)
			var is_desert = biome_val < -0.1
			var is_water_area = height < SEA_LEVEL
			
			var tree_rng = RandomNumberGenerator.new()
			tree_rng.seed = hash(world_seed) + hash(Vector2i(world_x, world_z))
			
			for y in range(max(height, SEA_LEVEL) + 1):
				var type = -1
				if y <= height:
					type = BlockType.STONE
					if y == 0: type = BlockType.BEDROCK
					elif y == height:
						if is_desert: type = BlockType.SAND
						else: type = BlockType.GRASS if height > SEA_LEVEL + 1 else BlockType.SAND
					elif y > height - 3:
						if is_desert: type = BlockType.SAND
						else: type = BlockType.DIRT
				elif y <= SEA_LEVEL:
					type = BlockType.WATER
				
				if type != -1:
					chunk_blocks[Vector3i(world_x, y, world_z)] = type
			
			# Simple Tree Generation (Within Chunk Data)
			if not is_desert and not is_water_area and height > SEA_LEVEL + 3 and tree_rng.randf() < 0.02:
				var tree_height = tree_rng.randi_range(4, 6)
				for ty in range(tree_height):
					chunk_blocks[Vector3i(world_x, height + 1 + ty, world_z)] = BlockType.WOOD
				
				# Leaves (Simplified: only within this chunk generation, 
				# for real trees we'd need to handle neighboring chunks too)
				for lx in range(-2, 3):
					for lz in range(-2, 3):
						for ly in range(2):
							var l_pos = Vector3i(world_x + lx, height + tree_height + ly, world_z + lz)
							# Check if it's in OUR chunk for simplicity in this thread
							var l_cx = floor(float(l_pos.x) / chunk_size)
							var l_cz = floor(float(l_pos.z) / chunk_size)
							if l_cx == cx and l_cz == cz:
								if not chunk_blocks.has(l_pos):
									chunk_blocks[l_pos] = BlockType.LEAVES
	
	world_mutex.lock()
	world_data[c_pos] = chunk_blocks
	chunk_data_status[c_pos] = true
	world_mutex.unlock()

static func is_transparent(type):
	return type == -1 or type == BlockType.WATER or type == BlockType.WATER_FLOW or type == BlockType.LEAVES

static func is_water(type):
	return type == BlockType.WATER or type == BlockType.WATER_FLOW

func create_chunk(cx, cz):
	var c_pos = Vector2i(cx, cz)
	
	# If already being meshed, mark it for a follow-up rebuild
	if active_mesh_tasks.has(c_pos):
		chunks_needing_rebuild[c_pos] = true
		return
	
	# Capture values needed by the thread to avoid accessing 'self' as much as possible
	var current_chunk_size = chunk_size
	var self_id = get_instance_id()
	if self_id == 0: return # Should not happen for a live node
	
	active_mesh_tasks[c_pos] = WorkerThreadPool.add_task(func(): 
		var world = instance_from_id(self_id)
		if is_instance_valid(world):
			world._threaded_mesh_gen(cx, cz, current_chunk_size)
	)

func _threaded_mesh_gen(cx, cz, c_size):
	var c_pos = Vector2i(cx, cz)
	var self_id = get_instance_id()
	var mesh_results = {} # type -> { "arrays": [], "collision_shape": ConcavePolygonShape3D }
	
	# Important: Snapshot the data inside the mutex to avoid concurrent modification issues
	var relevant_chunks = {}
	world_mutex.lock()
	for x in range(-1, 2):
		for z in range(-1, 2):
			var nc_pos = c_pos + Vector2i(x, z)
			if world_data.has(nc_pos):
				# Explicitly duplicate the inner dictionary while locked
				var original = world_data[nc_pos]
				var copy = {}
				for key in original:
					copy[key] = original[key]
				relevant_chunks[nc_pos] = copy
	world_mutex.unlock()
	
	var current_chunk_data = relevant_chunks.get(c_pos, {})
	if current_chunk_data.is_empty():
		call_deferred("_apply_chunk_mesh", cx, cz, [])
		return
	
	for pos in current_chunk_data:
		var type = current_chunk_data[pos]
		var type_is_water = is_water(type)
		
		# Local coordinates for vertex generation
		var lx = pos.x - cx * c_size
		var lz = pos.z - cz * c_size
		var ly = pos.y
		
		for face in FACES:
			var neighbor_pos = pos + face.dir
			var n_cx = floor(float(neighbor_pos.x) / c_size)
			var n_cz = floor(float(neighbor_pos.z) / c_size)
			var n_c_pos = Vector2i(n_cx, n_cz)
			
			var n_chunk = relevant_chunks.get(n_c_pos, {})
			var n_type = n_chunk.get(neighbor_pos, -1)
			
			var draw_face = false
			if type_is_water:
				if not is_water(n_type) and is_transparent(n_type): draw_face = true
			else:
				if is_transparent(n_type): draw_face = true
			
			if draw_face:
				if not mesh_results.has(type):
					mesh_results[type] = {
						"verts": PackedVector3Array(),
						"uvs": PackedVector2Array(),
						"normals": PackedVector3Array(),
						"indices": PackedInt32Array(),
						"col_verts": PackedVector3Array()
					}
				
				var res = mesh_results[type]
				var v_offset = res.verts.size()
				var offset = Vector3(lx, ly, lz)
				
				for i in range(4):
					res.verts.append(face.verts[i] + offset)
					res.uvs.append(face.uvs[i])
					res.normals.append(face.normal)
				
				res.indices.append(v_offset + 0)
				res.indices.append(v_offset + 1)
				res.indices.append(v_offset + 2)
				res.indices.append(v_offset + 0)
				res.indices.append(v_offset + 2)
				res.indices.append(v_offset + 3)
				
				if type != BlockType.WATER and type != BlockType.WATER_FLOW:
					res.col_verts.append(face.verts[0] + offset)
					res.col_verts.append(face.verts[1] + offset)
					res.col_verts.append(face.verts[2] + offset)
					res.col_verts.append(face.verts[0] + offset)
					res.col_verts.append(face.verts[2] + offset)
					res.col_verts.append(face.verts[3] + offset)

	# Pre-create resources in the thread
	var final_results = []
	for type in mesh_results:
		var res = mesh_results[type]
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = res.verts
		arrays[Mesh.ARRAY_TEX_UV] = res.uvs
		arrays[Mesh.ARRAY_NORMAL] = res.normals
		arrays[Mesh.ARRAY_INDEX] = res.indices
		
		var col_shape = null
		if not res.col_verts.is_empty():
			col_shape = ConcavePolygonShape3D.new()
			col_shape.set_faces(res.col_verts)
			
		final_results.append({
			"type": type,
			"arrays": arrays,
			"collision_shape": col_shape
		})
							
	var world = instance_from_id(self_id)
	if world:
		world.call_deferred("_apply_chunk_mesh", cx, cz, final_results)

func _apply_chunk_mesh(cx, cz, final_results):
	var c_pos = Vector2i(cx, cz)
	active_mesh_tasks.erase(c_pos)
	chunk_meshed_status[c_pos] = true
	
	# Replace existing chunk if any
	if chunks.has(c_pos):
		chunks[c_pos].queue_free()
	
	# If no results (empty chunk), just clean up
	if final_results.is_empty():
		chunks.erase(c_pos)
		# Check if it was made dirty while we were "generating" nothing
		if chunks_needing_rebuild.has(c_pos):
			chunks_needing_rebuild.erase(c_pos)
			create_chunk(cx, cz)
		return

	var chunk_node = StaticBody3D.new()
	chunk_node.name = "Chunk_%d_%d" % [cx, cz]
	chunk_node.position = Vector3(cx * chunk_size, 0, cz * chunk_size)
	chunk_node.collision_layer = 1
	add_child(chunk_node)
	chunks[c_pos] = chunk_node
	
	for res in final_results:
		var type = res.get("type", -1)
		if type == -1 or not materials.has(type):
			continue
			
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res.arrays)
		
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = materials[type]
		chunk_node.add_child(mi)
		
		if res.collision_shape:
			var col = CollisionShape3D.new()
			col.shape = res.collision_shape
			chunk_node.add_child(col)
	
	# After applying, check if we need to rebuild because of a block change
	if chunks_needing_rebuild.has(c_pos):
		chunks_needing_rebuild.erase(c_pos)
		create_chunk(cx, cz)

# Helper functions for water simulation (MUST BE CALLED UNDER world_mutex LOCK)
func _get_block_type_locked(pos: Vector3i) -> int:
	var cx = floor(float(pos.x) / chunk_size)
	var cz = floor(float(pos.z) / chunk_size)
	var chunk = world_data.get(Vector2i(cx, cz))
	if chunk:
		return chunk.get(pos, -1)
	return -1

func _set_block_type_locked(pos: Vector3i, type: int):
	var cx = floor(float(pos.x) / chunk_size)
	var cz = floor(float(pos.z) / chunk_size)
	var c_pos = Vector2i(cx, cz)
	if type == -1:
		if world_data.has(c_pos):
			world_data[c_pos].erase(pos)
	else:
		if not world_data.has(c_pos):
			world_data[c_pos] = {}
		world_data[c_pos][pos] = type

func _get_water_level_locked(pos: Vector3i) -> int:
	var cx = floor(float(pos.x) / chunk_size)
	var cz = floor(float(pos.z) / chunk_size)
	var chunk = water_levels.get(Vector2i(cx, cz))
	if chunk:
		return chunk.get(pos, 0)
	return 0

func _set_water_level_locked(pos: Vector3i, level: int):
	var cx = floor(float(pos.x) / chunk_size)
	var cz = floor(float(pos.z) / chunk_size)
	var c_pos = Vector2i(cx, cz)
	if level <= 0:
		if water_levels.has(c_pos):
			water_levels[c_pos].erase(pos)
	else:
		if not water_levels.has(c_pos):
			water_levels[c_pos] = {}
		water_levels[c_pos][pos] = level

func _tick_water():
	if water_update_queue.is_empty():
		return
	
	var chunks_to_rebuild = {}
	var current_queue = water_update_queue.keys()
	water_update_queue.clear()
	
	var changed = false
	
	world_mutex.lock()
	for pos in current_queue:
		var current_type = _get_block_type_locked(pos)
		
		# Skip non-air/non-water blocks immediately
		if current_type != -1 and current_type != BlockType.WATER and current_type != BlockType.WATER_FLOW:
			continue
			
		var old_level = _get_water_level_locked(pos) if current_type == BlockType.WATER_FLOW else (8 if current_type == BlockType.WATER else 0)
		
		# 1. Infinite Source logic
		if current_type == -1 or current_type == BlockType.WATER_FLOW:
			var source_neighbors = 0
			for dir in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
				if _get_block_type_locked(pos + dir) == BlockType.WATER:
					source_neighbors += 1
			if source_neighbors >= 2:
				var below = pos + Vector3i.DOWN
				var type_below = _get_block_type_locked(below)
				if type_below != -1 and type_below != BlockType.WATER and type_below != BlockType.WATER_FLOW:
					_set_block_type_locked(pos, BlockType.WATER)
					_set_water_level_locked(pos, 8)
					_mark_pos_dirty(pos, chunks_to_rebuild)
					changed = true
					# Trigger neighbors
					for face in FACES: _schedule_water_update(pos + face.dir)
					continue

		# 2. Flow Calculation
		if current_type == BlockType.WATER: continue # Source blocks don't "flow" into themselves
		
		var target_level = 0
		var above = pos + Vector3i.UP
		var type_above = _get_block_type_locked(above)
		if type_above == BlockType.WATER or type_above == BlockType.WATER_FLOW:
			target_level = 8 # Falling water is max level
		else:
			for dir in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
				var n_pos = pos + dir
				var n_type = _get_block_type_locked(n_pos)
				if n_type == BlockType.WATER or n_type == BlockType.WATER_FLOW:
					var n_level = 8 if n_type == BlockType.WATER else _get_water_level_locked(n_pos)
					var n_below = n_pos + Vector3i.DOWN
					var n_below_type = _get_block_type_locked(n_below)
					# Only flow sideways if there's a solid block below or if it can't flow down
					var n_is_falling = n_below.y >= 0 and (n_below_type == -1 or n_below_type == BlockType.WATER or n_below_type == BlockType.WATER_FLOW)
					if not n_is_falling:
						target_level = max(target_level, n_level - 1)

		if target_level > 0:
			if current_type != BlockType.WATER_FLOW or old_level != target_level:
				_set_block_type_locked(pos, BlockType.WATER_FLOW)
				_set_water_level_locked(pos, target_level)
				_mark_pos_dirty(pos, chunks_to_rebuild)
				changed = true
				for face in FACES: _schedule_water_update(pos + face.dir)
		elif current_type == BlockType.WATER_FLOW:
			_set_block_type_locked(pos, -1)
			_set_water_level_locked(pos, 0)
			_mark_pos_dirty(pos, chunks_to_rebuild)
			changed = true
			for face in FACES: _schedule_water_update(pos + face.dir)
	world_mutex.unlock()

	if changed:
		for c_pos in chunks_to_rebuild:
			_rebuild_chunk(c_pos)


func _mark_pos_dirty(pos, dict):
	var cx = floor(float(pos.x) / chunk_size)
	var cz = floor(float(pos.z) / chunk_size)
	dict[Vector2i(cx, cz)] = true
	var lx = pos.x - cx * chunk_size
	var lz = pos.z - cz * chunk_size
	if lx == 0: dict[Vector2i(cx - 1, cz)] = true
	if lx == chunk_size - 1: dict[Vector2i(cx + 1, cz)] = true
	if lz == 0: dict[Vector2i(cx, cz - 1)] = true
	if lz == chunk_size - 1: dict[Vector2i(cx, cz + 1)] = true
