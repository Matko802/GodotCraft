extends Control

@onready var main_content = $CenterContainer/MenuPanel/MenuMargin/VBoxContainer/MainContent
@onready var settings_content = $CenterContainer/MenuPanel/MenuMargin/VBoxContainer/SettingsContent
@onready var render_distance_slider = $CenterContainer/MenuPanel/MenuMargin/VBoxContainer/SettingsContent/SettingsHBox/RenderDistanceSliderUI
@onready var render_distance_label = $CenterContainer/MenuPanel/MenuMargin/VBoxContainer/SettingsContent/SettingsHBox/RenderDistanceLabelUI
@onready var fov_slider = $CenterContainer/MenuPanel/MenuMargin/VBoxContainer/SettingsContent/HBoxFOV/FOVSliderUI
@onready var fov_label = $CenterContainer/MenuPanel/MenuMargin/VBoxContainer/SettingsContent/HBoxFOV/FOVLabelUI
@onready var fullscreen_checkbox = $CenterContainer/MenuPanel/MenuMargin/VBoxContainer/SettingsContent/SettingsHBox/FullscreenCheckBoxUI

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
	
	var state = get_node_or_null("/root/GameState")
	if state:
		state.settings_changed.connect(_on_external_settings_changed)
		render_distance_slider.value = state.render_distance
		render_distance_label.text = "Render Distance: %d" % state.render_distance
		fov_slider.value = state.fov
		fov_label.text = "FOV: %d" % state.fov
		fullscreen_checkbox.button_pressed = state.borderless_fullscreen

func _on_external_settings_changed():
	var state = get_node_or_null("/root/GameState")
	if state:
		fullscreen_checkbox.set_pressed_no_signal(state.borderless_fullscreen)
		render_distance_slider.set_value_no_signal(state.render_distance)
		fov_slider.set_value_no_signal(state.fov)
		fov_label.text = "FOV: %d" % state.fov

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
