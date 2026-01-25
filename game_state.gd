extends Node

var world_seed = "GodotCraft"
var render_distance = 4
var borderless_fullscreen = false
var current_save_name = ""
var fov = 75.0
var username = "Player"
var is_slim = false
var custom_texture_path = ""

# Game Rules
var rules = {
	"drop_items": true
}
var ops = ["Player"] # Default op for simplicity in single player

signal settings_changed

const SETTINGS_PATH = "user://settings.cfg"
const SAVES_DIR = "user://saves/"

func _ready():
	load_settings()
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_absolute(SAVES_DIR)

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
	config.set_value("Graphics", "fov", fov)
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
		fov = config.get_value("Graphics", "fov", 75.0)
		is_slim = config.get_value("Player", "is_slim", false)
		custom_texture_path = config.get_value("Player", "custom_texture_path", "")
	
	_apply_graphics_settings()

func _apply_graphics_settings():
	print("Applying graphics settings: Fullscreen =", borderless_fullscreen)
	if borderless_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

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
