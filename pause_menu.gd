extends Control

@onready var main_content = find_child("MainContent", true) as Control
@onready var settings_content = find_child("SettingsContent", true) as Control
@onready var render_distance_slider = find_child("RenderDistanceSliderUI", true) as HSlider
@onready var render_distance_label = find_child("RenderDistanceLabelUI", true) as Label
@onready var fov_slider = find_child("FOVSliderUI", true) as HSlider
@onready var fov_label = find_child("FOVLabelUI", true) as Label
@onready var fullscreen_checkbox = find_child("FullscreenCheckBoxUI", true) as CheckBox
@onready var vsync_checkbox = find_child("VSyncCheckBoxUI", true) as CheckBox
@onready var shadows_slider = find_child("ShadowsSliderUI", true) as HSlider
@onready var shadows_label = find_child("ShadowsLabelUI", true) as Label
@onready var msaa_button = find_child("MSAAOptionButtonUI", true) as OptionButton

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	$CenterContainer/MenuPanel/MenuMargin/VBoxContainer/MainContent/ResumeButton.pressed.connect(_on_resume_pressed)
	$CenterContainer/MenuPanel/MenuMargin/VBoxContainer/MainContent/SettingsButton.pressed.connect(_on_settings_pressed)
	$CenterContainer/MenuPanel/MenuMargin/VBoxContainer/MainContent/QuitButton.pressed.connect(_on_quit_pressed)
	$CenterContainer/MenuPanel/MenuMargin/VBoxContainer/SettingsContent/BackButtonUI.pressed.connect(_on_back_pressed)
	
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
	
	var state = get_node_or_null("/root/GameState")
	if state:
		state.settings_changed.connect(_on_external_settings_changed)
		_refresh_ui_from_state()

func _refresh_ui_from_state():
	var state = get_node_or_null("/root/GameState")
	if not state: return
	
	render_distance_slider.set_value_no_signal(state.render_distance)
	render_distance_label.text = "Render Distance: %d" % state.render_distance
	fov_slider.set_value_no_signal(state.fov)
	fov_label.text = "FOV: %d" % state.fov
	fullscreen_checkbox.set_pressed_no_signal(state.borderless_fullscreen)
	vsync_checkbox.set_pressed_no_signal(state.vsync)
	shadows_slider.set_value_no_signal(state.shadow_quality)
	_update_shadows_label(state.shadow_quality)
	msaa_button.selected = state.msaa

func _on_external_settings_changed():
	_refresh_ui_from_state()

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

func _on_resume_pressed():
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_quit_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_settings_pressed():
	main_content.visible = false
	settings_content.visible = true

func _on_back_pressed():
	main_content.visible = true
	settings_content.visible = false

func open():
	visible = true
	main_content.visible = true
	settings_content.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	
	# Auto-save when opening the pause menu (Now Optimized)
	var world = get_node_or_null("/root/World")
	if world and world.has_method("save_game"):
		world.save_game()

func _on_render_distance_changed(value):
	render_distance_label.text = "Render Distance: %d" % value
	var state = get_node_or_null("/root/GameState")
	if state:
		state.render_distance = int(value)
		state.save_settings()
		
	# Apply render distance to the world immediately
	var world = get_node_or_null("/root/World")
	if world:
		world.render_distance = int(value)

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
