extends Control

@onready var main_screen = $MainScreen
@onready var play_screen = $PlayScreen
@onready var settings_screen = $SettingsScreen

# Main Screen Buttons
@onready var play_button = $MainScreen/MenuPanel/MenuMargin/VBoxContainer/PlayButton
@onready var settings_button = $MainScreen/MenuPanel/MenuMargin/VBoxContainer/SettingsButton
@onready var quit_button = $MainScreen/MenuPanel/MenuMargin/VBoxContainer/QuitButton

# Play Screen Elements
@onready var world_name_input = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/CreateWorld/NameInputUI
@onready var seed_input = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/CreateWorld/SeedInputUI
@onready var create_button = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/CreateWorld/CreateButtonUI
@onready var save_list = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/LoadWorld/SaveListUI
@onready var load_button = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/LoadWorld/PreviewPanel/HBoxContainer/LoadButtonUI
@onready var delete_button = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/LoadWorld/PreviewPanel/HBoxContainer/DeleteButtonUI
@onready var thumbnail_ui = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/LoadWorld/PreviewPanel/ThumbnailUI
@onready var info_label = $PlayScreen/PanelContainer/VBoxContainer/TabContainer/LoadWorld/PreviewPanel/WorldInfoLabel
@onready var play_back_button = $PlayScreen/PanelContainer/VBoxContainer/PlayBackButton

# Settings Screen Elements
@onready var render_distance_slider = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/HBoxContainer/RenderDistanceSliderUI
@onready var render_distance_label = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/HBoxContainer/RenderDistanceLabelUI
@onready var fov_slider = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/HBoxFOV/FOVSliderUI
@onready var fov_label = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/HBoxFOV/FOVLabelUI
@onready var fullscreen_checkbox = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/FullscreenCheckBoxUI
@onready var slim_checkbox = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/SlimModelCheckBoxUI
@onready var custom_texture_input = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/TextureHBox/CustomTextureInputUI
@onready var username_input = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/UsernameHBox/UsernameInputUI
@onready var settings_back_button = $SettingsScreen/PanelContainer2/SettingsMargin/VBoxContainer/SettingsBackButtonUI

var selected_save_index = -1

func _ready():
	randomize()
	
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
	slim_checkbox.toggled.connect(_on_slim_toggled)
	custom_texture_input.text_changed.connect(_on_custom_texture_changed)
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
		slim_checkbox.button_pressed = state.is_slim
		custom_texture_input.text = state.custom_texture_path
		username_input.text = state.username

func _style_all_buttons():
	# Find all buttons in the scene
	var buttons = []
	var stack = [self]
	while stack.size() > 0:
		var node = stack.pop_back()
		if node is Button:
			buttons.append(node)
		for child in node.get_children():
			stack.push_back(child)
	
	for btn in buttons:
		btn.add_theme_font_size_override("font_size", 24)
		btn.custom_minimum_size.y = 50
		
		# Specific colors for critical buttons
		if btn == load_button:
			var style = btn.get_theme_stylebox("normal").duplicate() if btn.has_theme_stylebox("normal") else StyleBoxFlat.new()
			if style is StyleBoxFlat:
				style.bg_color = Color(0.2, 0.6, 0.2) # Green
				btn.add_theme_stylebox_override("normal", style)
		elif btn == delete_button:
			var style = btn.get_theme_stylebox("normal").duplicate() if btn.has_theme_stylebox("normal") else StyleBoxFlat.new()
			if style is StyleBoxFlat:
				style.bg_color = Color(0.6, 0.2, 0.2) # Red
				btn.add_theme_stylebox_override("normal", style)
		elif btn == create_button:
			var style = btn.get_theme_stylebox("normal").duplicate() if btn.has_theme_stylebox("normal") else StyleBoxFlat.new()
			if style is StyleBoxFlat:
				style.bg_color = Color(0.2, 0.4, 0.6) # Blue-ish
				btn.add_theme_stylebox_override("normal", style)


func _on_external_settings_changed():
	var state = get_node_or_null("/root/GameState")
	if state:
		fullscreen_checkbox.button_pressed = state.borderless_fullscreen
		render_distance_slider.value = state.render_distance
		fov_slider.value = state.fov

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
		var data = {
			"seed": seed_str,
			"world_data": {},
			"player_pos": Vector3(8, 40, 8),
			"player_rot": Vector3.ZERO
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
