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
@onready var slim_checkbox = find_child("SlimModelCheckBoxUI", true) as CheckBox
@onready var browse_texture_button = find_child("BrowseTextureButtonUI", true) as Button
@onready var username_input = find_child("UsernameInputUI", true) as LineEdit

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
	
	slim_checkbox.toggled.connect(_on_slim_toggled)
	browse_texture_button.pressed.connect(_on_browse_texture_pressed)
	username_input.text_changed.connect(_on_username_changed)
	
	_style_ui()
	
	var state = get_node_or_null("/root/GameState")
	if state:
		state.settings_changed.connect(_on_external_settings_changed)
		_refresh_ui_from_state()

func _style_ui():
	# Find all relevant nodes in the settings list
	var settings_list = find_child("SettingsList", true)
	if not settings_list: return
	
	var nodes = []
	var stack = [settings_list]
	# Also include main content buttons
	stack.append(main_content)
	stack.append(find_child("BackButtonUI", true))
	
	while stack.size() > 0:
		var node = stack.pop_back()
		if node == null: continue
		nodes.append(node)
		for child in node.get_children():
			stack.push_back(child)
			
	for node in nodes:
		if node is Button:
			node.add_theme_font_size_override("font_size", 24)
			node.custom_minimum_size.y = 50
		elif node is Label:
			node.add_theme_font_size_override("font_size", 20)
		elif node is LineEdit:
			node.add_theme_font_size_override("font_size", 20)
			node.custom_minimum_size.y = 40
		elif node is CheckBox:
			node.add_theme_font_size_override("font_size", 20)
		elif node is OptionButton:
			node.add_theme_font_size_override("font_size", 20)
			node.custom_minimum_size.y = 40
		elif node is HSlider:
			node.custom_minimum_size.y = 30

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
	slim_checkbox.set_pressed_no_signal(state.is_slim)
	username_input.text = state.username

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

func _on_slim_toggled(toggled_on):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.is_slim = toggled_on
		state.save_settings()

func _on_username_changed(new_username):
	var state = get_node_or_null("/root/GameState")
	if state:
		state.username = new_username
		state.save_settings()

func _on_browse_texture_pressed():
	print("Browse texture pressed")
	if OS.has_feature("web"):
		_open_web_file_dialog()
	elif DisplayServer.has_method("file_dialog_show"):
		var filters = ["*.png", "*.jpg", "*.jpeg", "*.tga", "*.bmp", "*.webp"]
		DisplayServer.file_dialog_show("Open Player Texture", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_file_selected)

var _web_file_callback = null
var _web_reader_callback = null

func _open_web_file_dialog():
	if not JavaScriptBridge: return
	var document = JavaScriptBridge.get_interface("document")
	var input = document.createElement("input")
	input.type = "file"
	input.accept = ".png,.jpg,.jpeg,.webp"
	input.style.display = "none"
	document.body.appendChild(input)
	
	_web_file_callback = JavaScriptBridge.create_callback(func(args):
		_on_web_file_selected(args)
		document.body.removeChild(input)
	)
	input.onchange = _web_file_callback
	input.click()

func _on_web_file_selected(args):
	var event = args[0]
	var files = event.target.files
	if files.length > 0:
		var file = files[0]
		var reader = JavaScriptBridge.create_object("FileReader")
		_web_reader_callback = JavaScriptBridge.create_callback(func(reader_args):
			var result = reader_args[0].target.result
			
			# Use eval to create a helper for Uint8Array creation to avoid bridge issues
			JavaScriptBridge.eval("window._createUint8Array = (buf) => new Uint8Array(buf)")
			var window = JavaScriptBridge.get_interface("window")
			var bytes = window._createUint8Array(result)
			
			if not bytes:
				print("Error: Could not create Uint8Array from buffer")
				return
				
			var packed_bytes = PackedByteArray()
			for i in range(bytes.length): packed_bytes.append(bytes[i])
			var img = Image.new()
			var err = img.load_png_from_buffer(packed_bytes)
			if err != OK: err = img.load_webp_from_buffer(packed_bytes)
			if err != OK: err = img.load_jpg_from_buffer(packed_bytes)
			if err == OK:
				var state = get_node_or_null("/root/GameState")
				var target_path = "user://skins/custom_skin.png"
				if state:
					target_path = state.SKINS_DIR + "custom_skin.png"
				
				img.save_png(target_path)
				if state:
					state.custom_texture_path = target_path
					state.save_settings()
					print("Web skin loaded to skins folder")
		)
		reader.onload = _web_reader_callback
		reader.readAsArrayBuffer(file)

func _on_file_selected(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int):
	if not status or selected_paths.is_empty():
		return
		
	var path = selected_paths[0]
	var img = Image.load_from_file(path)
	if img:
		var state = get_node_or_null("/root/GameState")
		var ext = path.get_extension()
		var target_path = "user://skins/custom_skin." + ext
		if state:
			target_path = state.SKINS_DIR + "custom_skin." + ext
			
		var err = img.save_png(target_path) if ext.to_lower() == "png" else img.save_webp(target_path)
		
		if err == OK:
			if state:
				state.custom_texture_path = target_path
				state.save_settings()
		else:
			print("Error saving custom skin: ", err)

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
