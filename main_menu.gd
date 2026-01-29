extends Control

@onready var main_screen = $MainScreen
@onready var play_screen = $PlayScreen
@onready var settings_screen = $SettingsScreen

# Main Screen Buttons
@onready var play_button = $MainScreen/MenuPanel/MenuMargin/VBoxContainer/PlayButton
@onready var settings_button = $MainScreen/MenuPanel/MenuMargin/VBoxContainer/SettingsButton
@onready var quit_button = $MainScreen/MenuPanel/MenuMargin/VBoxContainer/QuitButton

# Play Screen Elements
@onready var world_name_input = find_child("NameInputUI", true) as LineEdit
@onready var seed_input = find_child("SeedInputUI", true) as LineEdit
@onready var create_button = find_child("CreateButtonUI", true) as Button
@onready var save_list = find_child("SaveListUI", true) as ItemList
@onready var load_button = find_child("LoadButtonUI", true) as Button
@onready var delete_button = find_child("DeleteButtonUI", true) as Button
@onready var thumbnail_ui = find_child("ThumbnailUI", true) as TextureRect
@onready var info_label = find_child("WorldInfoLabel", true) as Label
@onready var play_back_button = find_child("PlayBackButton", true) as Button

# Settings Screen Elements
@onready var render_distance_slider = find_child("RenderDistanceSliderUI", true) as HSlider
@onready var render_distance_label = find_child("RenderDistanceLabelUI", true) as Label
@onready var fov_slider = find_child("FOVSliderUI", true) as HSlider
@onready var fov_label = find_child("FOVLabelUI", true) as Label
@onready var fullscreen_checkbox = find_child("FullscreenCheckBoxUI", true) as CheckBox
@onready var vsync_checkbox = find_child("VSyncCheckBoxUI", true) as CheckBox
@onready var shadows_slider = find_child("ShadowsSliderUI", true) as HSlider
@onready var shadows_label = find_child("ShadowsLabelUI", true) as Label
@onready var msaa_button = find_child("MSAAOptionButtonUI", true) as OptionButton
@onready var slim_checkbox = find_child("SlimModelCheckBoxUI", true) as CheckBox
@onready var custom_texture_input = find_child("CustomTextureInputUI", true) as LineEdit
@onready var browse_texture_button = find_child("BrowseTextureButtonUI", true) as Button
@onready var username_input = find_child("UsernameInputUI", true) as LineEdit
@onready var settings_back_button = find_child("SettingsBackButtonUI", true) as Button

var selected_save_index = -1

func _ready():
	randomize()
	
	print("Checking nodes...")
	print("browse_texture_button: ", browse_texture_button)
	print("username_input: ", username_input)
	
	_style_all_buttons()
	
	# Connect Main Screen
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Connect Play Screen
	create_button.pressed.connect(_on_create_pressed)
	load_button.pressed.connect(_on_load_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	play_back_button.pressed.connect(_on_back_to_main_pressed)
	save_list.item_selected.connect(_on_save_selected)
	save_list.item_activated.connect(_on_save_activated)
	
	# Connect Settings Screen
	settings_back_button.pressed.connect(_on_back_to_main_pressed)
	render_distance_slider.value_changed.connect(_on_render_distance_changed)
	fov_slider.value_changed.connect(_on_fov_changed)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	vsync_checkbox.toggled.connect(_on_vsync_toggled)
	shadows_slider.value_changed.connect(_on_shadows_changed)
	
	msaa_button.clear()
	msaa_button.add_item("Disabled", 0)
	msaa_button.add_item("2x", 1)
	msaa_button.add_item("4x", 2)
	msaa_button.add_item("8x", 3)
	msaa_button.item_selected.connect(_on_msaa_selected)
	
	slim_checkbox.toggled.connect(_on_slim_toggled)
	custom_texture_input.text_changed.connect(_on_custom_texture_changed)
	browse_texture_button.pressed.connect(_on_browse_texture_pressed)
	username_input.text_changed.connect(_on_username_changed)
	
	# Initial UI state
	main_screen.visible = true
	play_screen.visible = false
	settings_screen.visible = false
	
	refresh_save_list()
	
	var state = get_node_or_null("/root/GameState")
	if state:
		state.settings_changed.connect(_on_external_settings_changed)
		render_distance_slider.value = state.render_distance
		render_distance_label.text = "Render Distance: %d" % state.render_distance
		fov_slider.value = state.fov
		fov_label.text = "FOV: %d" % state.fov
		fullscreen_checkbox.button_pressed = state.borderless_fullscreen
		vsync_checkbox.button_pressed = state.vsync
		shadows_slider.value = state.shadow_quality
		_update_shadows_label(state.shadow_quality)
		msaa_button.selected = state.msaa
		slim_checkbox.button_pressed = state.is_slim
		custom_texture_input.text = state.custom_texture_path
		username_input.text = state.username

func _style_all_buttons():
	# Find all buttons and other controls in the scene
	var controls = []
	var stack = [self]
	while stack.size() > 0:
		var node = stack.pop_back()
		if node is Control:
			controls.append(node)
		for child in node.get_children():
			stack.push_back(child)
	
	for node in controls:
		if node is Button:
			node.add_theme_font_size_override("font_size", 24)
			node.custom_minimum_size.y = 50
			
			# Specific colors for critical buttons
			if node == load_button:
				var style = node.get_theme_stylebox("normal").duplicate() if node.has_theme_stylebox("normal") else StyleBoxFlat.new()
				if style is StyleBoxFlat:
					style.bg_color = Color(0.2, 0.6, 0.2) # Green
					node.add_theme_stylebox_override("normal", style)
			elif node == delete_button:
				var style = node.get_theme_stylebox("normal").duplicate() if node.has_theme_stylebox("normal") else StyleBoxFlat.new()
				if style is StyleBoxFlat:
					style.bg_color = Color(0.6, 0.2, 0.2) # Red
					node.add_theme_stylebox_override("normal", style)
			elif node == create_button:
				var style = node.get_theme_stylebox("normal").duplicate() if node.has_theme_stylebox("normal") else StyleBoxFlat.new()
				if style is StyleBoxFlat:
					style.bg_color = Color(0.2, 0.4, 0.6) # Blue-ish
					node.add_theme_stylebox_override("normal", style)
		elif node is Label:
			if node.name != "Title": # Keep title as is or it might be too small/big
				node.add_theme_font_size_override("font_size", 20)
		elif node is LineEdit:
			node.add_theme_font_size_override("font_size", 20)
			node.custom_minimum_size.y = 45
		elif node is CheckBox:
			node.add_theme_font_size_override("font_size", 20)
		elif node is OptionButton:
			node.add_theme_font_size_override("font_size", 20)
			node.custom_minimum_size.y = 45
		elif node is HSlider:
			node.custom_minimum_size.y = 30


func _on_external_settings_changed():
	var state = get_node_or_null("/root/GameState")
	if state:
		fullscreen_checkbox.button_pressed = state.borderless_fullscreen
		vsync_checkbox.button_pressed = state.vsync
		shadows_slider.value = state.shadow_quality
		_update_shadows_label(state.shadow_quality)
		msaa_button.selected = state.msaa
		render_distance_slider.value = state.render_distance
		fov_slider.value = state.fov

func _on_vsync_toggled(toggled_on):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.vsync = toggled_on
		state.save_settings()
		state._apply_graphics_settings()

func _on_shadows_changed(value):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.shadow_quality = int(value)
		state.save_settings()
		_update_shadows_label(state.shadow_quality)

func _update_shadows_label(value):
	var text = "Off"
	match int(value):
		1: text = "Low"
		2: text = "Medium"
		3: text = "High"
		4: text = "Ultra"
	shadows_label.text = "Shadows: " + text

func _on_msaa_selected(index):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.msaa = index
		state.save_settings()
		state._apply_graphics_settings()

func refresh_save_list():
	save_list.clear()
	selected_save_index = -1
	load_button.disabled = true
	delete_button.disabled = true
	thumbnail_ui.texture = null
	info_label.text = "Select a world"
	
	var state = get_node_or_null("/root/GameState")
	if state:
		var saves = state.get_save_list()
		for s in saves:
			var s_name = s.get("name", "Unknown World")
			var s_date = s.get("date", "Unknown Date")
			var text = "%s (%s)" % [s_name, s_date]
			save_list.add_item(text)
			save_list.set_item_metadata(save_list.get_item_count() - 1, s_name)

func _on_play_pressed():
	main_screen.visible = false
	play_screen.visible = true
	refresh_save_list()

func _on_settings_pressed():
	main_screen.visible = false
	settings_screen.visible = true

func _on_quit_pressed():
	get_tree().quit()

func _on_back_to_main_pressed():
	main_screen.visible = true
	play_screen.visible = false
	settings_screen.visible = false

func _on_create_pressed():
	var world_name = world_name_input.text.strip_edges()
	if world_name == "":
		world_name = "World " + str(randi() % 1000)
	
	var seed_str = seed_input.text.strip_edges()
	if seed_str == "":
		seed_str = str(randi())
	
	var state = get_node_or_null("/root/GameState")
	if state:
		state.current_save_name = world_name
		state.world_seed = seed_str
		state.gamemode = state.GameMode.SURVIVAL # Default to survival
		var data = {
			"seed": seed_str,
			"world_data": {},
			"player_pos": Vector3(8, 40, 8),
			"player_rot": Vector3.ZERO,
			"gamemode": state.GameMode.SURVIVAL,
			"ops": []
		}
		state.save_game(world_name, data)
		state.save_settings()
	
	get_tree().change_scene_to_file("res://world.tscn")

func _on_save_selected(index):
	selected_save_index = index
	load_button.disabled = false
	delete_button.disabled = false
	
	var save_name = save_list.get_item_metadata(index)
	var state = get_node_or_null("/root/GameState")
	if state:
		var info = state.get_save_info(save_name)
		if info:
			var date = info.get("date", "Unknown")
			var world_seed_val = info.get("seed", "Unknown")
			info_label.text = "Name: %s\nPlayed: %s\nSeed: %s" % [save_name, date, world_seed_val]
			
			var thumb_path = info.get("thumbnail", "")
			if thumb_path != "" and FileAccess.file_exists(thumb_path):
				var img = Image.load_from_file(thumb_path)
				thumbnail_ui.texture = ImageTexture.create_from_image(img)
			else:
				thumbnail_ui.texture = null
		else:
			info_label.text = "Error loading info"
			thumbnail_ui.texture = null

func _on_save_activated(index):
	_on_save_selected(index)
	_on_load_pressed()

func _on_load_pressed():
	if selected_save_index == -1: return
	
	var save_name = save_list.get_item_metadata(selected_save_index)
	var state = get_node_or_null("/root/GameState")
	if state:
		state.current_save_name = save_name
		# We don't load data here anymore to avoid lag
		# The World scene will load it in its _ready
		state.save_settings()
		
	get_tree().change_scene_to_file("res://world.tscn")

func _on_delete_pressed():
	if selected_save_index == -1: return
	
	var save_name = save_list.get_item_metadata(selected_save_index)
	var state = get_node_or_null("/root/GameState")
	if state:
		state.delete_save(save_name)
		refresh_save_list()

func _on_render_distance_changed(value):
	render_distance_label.text = "Render Distance: %d" % value
	var state = get_node_or_null("/root/GameState")
	if state:
		state.render_distance = int(value)
		state.save_settings()

func _on_fov_changed(value):
	fov_label.text = "FOV: %d" % value
	var state = get_node_or_null("/root/GameState")
	if state:
		state.fov = float(value)
		state.save_settings()
		state.settings_changed.emit()

func _on_fullscreen_toggled(toggled_on):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.borderless_fullscreen = toggled_on
		state.save_settings()
		state._apply_graphics_settings()

func _on_slim_toggled(toggled_on):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.is_slim = toggled_on
		state.save_settings()

func _on_custom_texture_changed(new_path):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.custom_texture_path = new_path
		state.save_settings()

func _on_username_changed(new_username):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.username = new_username
		state.save_settings()

func _on_browse_texture_pressed():
	# Use Godot's built-in file dialog which works on Desktop and Godot 4.3+ Web
	# Filters for common image formats
	var filters = ["*.png", "*.jpg", "*.jpeg", "*.tga", "*.bmp", "*.webp"]
	DisplayServer.file_dialog_show("Open Player Texture", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_file_selected)

func _on_file_selected(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int):
	if not status or selected_paths.is_empty():
		return
		
	var path = selected_paths[0]
	var img = Image.load_from_file(path)
	if img:
		# Copy the file to user:// to ensure it persists and is accessible by the game
		# This is especially important for Web where the local path might be temporary
		var ext = path.get_extension()
		var target_path = "user://custom_skin." + ext
		
		# For Web, we must save it to user:// to ensure we have a persistent internal path
		var err = img.save_png(target_path) if ext.to_lower() == "png" else img.save_webp(target_path)
		
		if err == OK:
			var state = get_node_or_null("/root/GameState")
			if state:
				state.custom_texture_path = target_path
				state.save_settings()
				custom_texture_input.text = target_path
				print("Skin saved to: ", target_path)
		else:
			print("Error saving custom skin: ", err)
