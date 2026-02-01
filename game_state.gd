extends Node

var world_seed = "GodotCraft"
var render_distance = 4:
	set(value):
		render_distance = value
		settings_changed.emit()

var borderless_fullscreen = false:
	set(value):
		borderless_fullscreen = value
		_apply_graphics_settings()
		settings_changed.emit()

var msaa = 0: # 0: Disabled, 1: 2x, 2: 4x, 3: 8x
	set(value):
		msaa = value
		_apply_graphics_settings()
		settings_changed.emit()

var vsync = true:
	set(value):
		vsync = value
		_apply_graphics_settings()
		settings_changed.emit()

var shadow_quality = 2: # 0: Off, 1: Low, 2: Medium, 3: High, 4: Ultra
	set(value):
		shadow_quality = value
		_apply_graphics_settings()
		settings_changed.emit()

var current_save_name = ""

var fov = 75.0:
	set(value):
		fov = value
		settings_changed.emit()

var master_volume = 1.0:
	set(value):
		master_volume = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		settings_changed.emit()

var blocks_volume = 1.0:
	set(value):
		blocks_volume = value
		var bus_idx = AudioServer.get_bus_index("Blocks")
		if bus_idx != -1:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
		settings_changed.emit()

var damage_volume = 1.0:
	set(value):
		damage_volume = value
		var bus_idx = AudioServer.get_bus_index("Damage")
		if bus_idx != -1:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
		settings_changed.emit()

var pickup_volume = 1.0:
	set(value):
		pickup_volume = value
		var bus_idx = AudioServer.get_bus_index("Pickup")
		if bus_idx != -1:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
		settings_changed.emit()

var username = "Player"
var is_slim = false:
	set(value):
		is_slim = value
		settings_changed.emit()

var custom_texture_path = ""

enum GameMode { SURVIVAL, CREATIVE }
var gamemode = GameMode.SURVIVAL:
	set(value):
		gamemode = value
		gamemode_changed.emit(value)

signal gamemode_changed(new_mode)

# Game Rules
var rules = {
	"drop_items": true
}
var ops = [] # No default ops

signal settings_changed

const SETTINGS_PATH = "user://settings.cfg"
const SAVES_DIR = "user://saves/"
const SKINS_DIR = "user://skins/"

var remote_sound_cache = {}
var _pending_sounds = []
var _is_downloading = false
var _current_http: HTTPRequest = null
var _currently_downloading_path = ""

signal all_remote_sounds_loaded

const REMOTE_BASE_URL = "https://raw.githubusercontent.com/Matko802/GodotCraft/main/"

const SOUND_LIST = [
	"res://textures/Sounds/block_broke/stone1.ogg",
	"res://textures/Sounds/block_broke/stone2.ogg",
	"res://textures/Sounds/block_broke/stone3.ogg",
	"res://textures/Sounds/block_broke/stone4.ogg",
	"res://textures/Sounds/block_broke/gravel1.ogg",
	"res://textures/Sounds/block_broke/gravel2.ogg",
	"res://textures/Sounds/block_broke/gravel3.ogg",
	"res://textures/Sounds/block_broke/gravel4.ogg",
	"res://textures/Sounds/block_breaking/grass1.ogg",
	"res://textures/Sounds/block_breaking/grass2.ogg",
	"res://textures/Sounds/block_breaking/grass3.ogg",
	"res://textures/Sounds/block_breaking/grass4.ogg",
	"res://textures/Sounds/block_breaking/sand1.ogg",
	"res://textures/Sounds/block_breaking/sand2.ogg",
	"res://textures/Sounds/block_breaking/sand3.ogg",
	"res://textures/Sounds/block_breaking/sand4.ogg",
	"res://textures/Sounds/block_breaking/wood1.ogg",
	"res://textures/Sounds/block_breaking/wood2.ogg",
	"res://textures/Sounds/block_breaking/wood3.ogg",
	"res://textures/Sounds/block_breaking/wood4.ogg",
	"res://textures/Sounds/block_hit/stone1.ogg",
	"res://textures/Sounds/damage/hit1.ogg",
	"res://textures/Sounds/damage/hit2.ogg",
	"res://textures/Sounds/damage/hit3.ogg",
	"res://textures/Sounds/damage/fallsmall.ogg",
	"res://textures/Sounds/damage/fallbig1.ogg",
	"res://textures/Sounds/damage/fallbig2.ogg",
	"res://textures/Sounds/random/pop.ogg"
]

func _ready():
	_ensure_audio_buses()
	load_settings()
	_apply_initial_audio_settings()
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_absolute(SAVES_DIR)
	if not DirAccess.dir_exists_absolute(SKINS_DIR):
		DirAccess.make_dir_absolute(SKINS_DIR)
	
	if OS.has_feature("web"):
		call_deferred("_start_remote_sound_download")

func _start_remote_sound_download():
	print("[GodotCraft] Web detected. Starting remote sound download from GitHub...")
	_pending_sounds = SOUND_LIST.duplicate()
	_download_next_sound()

func _download_next_sound():
	if _pending_sounds.is_empty():
		print("[GodotCraft] All remote sounds downloaded.")
		_is_downloading = false
		all_remote_sounds_loaded.emit()
		return
		
	_is_downloading = true
	var res_path = _pending_sounds.pop_front()
	_currently_downloading_path = res_path
	var url = res_path.replace("res://", REMOTE_BASE_URL)
	
	if _current_http == null:
		_current_http = HTTPRequest.new()
		add_child(_current_http)
		_current_http.request_completed.connect(_on_sound_download_completed)
	
	var err = _current_http.request(url)
	if err != OK:
		print("ERROR: Failed to start request for: ", url)
		_download_next_sound()

func _on_sound_download_completed(result, response_code, _headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var stream = AudioStreamOggVorbis.load_from_buffer(body)
		if stream:
			remote_sound_cache[_currently_downloading_path] = stream
			# print("Downloaded: ", _currently_downloading_path)
		else:
			print("ERROR: Failed to parse OGG from: ", _currently_downloading_path)
	else:
		print("ERROR: Download failed with code: ", response_code)
		
	_download_next_sound()

func get_sound(path: String) -> AudioStream:
	if remote_sound_cache.has(path):
		return remote_sound_cache[path]
	
	if OS.has_feature("web"):
		# On web, if it's not in the remote cache, we don't try local load
		return null
		
	# Fallback to local load for PC
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _apply_initial_audio_settings():
	# Explicitly call setters to ensure AudioServer reflects current values
	# especially if load_settings didn't find a config file
	master_volume = master_volume
	blocks_volume = blocks_volume
	damage_volume = damage_volume
	pickup_volume = pickup_volume

func _ensure_audio_buses():
	print("Ensuring audio buses...")
	var master_idx = AudioServer.get_bus_index("Master")
	print("Master bus index: ", master_idx)
	if master_idx != -1:
		print("Master bus volume: ", AudioServer.get_bus_volume_db(master_idx))
		AudioServer.set_bus_mute(master_idx, false)

	for bus_name in ["Blocks", "Damage", "Pickup"]:
		var idx = AudioServer.get_bus_index(bus_name)
		if idx == -1:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
			print("Created bus: ", bus_name, " at index: ", idx)
		else:
			AudioServer.set_bus_send(idx, "Master")
			print("Found existing bus: ", bus_name, " at index: ", idx)
		
		# Ensure not muted
		AudioServer.set_bus_mute(idx, false)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		borderless_fullscreen = !borderless_fullscreen
		save_settings()
		_apply_graphics_settings()
		settings_changed.emit()

func save_settings():
	var config = ConfigFile.new()
	config.set_value("Game", "world_seed", world_seed)
	config.set_value("Game", "username", username)
	config.set_value("Graphics", "render_distance", render_distance)
	config.set_value("Graphics", "borderless_fullscreen", borderless_fullscreen)
	config.set_value("Graphics", "msaa", msaa)
	config.set_value("Graphics", "vsync", vsync)
	config.set_value("Graphics", "shadow_quality", shadow_quality)
	config.set_value("Graphics", "fov", fov)
	config.set_value("Audio", "master_volume", master_volume)
	config.set_value("Audio", "blocks_volume", blocks_volume)
	config.set_value("Audio", "damage_volume", damage_volume)
	config.set_value("Audio", "pickup_volume", pickup_volume)
	config.set_value("Player", "is_slim", is_slim)
	config.set_value("Player", "custom_texture_path", custom_texture_path)
	config.save(SETTINGS_PATH)

func load_settings():
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		world_seed = config.get_value("Game", "world_seed", "GodotCraft")
		username = config.get_value("Game", "username", "Player")
		render_distance = config.get_value("Graphics", "render_distance", 4)
		borderless_fullscreen = config.get_value("Graphics", "borderless_fullscreen", false)
		msaa = config.get_value("Graphics", "msaa", 0)
		vsync = config.get_value("Graphics", "vsync", true)
		shadow_quality = config.get_value("Graphics", "shadow_quality", 2)
		fov = config.get_value("Graphics", "fov", 75.0)
		master_volume = config.get_value("Audio", "master_volume", 1.0)
		blocks_volume = config.get_value("Audio", "blocks_volume", 1.0)
		damage_volume = config.get_value("Audio", "damage_volume", 1.0)
		pickup_volume = config.get_value("Audio", "pickup_volume", 1.0)
		is_slim = config.get_value("Player", "is_slim", false)
		custom_texture_path = config.get_value("Player", "custom_texture_path", "")
	
	_apply_graphics_settings()

func _apply_graphics_settings():
	print("Applying graphics settings")
	if borderless_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
	# Apply VSync
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		
	# Apply MSAA (This applies to the main viewport)
	var msaa_value = Viewport.MSAA_DISABLED
	match msaa:
		1: msaa_value = Viewport.MSAA_2X
		2: msaa_value = Viewport.MSAA_4X
		3: msaa_value = Viewport.MSAA_8X
	get_viewport().msaa_3d = msaa_value
	
	# Apply global shadow quality
	match shadow_quality:
		0: pass
		1: # Low
			RenderingServer.positional_soft_shadow_filter_set_quality(1 as RenderingServer.ShadowQuality)
			RenderingServer.directional_soft_shadow_filter_set_quality(1 as RenderingServer.ShadowQuality)
		2: # Medium
			RenderingServer.positional_soft_shadow_filter_set_quality(2 as RenderingServer.ShadowQuality)
			RenderingServer.directional_soft_shadow_filter_set_quality(2 as RenderingServer.ShadowQuality)
		3: # High
			RenderingServer.positional_soft_shadow_filter_set_quality(3 as RenderingServer.ShadowQuality)
			RenderingServer.directional_soft_shadow_filter_set_quality(3 as RenderingServer.ShadowQuality)
		4: # Ultra
			RenderingServer.positional_soft_shadow_filter_set_quality(4 as RenderingServer.ShadowQuality)
			RenderingServer.directional_soft_shadow_filter_set_quality(4 as RenderingServer.ShadowQuality)
	
	# Shadows are applied by the World scene when it detects change or on ready
	settings_changed.emit()

func get_save_list():
	var saves = []
	var dir = DirAccess.open(SAVES_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".save"):
				var save_name = file_name.replace(".save", "")
				var info = get_save_info(save_name)
				if info:
					saves.append(info)
			file_name = dir.get_next()
	return saves

func get_save_info(save_name):
	var path = SAVES_DIR + save_name + ".save"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file.get_length() < 4: return null
		var header = file.get_var()
		if header is Dictionary:
			# Ensure backward compatibility for old save files
			if not header.has("name"):
				header["name"] = save_name
			if not header.has("date"):
				header["date"] = "Pre-update"
			
			var thumb_path = SAVES_DIR + save_name + ".png"
			if FileAccess.file_exists(thumb_path):
				header["thumbnail"] = thumb_path
			else:
				header["thumbnail"] = ""
				
			return header
	return null

func delete_save(save_name):
	var path = SAVES_DIR + save_name + ".save"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var thumb_path = SAVES_DIR + save_name + ".png"
	if FileAccess.file_exists(thumb_path):
		DirAccess.remove_absolute(thumb_path)

func save_game(save_name, data):
	var path = SAVES_DIR + save_name + ".save"
	var file = FileAccess.open(path, FileAccess.WRITE)
	var header = {
		"name": save_name,
		"date": Time.get_datetime_string_from_system(false, true),
		"seed": data.get("seed", "")
	}
	file.store_var(header) # Store header first
	file.store_var(data)   # Store full data second
	file.flush()

func load_game_data(save_name):
	var path = SAVES_DIR + save_name + ".save"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		file.get_var() # Skip header
		return file.get_var() # Return actual data
	return null
