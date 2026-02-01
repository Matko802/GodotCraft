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
@onready var master_volume_slider = find_child("MasterVolumeSliderUI", true) as HSlider
@onready var master_volume_label = find_child("MasterVolumeLabelUI", true) as Label
@onready var blocks_volume_slider = find_child("BlocksVolumeSliderUI", true) as HSlider
@onready var blocks_volume_label = find_child("BlocksVolumeLabelUI", true) as Label
@onready var damage_volume_slider = find_child("DamageVolumeSliderUI", true) as HSlider
@onready var damage_volume_label = find_child("DamageVolumeLabelUI", true) as Label
@onready var pickup_volume_slider = find_child("PickupVolumeSliderUI", true) as HSlider
@onready var pickup_volume_label = find_child("PickupVolumeLabelUI", true) as Label
@onready var slim_checkbox = find_child("SlimModelCheckBoxUI", true) as CheckBox
@onready var custom_texture_input = find_child("CustomTextureInputUI", true) as LineEdit
@onready var browse_texture_button = find_child("BrowseTextureButtonUI", true) as Button
@onready var username_input = find_child("UsernameInputUI", true) as LineEdit
@onready var settings_back_button = find_child("SettingsBackButtonUI", true) as Button

var selected_save_index = -1

func _ready():
	randomize()
	
	# Resume AudioServer on first input (Web requirement)
	if OS.has_feature("web"):
		set_process_input(true)
	
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
	
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	blocks_volume_slider.value_changed.connect(_on_blocks_volume_changed)
	damage_volume_slider.value_changed.connect(_on_damage_volume_changed)
	pickup_volume_slider.value_changed.connect(_on_pickup_volume_changed)
	
	slim_checkbox.toggled.connect(_on_slim_toggled)
	browse_texture_button.pressed.connect(_on_browse_texture_pressed)
	username_input.text_changed.connect(_on_username_changed)
	
	# Initial UI state
	main_screen.visible = true
	play_screen.visible = false
	settings_screen.visible = false
	
	refresh_save_list()
	
	_update_version_label()
	
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
		master_volume_slider.value = state.master_volume
		master_volume_label.text = "Master Volume: %d%%" % int(state.master_volume * 100)
		blocks_volume_slider.value = state.blocks_volume
		blocks_volume_label.text = "Blocks Volume: %d%%" % int(state.blocks_volume * 100)
		damage_volume_slider.value = state.damage_volume
		damage_volume_label.text = "Damage Volume: %d%%" % int(state.damage_volume * 100)
		pickup_volume_slider.value = state.pickup_volume
		pickup_volume_label.text = "Pickup Volume: %d%%" % int(state.pickup_volume * 100)
		slim_checkbox.button_pressed = state.is_slim
		username_input.text = state.username

func _update_version_label():
	var version = ProjectSettings.get_setting("application/config/version", "0.0.0.0")
	var engine_info = Engine.get_version_info()
	var engine_str = "Godot %d.%d.%d" % [engine_info.major, engine_info.minor, engine_info.patch]
	
	if has_node("VersionLabel"):
		$VersionLabel.text = "build %s (%s)" % [version, engine_str]

func _input(event):
	if OS.has_feature("web"):
		if event is InputEventMouseButton or event is InputEventKey:
			if event.pressed:
				_resume_web_audio()
				# Stop processing after successful resume
				set_process_input(false)

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
		master_volume_slider.value = state.master_volume
		master_volume_label.text = "Master Volume: %d%%" % int(state.master_volume * 100)
		blocks_volume_slider.value = state.blocks_volume
		blocks_volume_label.text = "Blocks Volume: %d%%" % int(state.blocks_volume * 100)

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

func _on_master_volume_changed(value):
	master_volume_label.text = "Master Volume: %d%%" % int(value * 100)
	var state = get_node_or_null("/root/GameState")
	if state:
		state.master_volume = value
		state.save_settings()

func _on_blocks_volume_changed(value):
	blocks_volume_label.text = "Blocks Volume: %d%%" % int(value * 100)
	var state = get_node_or_null("/root/GameState")
	if state:
		state.blocks_volume = value
		state.save_settings()

func _on_damage_volume_changed(value):
	damage_volume_label.text = "Damage Volume: %d%%" % int(value * 100)
	var state = get_node_or_null("/root/GameState")
	if state:
		state.damage_volume = value
		state.save_settings()

func _on_pickup_volume_changed(value):
	pickup_volume_label.text = "Pickup Volume: %d%%" % int(value * 100)
	var state = get_node_or_null("/root/GameState")
	if state:
		state.pickup_volume = value
		state.save_settings()

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
	_resume_web_audio()
	main_screen.visible = false
	play_screen.visible = true
	refresh_save_list()

func _on_settings_pressed():
	_resume_web_audio()
	main_screen.visible = false
	settings_screen.visible = true

func _on_quit_pressed():
	_resume_web_audio()
	get_tree().quit()

func _on_back_to_main_pressed():
	_resume_web_audio()
	main_screen.visible = true
	play_screen.visible = false
	settings_screen.visible = false

func _resume_web_audio():
	if not OS.has_feature("web"): return
	
	print("[GodotCraft] Attempting to resume Web audio...")
	# Godot 4 Web audio resume logic
	AudioServer.set_bus_mute(0, false)
	
	# Explicitly resume via JavaScript
	if JavaScriptBridge:
		JavaScriptBridge.eval("""
			(function() {
				var resume = function() {
					var context = window.AudioContext || window.webkitAudioContext;
					if (context) {
						// Resume all potential contexts
						if (typeof Module !== 'undefined' && Module.audioContext) {
							Module.audioContext.resume();
						}
						
						// Create and resume a dummy context to poke the system
						var dummy = new (window.AudioContext || window.webkitAudioContext)();
						dummy.resume();
					}
					console.log('[GodotCraft JS] Audio resume attempt triggered');
				};
				resume();
				// Persistent listeners to ensure resume on any interaction
				window.addEventListener('mousedown', resume, { once: false });
				window.addEventListener('keydown', resume, { once: false });
				window.addEventListener('touchstart', resume, { once: false });
			})();
		""")
	
	# Force unmute and volume reset for all standard buses
	var state = get_node_or_null("/root/GameState")
	for bus_name in ["Master", "Blocks", "Damage", "Pickup"]:
		var idx = AudioServer.get_bus_index(bus_name)
		if idx != -1:
			AudioServer.set_bus_mute(idx, false)
			var vol = 1.0
			if state:
				match bus_name:
					"Master": vol = state.master_volume
					"Blocks": vol = state.blocks_volume
					"Damage": vol = state.damage_volume
					"Pickup": vol = state.pickup_volume
			AudioServer.set_bus_volume_db(idx, linear_to_db(vol))

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
	else:
		print("Native file dialog not supported on this platform/version.")

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
		document.body.removeChild(input) # Cleanup
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
			# For small files like skins, this loop is acceptable
			for i in range(bytes.length):
				packed_bytes.append(bytes[i])
			
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
					if custom_texture_input:
						custom_texture_input.text = target_path
					print("Web skin loaded and saved to skins folder")
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
				print("Skin saved to: ", target_path)
		else:
			print("Error saving custom skin: ", err)
