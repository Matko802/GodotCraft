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

func _ready():
	_ensure_audio_buses()
	load_settings()
	_apply_initial_audio_settings()
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_absolute(SAVES_DIR)
	if not DirAccess.dir_exists_absolute(SKINS_DIR):
		DirAccess.make_dir_absolute(SKINS_DIR)

func _apply_initial_audio_settings():
	# Explicitly call setters to ensure AudioServer reflects current values
	# especially if load_settings didn't find a config file
	master_volume = master_volume
	blocks_volume = blocks_volume
	damage_volume = damage_volume
	pickup_volume = pickup_volume

func _ensure_audio_buses():
	for bus_name in ["Blocks", "Damage", "Pickup"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var bus_count = AudioServer.bus_count
			AudioServer.add_bus(bus_count)
			AudioServer.set_bus_name(bus_count, bus_name)
			AudioServer.set_bus_send(bus_count, "Master")

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
