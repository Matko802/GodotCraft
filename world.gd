extends Node3D

@export var chunk_size = 16
@export var chunk_height = 64
@export var world_seed = "GodotCraft"
@export var render_distance = 4

enum BlockType { STONE, DIRT, GRASS, SAND, BEDROCK, WOOD, LEAVES, WATER, WATER_FLOW, TORCH, COARSE_DIRT, WOOD_X, WOOD_Z }

const BLOCK_TEXTURES = {
	0: "res://textures/stone.png",
	1: "res://textures/dirt.png",
	2: "res://textures/grass_side.png",
	3: "res://textures/Sand.png",
	4: "res://textures/bedrock.png",
	5: "res://textures/oak_wood_side.png",
	6: "res://textures/leaves.png",
	9: "res://models/block/torch/torch_0.png",
	10: "res://textures/dirt.png",
	11: "res://textures/oak_wood_side.png",
	12: "res://textures/oak_wood_side.png"
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
	],
	"wood_hit": [
		"res://textures/Sounds/block_hit/stone1.ogg"
	]
}

const TYPE_TO_SOUND = {
	BlockType.STONE: "stone",
	BlockType.DIRT: "gravel",
	BlockType.GRASS: "grass",
	BlockType.SAND: "sand",
	BlockType.WOOD: "wood",
	BlockType.WOOD_X: "wood",
	BlockType.WOOD_Z: "wood",
	BlockType.LEAVES: "grass",
	BlockType.TORCH: "wood",
	BlockType.COARSE_DIRT: "gravel"
}

const DROPPED_ITEM_SCENE = preload("res://dropped_item.tscn")

var torch_mesh: Mesh = null
var torch_material: Material = null

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

enum LoadingStage { ASSETS, CHUNKS }
var _current_stage = LoadingStage.ASSETS
var _assets_to_load = []
var _total_assets = 0
var _loaded_assets = 0

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

# Time system (0 to 24000, 24000 ticks = 24 hours)
# 0 = 06:00 (Sunrise), 6000 = 12:00 (Noon), 12000 = 18:00 (Sunset), 18000 = 00:00 (Midnight)
var time: float = 6000.0 # Start at Noon
var days_passed: int = 0
const TICKS_PER_SECOND = 20.0
const MAX_TIME = 24000.0

@onready var sun = $DefaultLight
@onready var world_env = $WorldEnvironment
@onready var celestial_bodies = $Sky

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
	
	# Reduced to 4 particles for better performance
	for i in range(4):
		var debris = MeshInstance3D.new()
		var quad = QuadMesh.new()
		quad.size = Vector2(0.15, 0.15)
		debris.mesh = quad
		
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.albedo_texture = texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		
		mat.uv1_offset = Vector3(randf() * 0.75, randf() * 0.75, 0)
		mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
		
		debris.material_override = mat
		debris.set_script(DEBRIS_SCRIPT)
		add_child(debris)
		
		debris.global_position = pos + Vector3(0.5, 0.5, 0.5) + Vector3(randf()-0.5, randf()-0.5, randf()-0.5) * 0.3
		debris.velocity = Vector3(randf() - 0.5, randf() * 1.5 + 1.0, randf() - 0.5) * 2.5

func play_break_sound(pos: Vector3, type: int):
	var category = TYPE_TO_SOUND.get(type, "stone")
	var sound_paths = BLOCK_SOUNDS.get(category, BLOCK_SOUNDS["stone"])
	var sound_path = sound_paths[randi() % sound_paths.size()]
	
	var audio = AudioStreamPlayer3D.new()
	audio.stream = load(sound_path)
	audio.bus = "Blocks"
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
	audio.bus = "Blocks"
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
	# High priority rebuild for player actions
	create_chunk(c_pos.x, c_pos.y, true)

func _enter_tree():
	_setup_materials()

func _ready():
	add_to_group("world")
	get_tree().set_auto_accept_quit(false)
	
	_gather_assets()
	
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
	
	if state:
		state.settings_changed.connect(_apply_settings)
		_apply_settings()

	# Calculate total spawn chunks for progress bar, but we'll finish earlier
	total_spawn_chunks = (render_distance * 2 + 1) * (render_distance * 2 + 1)
	
	# Start asset loading
	if _assets_to_load.is_empty():
		_current_stage = LoadingStage.CHUNKS
		update_chunks(p_pos)
	else:
		for path in _assets_to_load:
			ResourceLoader.load_threaded_request(path)

func _gather_assets():
	var paths = []
	# Textures
	for type in BLOCK_TEXTURES:
		paths.append(BLOCK_TEXTURES[type])
	
	paths.append("res://textures/grass_top.png")
	paths.append("res://textures/dirt.png")
	paths.append("res://textures/oak_wood_top.png")
	paths.append("res://textures/water0.png")
	paths.append("res://textures/water1.png")
	paths.append("res://textures/sky/sun.png")
	paths.append("res://textures/sky/moon.png")
	
	# Sounds
	for cat in BLOCK_SOUNDS:
		for s in BLOCK_SOUNDS[cat]:
			paths.append(s)
	
	# Models
	paths.append("res://models/block/torch/torch.gltf")
	
	# Filter duplicates and non-existent
	for p in paths:
		if not p in _assets_to_load and ResourceLoader.exists(p):
			_assets_to_load.append(p)
	
	_total_assets = _assets_to_load.size()

func _apply_settings():
	var state = get_node_or_null("/root/GameState")
	if state and sun:
		if state.shadow_quality == 0:
			sun.shadow_enabled = false
		else:
			sun.shadow_enabled = true
			match state.shadow_quality:
				1: # Low
					sun.shadow_blur = 0.5
					sun.directional_shadow_max_distance = 256.0
				2: # Medium
					sun.shadow_blur = 1.0
					sun.directional_shadow_max_distance = 128.0
				3: # High
					sun.shadow_blur = 1.5
					sun.directional_shadow_max_distance = 96.0
				4: # Ultra
					sun.shadow_blur = 2.0
					sun.directional_shadow_max_distance = 64.0
		
		# Common shadow settings
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.shadow_bias = 0.02
		sun.shadow_normal_bias = 1.0
	
	_update_torch_lights()

func _update_torch_lights():
	var state = get_node_or_null("/root/GameState")
	if not state: return
	
	for light in get_tree().get_nodes_in_group("torch_lights"):
		if light is OmniLight3D:
			# Skip the player's held torch light
			if light.name == "HandLight": continue
			_apply_shadow_settings_to_light(light, state.shadow_quality)

func _apply_shadow_settings_to_light(light: OmniLight3D, quality: int):
	light.shadow_enabled = quality > 0
	if quality > 0:
		var blur = 0.0
		match quality:
			1: # Low - Very Sharp/Pixelated
				blur = 0.0
			2: # Medium - Slightly soft
				blur = 1.0
			3: # High - Soft
				blur = 2.5
			4: # Ultra - Very soft
				blur = 4.5
		
		light.shadow_blur = blur
		light.shadow_opacity = 1.0 # Keep shadow darkness/brightness constant
		light.shadow_bias = 0.05
		light.shadow_normal_bias = 1.0

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
		var p = $Player
		p.global_position = p_pos
		p.rotation = data.get("player_rot", Vector3.ZERO)
		
		if data.has("selected_slot"):
			p.selected_slot = data["selected_slot"]
			if p.inventory_ui:
				p.inventory_ui.set_selected(p.selected_slot)
			p._update_held_item_mesh()
		
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
	var p_pos = player.global_position if player else Vector3.ZERO
	
	if celestial_bodies.has_method("update_time"):
		celestial_bodies.update_time(time, p_pos)

	# Minecraft Time mapping:
	# 0 = Sunrise/Early Morning (Sun at Horizon)
	# 6000 = Noon (Sun at Zenith)
	# 12000 = Sunset (Sun at Horizon)
	# 18000 = Midnight (Moon at Zenith)
	
	var angle = (time / MAX_TIME) * 360.0
	
	# Light rotation matches sun/moon
	# During day (0-12000), sun is up. During night (12000-24000), moon is up.
	var is_day = time < 12000.0
	
	# When sun is at 90 deg (Noon), light should point down (-90)
	sun.rotation_degrees.x = -angle
	sun.rotation_degrees.y = 180.0

	# Calculate day/night intensity (0.0 to 1.0)
	# Day peaks at 6000, Night peaks at 18000
	var day_pos = clamp(sin(deg_to_rad(angle)), 0.0, 1.0)
	var night_pos = clamp(sin(deg_to_rad(angle + 180.0)), 0.0, 1.0)
	
	# Smooth transitions for colors
	var transition = clamp(sin(deg_to_rad(angle)) * 2.0, -1.0, 1.0) * 0.5 + 0.5
	
	# Light colors
	var day_color = Color(1.0, 0.95, 0.85)
	var sunset_color = Color(1.0, 0.5, 0.2)
	var night_color = Color(0.15, 0.15, 0.3)
	
	if is_day:
		sun.light_energy = day_pos * 0.4 + 0.1
		sun.light_color = sunset_color.lerp(day_color, day_pos)
	else:
		sun.light_energy = night_pos * 0.2 + 0.3
		sun.light_color = night_color
	
	if world_env:
		var env = world_env.environment
		
		# Atmospheric Colors
		var sky_top_day = Color(0.4, 0.6, 1.0)
		var sky_top_night = Color(0.05, 0.05, 0.1)
		var sky_hor_day = Color(0.7, 0.8, 1.0)
		var sky_hor_night = Color(0.1, 0.1, 0.2)
		
		# Horizon color becomes orange/pink during sunrise/sunset
		var sunset_hor = Color(1.0, 0.4, 0.3)
		var hor_weight = clamp(1.0 - abs(day_pos), 0.0, 1.0)
		var current_hor = sky_hor_night.lerp(sky_hor_day, transition)
		
		if is_day:
			current_hor = current_hor.lerp(sunset_hor, pow(hor_weight, 3.0))
		
		if env.sky and env.sky.sky_material:
			env.sky.sky_material.sky_top_color = sky_top_night.lerp(sky_top_day, transition)
			env.sky.sky_material.sky_horizon_color = current_hor
			env.sky.sky_material.ground_bottom_color = Color(0.1, 0.1, 0.1)
			env.sky.sky_material.ground_horizon_color = current_hor
		
		# Ambient Lighting - Tuned for night visibility and softer days
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = transition * 0.15 + 0.05 # High base energy for night
		env.ambient_light_color = Color(0.7, 0.7, 0.85).lerp(Color(1, 1, 1), transition)
		
		# Fog and background energy
		env.background_energy_multiplier = transition * 0.4 + 0.6
		env.tonemap_exposure = 1.0 # Ensure exposure isn't too low

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not is_loading:
			# If we are in a world, try to save
			var state = get_node_or_null("/root/GameState")
			if state and state.current_save_name != "":
				# Save without screenshot for faster closing
				await save_game(true)
		get_tree().quit()

func save_game(data_only: bool = false):
	var state = get_node_or_null("/root/GameState")
	if state and state.current_save_name != "":
		var img = null
		if not data_only:
			# Hide UI for screenshot
			var hud = get_node_or_null("Player/HUD")
			var pause_layer = get_node_or_null("Player/PauseLayer")
			var player = get_tree().get_first_node_in_group("player")
			var view_model = null
			if player:
				view_model = player.get_node_or_null("SpringArm3D/Camera3D/ViewModelArm")
				
			if hud: hud.visible = false
			if pause_layer: pause_layer.visible = false
			if view_model: view_model.visible = false
			
			# Wait for render frame to ensure UI is hidden in capture
			await RenderingServer.frame_post_draw
			
			img = get_viewport().get_texture().get_image()
			# Resize to small thumbnail to speed up save_png
			img.resize(320, 180, Image.INTERPOLATE_LANCZOS)
			
			# Restore UI immediately so user doesn't see flicker
			if hud: hud.visible = true
			if pause_layer: pause_layer.visible = true
			if view_model: view_model.visible = player.current_camera_mode == player.CameraMode.FIRST_PERSON

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
			"selected_slot": $Player.selected_slot if has_node("Player") else 0,
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
			if img:
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
	var rotated_shader = load("res://voxel_rotated.gdshader")
	
	var wood_mat = ShaderMaterial.new()
	wood_mat.shader = rotated_shader
	if ResourceLoader.exists("res://textures/oak_wood_top.png"):
		wood_mat.set_shader_parameter("top_texture", load("res://textures/oak_wood_top.png"))
		wood_mat.set_shader_parameter("bottom_texture", load("res://textures/oak_wood_top.png"))
	if ResourceLoader.exists("res://textures/oak_wood_side.png"):
		wood_mat.set_shader_parameter("side_texture", load("res://textures/oak_wood_side.png"))
	wood_mat.set_shader_parameter("up_vector", Vector3(0, 1, 0))
	materials[BlockType.WOOD] = wood_mat

	var wood_x_mat = wood_mat.duplicate()
	wood_x_mat.set_shader_parameter("up_vector", Vector3(1, 0, 0))
	materials[BlockType.WOOD_X] = wood_x_mat

	var wood_z_mat = wood_mat.duplicate()
	wood_z_mat.set_shader_parameter("up_vector", Vector3(0, 0, 1))
	materials[BlockType.WOOD_Z] = wood_z_mat

	# Torch Mesh Setup
	var torch_scene = load("res://models/block/torch/torch.gltf").instantiate()
	var torch_mesh_instances = torch_scene.find_children("*", "MeshInstance3D", true)
	if not torch_mesh_instances.is_empty():
		var torch_model_mesh_instance = torch_mesh_instances[0]
		torch_mesh = torch_model_mesh_instance.mesh
		torch_material = torch_model_mesh_instance.mesh.surface_get_material(0)
		if not torch_material:
			torch_material = torch_model_mesh_instance.material_override
		
		# Make torch always bright
		if torch_material:
			torch_material = torch_material.duplicate()
			torch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torch_scene.free()

func _process(delta):
	if is_loading:
		var p_pos = spawn_pos
		if has_node("Player"): p_pos = $Player.global_position

		if _current_stage == LoadingStage.ASSETS:
			var all_done = true
			var loaded_count = 0
			for path in _assets_to_load:
				var status = ResourceLoader.load_threaded_get_status(path)
				if status == ResourceLoader.THREAD_LOAD_LOADED:
					loaded_count += 1
				else:
					all_done = false
			
			_loaded_assets = loaded_count
			
			if all_done:
				_current_stage = LoadingStage.CHUNKS
				update_chunks(p_pos)
		
		_update_loading_progress()
		_process_generation_queue(p_pos)
		return

	# Update time
	time += delta * TICKS_PER_SECOND
	if time >= MAX_TIME:
		time -= MAX_TIME
		days_passed += 1
	_update_sun_rotation()

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
	
	if _current_stage == LoadingStage.ASSETS:
		if has_node("LoadingLayer/StatusLabel"):
			$LoadingLayer/StatusLabel.text = "Loading Assets: %d / %d" % [_loaded_assets, _total_assets]
		if has_node("LoadingLayer/ProgressBar"):
			$LoadingLayer/ProgressBar.value = (float(_loaded_assets) / _total_assets) * 50.0 # First 50% for assets
		return

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

	var progress = 50.0 + (float(loaded_count) / total_spawn_chunks) * 50.0
	if has_node("LoadingLayer/ProgressBar"):
		$LoadingLayer/ProgressBar.value = progress
	
	# Finish loading as soon as a minimal area is ready
	if loaded_count >= 1 or loaded_count >= total_spawn_chunks:
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
		current_gen_speed = 16 
		current_data_gen_limit = 32 # Increased for faster loading
	else:
		current_gen_speed = 2 # Slightly faster in-game
		current_data_gen_limit = 4

	# 1. Process Data Generation
	if not chunks_data_to_generate.is_empty() and active_data_tasks < current_data_gen_limit:
		var to_start = min(chunks_data_to_generate.size(), current_data_gen_limit - active_data_tasks)
		for _i in range(to_start):
			var c_pos = chunks_data_to_generate.pop_front()
			chunks_data_to_generate_set.erase(c_pos)
			active_data_tasks += 1
			WorkerThreadPool.add_task(func(): 
				var world = instance_from_id(self_id)
				if is_instance_valid(world):
					world.generate_chunk_data(c_pos.x, c_pos.y)
					world.call_deferred("_on_data_task_finished")
			, false) # Low priority for background data gen

	# 2. Process Mesh Generation
	if not chunks_to_generate.is_empty():
		var processed = 0
		var check_limit = 200 if is_loading else 20
		var checked = 0
		
		# Use a local copy of chunks_to_generate to avoid modifying it during iteration if needed, 
		# but here we use a temporary list to hold chunks that aren't ready yet.
		var not_ready = []
		
		while not chunks_to_generate.is_empty() and processed < current_gen_speed and checked < check_limit:
			var c_pos = chunks_to_generate.pop_front()
			checked += 1
			
			if chunk_meshed_status.has(c_pos):
				chunks_to_generate_set.erase(c_pos)
				continue

			# Optimized neighbor check: check status map only
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
				not_ready.append(c_pos)
		
		# Re-add non-ready chunks to the front for next frame
		for i in range(not_ready.size() - 1, -1, -1):
			chunks_to_generate.push_front(not_ready[i])


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
		var node = chunks[c_pos]
		if is_instance_valid(node):
			node.queue_free()
		chunks.erase(c_pos)
		chunk_meshed_status.erase(c_pos)

func generate_chunk_data(cx, cz):
	var c_pos = Vector2i(cx, cz)
	var chunk_blocks = {}
	var world_seed_hash = hash(world_seed)
	
	var tree_rng = RandomNumberGenerator.new()
	
	for x in range(chunk_size):
		for z in range(chunk_size):
			var world_x = cx * chunk_size + x
			var world_z = cz * chunk_size + z
			
			var noise_val = (noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
			var height = int(pow(noise_val, 3.5) * chunk_height * 1.5) + 6
			
			var is_desert = biome_noise.get_noise_2d(world_x, world_z) < -0.1
			var is_water_area = height < SEA_LEVEL
			
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
			
			# Simple Tree Generation
			if not is_desert and not is_water_area and height > SEA_LEVEL + 3:
				tree_rng.seed = world_seed_hash + hash(Vector2i(world_x, world_z))
				if tree_rng.randf() < 0.007:
					var tree_height = tree_rng.randi_range(4, 6)
					for ty in range(tree_height):
						chunk_blocks[Vector3i(world_x, height + 1 + ty, world_z)] = BlockType.WOOD
					
					# Improved leaf pattern
					for ly in range(-2, 3): # 5 layers of leaves (up to 2 above trunk)
						var radius = 2 if ly < 0 else 1
						if ly == 2: radius = 0 # Pointy top
						
						for lx in range(-radius, radius + 1):
							for lz in range(-radius, radius + 1):
								# Avoid corners for a rounder look
								if radius == 2 and abs(lx) == 2 and abs(lz) == 2:
									continue
								if radius == 1 and ly == 1 and abs(lx) == 1 and abs(lz) == 1:
									if tree_rng.randf() < 0.5: continue
								
								var l_pos = Vector3i(world_x + lx, height + tree_height + ly, world_z + lz)
								if floor(float(l_pos.x) / chunk_size) == cx and floor(float(l_pos.z) / chunk_size) == cz:
									if not chunk_blocks.has(l_pos):
										chunk_blocks[l_pos] = BlockType.LEAVES
	
	world_mutex.lock()
	world_data[c_pos] = chunk_blocks
	chunk_data_status[c_pos] = true
	world_mutex.unlock()

static func is_transparent(type):
	return type == -1 or type == BlockType.WATER or type == BlockType.WATER_FLOW or type == BlockType.LEAVES or type == BlockType.TORCH

static func is_water(type):
	return type == BlockType.WATER or type == BlockType.WATER_FLOW

func create_chunk(cx, cz, high_priority = false):
	var c_pos = Vector2i(cx, cz)
	
	# If this is a manual update, remove it from the background queue to avoid redundant work
	if high_priority and chunks_to_generate_set.has(c_pos):
		chunks_to_generate_set.erase(c_pos)
		# We don't remove from the array because it's slow, 
		# the process_queue will just skip it because chunk_meshed_status will be set.
	
	# If already being meshed, mark it for a follow-up rebuild
	if active_mesh_tasks.has(c_pos):
		chunks_needing_rebuild[c_pos] = true
		return
	
	# Capture values needed by the thread
	var current_chunk_size = chunk_size
	var self_id = get_instance_id()
	if self_id == 0: return
	
	active_mesh_tasks[c_pos] = WorkerThreadPool.add_task(func(): 
		var world = instance_from_id(self_id)
		if is_instance_valid(world):
			world._threaded_mesh_gen(cx, cz, current_chunk_size)
	, high_priority)

func _threaded_mesh_gen(cx, cz, c_size):
	var c_pos = Vector2i(cx, cz)
	var self_id = get_instance_id()
	var world = instance_from_id(self_id)
	var mesh_results = {} # type -> { "verts": [], ... }
	
	# Important: Snapshot the data inside the mutex
	var relevant_chunks = {}
	world_mutex.lock()
	for x in range(-1, 2):
		for z in range(-1, 2):
			var nc_pos = c_pos + Vector2i(x, z)
			if world_data.has(nc_pos):
				relevant_chunks[nc_pos] = world_data[nc_pos].duplicate()
	world_mutex.unlock()
	
	var current_chunk_data = relevant_chunks.get(c_pos, {})
	if current_chunk_data.is_empty():
		if is_instance_valid(world):
			world.call_deferred("_apply_chunk_mesh", cx, cz, [], [])
		return
	
	var decoration_positions = [] # [{type: int, pos: Vector3}]

	for pos in current_chunk_data:
		var type = current_chunk_data[pos]
		
		# Skip decoration blocks from solid mesh
		if type == BlockType.TORCH:
			decoration_positions.append({"type": type, "pos": Vector3(pos)})
			continue

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

	# Pre-create arrays and collision shapes in the thread
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
			"col_shape": col_shape
		})
							
	if is_instance_valid(world):
		world.call_deferred("_apply_chunk_mesh", cx, cz, final_results, decoration_positions)

func _apply_chunk_mesh(cx, cz, final_results, decoration_positions = []):
	var c_pos = Vector2i(cx, cz)
	active_mesh_tasks.erase(c_pos)
	chunk_meshed_status[c_pos] = true
	
	# Replace existing chunk if any
	if chunks.has(c_pos):
		chunks[c_pos].queue_free()
	
	# If no results and no decorations, just clean up
	if final_results.is_empty() and decoration_positions.is_empty():
		chunks.erase(c_pos)
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
		
		var col_shape = res.get("col_shape")
		if col_shape:
			var col = CollisionShape3D.new()
			col.shape = col_shape
			chunk_node.add_child(col)
	
	# Handle Torches using MultiMesh for optimization
	var torch_count = 0
	for deco in decoration_positions:
		if deco.type == BlockType.TORCH:
			torch_count += 1
			
	if torch_count > 0 and torch_mesh:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = torch_mesh
		mm.instance_count = torch_count
		
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = torch_material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.layers = 8 # Layer 4
		chunk_node.add_child(mmi)
		
		# Create a separate body for torch collisions on Layer 3 (mask 4)
		# This allows players to walk through torches (player mask is 1)
		# while still allowing raycasts (mask 5) to hit them.
		var deco_node = StaticBody3D.new()
		deco_node.collision_layer = 4
		deco_node.collision_mask = 0
		chunk_node.add_child(deco_node)
		
		var idx = 0
		for deco in decoration_positions:
			if deco.type == BlockType.TORCH:
				# deco.pos is in world coordinates
				var local_pos = deco.pos - chunk_node.position + Vector3(0.5, 0, 0.5)
				mm.set_instance_transform(idx, Transform3D(Basis(), local_pos))
				
				# Add dynamic light
				var light = OmniLight3D.new()
				light.add_to_group("torch_lights")
				light.light_color = Color(1.0, 0.7, 0.3)
				light.light_energy = 1.5
				light.omni_range = 7.0
				light.position = local_pos + Vector3(0, 0.5, 0)
				
				# Initialize shadow settings
				var state = get_node_or_null("/root/GameState")
				if state:
					_apply_shadow_settings_to_light(light, state.shadow_quality)
				else:
					light.shadow_enabled = true
					
				light.light_cull_mask = 4294967295 - 8 # Ignore Torches (Layer 4) only
				light.distance_fade_enabled = true
				light.distance_fade_begin = 20.0
				light.distance_fade_length = 5.0
				chunk_node.add_child(light)
				
				# Add collision to the deco_node instead of the main chunk_node
				var col = CollisionShape3D.new()
				var box = BoxShape3D.new()
				box.size = Vector3(0.5, 0.8, 0.5) # More accurate torch hit-box
				col.shape = box
				col.position = local_pos + Vector3(0, 0.4, 0)
				deco_node.add_child(col)
				
				idx += 1
	
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
