extends CharacterBody3D

const SPEED = 4.3
const SPRINT_SPEED = 5.6
const JUMP_VELOCITY = 8.5
const FLY_SPEED = 10.0
const FLY_SPRINT_SPEED = 20.0
const FLY_ACCEL = 10.0
const MOUSE_SENSITIVITY = 0.002

@onready var camera = $SpringArm3D/Camera3D
@onready var spring_arm = $SpringArm3D
@onready var raycast = $RayCastPivot/RayCast3D
@onready var inventory = $Inventory
@onready var inventory_ui = $HUD/InventoryUI
@onready var chat_ui = $HUD/ChatUI
@onready var crosshair = $HUD/CrosshairContainer
@onready var pause_menu = $PauseLayer/PauseMenu
@onready var player_model = $PlayerModel

@onready var view_model_camera = $ViewModelLayer/ViewModelContainer/SubViewport/ViewModelCamera
@onready var view_model_arm = $ViewModelLayer/ViewModelContainer/SubViewport/ViewModelCamera/ViewModelArm
@onready var slim_hand = $ViewModelLayer/ViewModelContainer/SubViewport/ViewModelCamera/ViewModelArm/SlimHandModel
@onready var wide_hand = $ViewModelLayer/ViewModelContainer/SubViewport/ViewModelCamera/ViewModelArm/WideHandModel
@onready var held_item_mesh = $ViewModelLayer/ViewModelContainer/SubViewport/ViewModelCamera/ViewModelArm/HeldItemRoot/HeldItemMesh
@onready var held_torch_root = $ViewModelLayer/ViewModelContainer/SubViewport/ViewModelCamera/ViewModelArm/HeldTorchRoot
@onready var hand_torch_mesh = $ViewModelLayer/ViewModelContainer/SubViewport/ViewModelCamera/ViewModelArm/HeldTorchRoot/HandTorchMesh
@onready var view_model_anim = $ViewModelAnimationPlayer

@onready var tp_held_item_mesh = $TPHeldItemRoot/TPHeldItemMesh
@onready var tp_held_item_root = $TPHeldItemRoot
@onready var tp_held_torch_root = $TPHeldTorchRoot
@onready var tp_held_torch_mesh = $TPHeldTorchRoot/TPHeldTorchMesh

@onready var right_arm = $PlayerModel/Waist/"Right Arm2"
@onready var left_arm = $PlayerModel/Waist/"Left Arm2"
@onready var right_leg = $"PlayerModel/Right Leg2"
@onready var left_leg = $"PlayerModel/Left Leg2"

var walk_time = 0.0
var idle_time = 0.0
var is_swinging = false
var swing_progress = 0.0
const SWING_SPEED = 8.0

var _hand_light_ref: OmniLight3D = null
var _viewmodel_light_ref: OmniLight3D = null

@onready var head_node = null
@onready var raycast_pivot = $RayCastPivot

signal health_changed(new_health)

var max_health = 20
var health = 20:
	set(value):
		var state = get_node_or_null("/root/GameState")
		if state and state.gamemode == state.GameMode.CREATIVE:
			# In creative, only allow health to be set to 0 (death command)
			if value > 0:
				return
				
		if value < health:
			_play_damage_sound()
		health = clamp(value, 0, max_health)
		health_changed.emit(health)
		if health <= 0:
			_die()

var is_flying = false

const DAMAGE_SOUNDS = [
	"res://textures/Sounds/damage/hit1.ogg",
	"res://textures/Sounds/damage/hit2.ogg",
	"res://textures/Sounds/damage/hit3.ogg"
]

const FALL_SMALL_SOUND = "res://textures/Sounds/damage/fallsmall.ogg"
const FALL_BIG_SOUNDS = [
	"res://textures/Sounds/damage/fallbig1.ogg",
	"res://textures/Sounds/damage/fallbig2.ogg"
]

func _play_fall_sound(dist: float):
	var audio = AudioStreamPlayer.new()
	if dist > 7.0:
		audio.stream = load(FALL_BIG_SOUNDS[randi() % FALL_BIG_SOUNDS.size()])
	else:
		audio.stream = load(FALL_SMALL_SOUND)
	audio.bus = "Master"
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _play_damage_sound():
	var sound_path = DAMAGE_SOUNDS[randi() % DAMAGE_SOUNDS.size()]
	var audio = AudioStreamPlayer.new()
	audio.stream = load(sound_path)
	audio.bus = "Master"
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

# Camera Modes
enum CameraMode { FIRST_PERSON, THIRD_PERSON_BACK, THIRD_PERSON_FRONT }
var current_camera_mode = CameraMode.FIRST_PERSON

var view_model_base_pos = Vector3.ZERO
var view_model_base_rot = Vector3.ZERO

func _die():
	var state = get_node_or_null("/root/GameState")
	var drop_items = true
	if state:
		drop_items = state.rules.get("drop_items", true)
	
	if drop_items:
		inventory.drop_all(global_position, world)
	
	# Simple respawn: reset health and move to spawn
	health = max_health
	
	var respawn_p = world.spawn_pos
	if world.has_method("get_highest_block_y"):
		var hy = world.get_highest_block_y(int(respawn_p.x), int(respawn_p.z))
		respawn_p.y = hy + 2.0
		
	global_position = respawn_p
	velocity = Vector3.ZERO
	if chat_ui:
		chat_ui.add_message("[color=red]You died![/color]")

var gravity = 28.0 # Tuned for responsive voxel jumping
var world = null
var selected_slot = 0
var selection_box: MeshInstance3D

var _was_on_floor = false
var _fall_start_y = 0.0
var _void_damage_timer = 0.0

var _last_jump_press_time = -1.0
const DOUBLE_TAP_TIME = 0.3

func _ready():
	add_to_group("player")
	collision_layer = 2 # Player on layer 2
	collision_mask = 1  # Collide with world (layer 1)
	
	# Raycast should hit World (1) and Decos (4) -> Mask 5
	raycast.collision_mask = 5
	
	_setup_input_map()
	
	print("Player ready. World: ", get_parent().name)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	world = get_parent()
	
	_setup_selection_box()
	_setup_player_model()
	_setup_view_model()
	
	var state = get_node_or_null("/root/GameState")
	if state:
		state.settings_changed.connect(_on_settings_changed)
		_on_settings_changed()
	
	if inventory_ui:
		inventory_ui.setup(self)
	
	inventory.inventory_changed.connect(_update_held_item_mesh)

func _setup_input_map():
	var actions = {
		"move_forward": [KEY_W],
		"move_back": [KEY_S],
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"jump": [KEY_SPACE],
		"sneak": [KEY_SHIFT],
		"inventory": [KEY_E],
		"drop": [KEY_Q],
		"chat": [KEY_T, KEY_ENTER],
		"attack": [MOUSE_BUTTON_LEFT],
		"interact": [MOUSE_BUTTON_RIGHT],
		"camera_toggle": [KEY_F5]
	}
	
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
			
		for key in actions[action]:
			var ev
			if key is int and key < 10: # Mouse buttons
				ev = InputEventMouseButton.new()
				ev.button_index = key
			else:
				ev = InputEventKey.new()
				ev.keycode = key
			InputMap.action_add_event(action, ev)

var camera_pitch = 0.0

func _setup_player_model():
	var state = get_node_or_null("/root/GameState")
	var is_slim = state.is_slim if state else false
	var tex_path = state.custom_texture_path if state and state.custom_texture_path != "" else ("res://models/player/slim/model_0.png" if is_slim else "res://models/player/wide/model_0.png")
	
	# Replace model if type changed
	var model_path = "res://models/player/slim/model.gltf" if is_slim else "res://models/player/wide/model.gltf"
	
	var current_path = player_model.scene_file_path
	if current_path != model_path:
		print("Swapping player model from ", current_path, " to ", model_path)
		
		# CRITICAL: Preserve attachment points before destroying old model
		if tp_held_item_root and tp_held_item_root.get_parent() != self:
			tp_held_item_root.reparent(self, true)
		if tp_held_torch_root and tp_held_torch_root.get_parent() != self:
			tp_held_torch_root.reparent(self, true)
			
		var new_model = load(model_path).instantiate()
		new_model.name = "PlayerModel"
		
		# Transfer transform
		new_model.transform = player_model.transform
		
		var parent = player_model.get_parent()
		parent.add_child(new_model)
		
		# Clean up old model
		player_model.queue_free()
		player_model = new_model

	# Find body parts for animation with fallback
	right_arm = player_model.find_child("Right Arm2", true)
	if not right_arm: right_arm = player_model.find_child("Right Arm", true)
	
	left_arm = player_model.find_child("Left Arm2", true)
	if not left_arm: left_arm = player_model.find_child("Left Arm", true)
	
	right_leg = player_model.find_child("Right Leg2", true)
	if not right_leg: right_leg = player_model.find_child("Right Leg", true)
	
	left_leg = player_model.find_child("Left Leg2", true)
	if not left_leg: left_leg = player_model.find_child("Left Leg", true)
	
	var new_head = player_model.find_child("Head2", true)
	if not new_head: new_head = player_model.find_child("Head", true)
	
	if new_head and head_node != new_head:
		head_node = new_head

	# Setup Third Person held item attachment from scene
	if right_arm:
		if tp_held_item_root:
			if tp_held_item_root.get_parent() != right_arm:
				tp_held_item_root.reparent(right_arm, true)
		
		if tp_held_torch_root:
			if tp_held_torch_root.get_parent() != right_arm:
				tp_held_torch_root.reparent(right_arm, true)

	# Apply texture
	var texture = null
	if tex_path.begins_with("res://"):
		texture = load(tex_path)
	elif FileAccess.file_exists(tex_path):
		var img = Image.load_from_file(tex_path)
		texture = ImageTexture.create_from_image(img)
	
	if not texture: texture = load("res://models/player/wide/model_0.png")
	
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	
	# Ensure every visual part of the player model is on Layer 3
	# This is critical so the held torch light (cull mask 1) can ignore it.
	if player_model is VisualInstance3D:
		player_model.layers = 4
	for child in player_model.find_children("*", "VisualInstance3D", true):
		child.layers = 4 # Layer 3
		if child is MeshInstance3D:
			child.material_override = mat
	
	_update_camera_mode()

func _on_settings_changed():
	var state = get_node_or_null("/root/GameState")
	if state:
		camera.fov = state.fov
		_update_light_shadows()

func _update_light_shadows():
	if not _hand_light_ref: return
	_hand_light_ref.shadow_enabled = false # Held torch shadows are disabled as requested

func _setup_selection_box():
	selection_box = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var s = 0.505
	var verts = [
		Vector3(-s,-s,-s), Vector3(s,-s,-s), Vector3(s,-s,-s), Vector3(s,-s,s),
		Vector3(s,-s,s), Vector3(-s,-s,s), Vector3(-s,-s,s), Vector3(-s,-s,-s),
		Vector3(-s,s,-s), Vector3(s,s,-s), Vector3(s,s,-s), Vector3(s,s,s),
		Vector3(s,s,s), Vector3(-s,s,s), Vector3(-s,s,s), Vector3(-s,s,-s),
		Vector3(-s,-s,-s), Vector3(-s,s,-s), Vector3(s,-s,-s), Vector3(s,s,-s),
		Vector3(s,-s,s), Vector3(s,s,s), Vector3(-s,-s,s), Vector3(-s,s,s)
	]
	for v in verts:
		st.add_vertex(v)
	selection_box.mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK
	mat.render_priority = 10
	# No depth test allows the outline to be seen through some transparent surfaces
	# though typically in Minecraft it's depth tested.
	mat.no_depth_test = false 
	selection_box.material_override = mat
	selection_box.layers = 4 # Layer 3 (Player)
	selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(selection_box)
	selection_box.top_level = true
	selection_box.visible = false

func _setup_view_model():
	if not view_model_arm: return
	
	var state = get_node_or_null("/root/GameState")
	var is_slim = state.is_slim if state else false
	
	# Initial visibility handled by _update_held_item_mesh
	# Setup Materials for hands
	var tex_path = state.custom_texture_path if state and state.custom_texture_path != "" else ("res://models/player/slim/slimhand_0.png" if is_slim else "res://models/player/wide/widehand_0.png")
	var texture = null
	if tex_path.begins_with("res://"):
		texture = load(tex_path)
	elif FileAccess.file_exists(tex_path):
		var img = Image.load_from_file(tex_path)
		texture = ImageTexture.create_from_image(img)
	if not texture: 
		texture = load("res://models/player/slim/slimhand_0.png" if is_slim else "res://models/player/wide/widehand_0.png")

	var hand_mat = ShaderMaterial.new()
	hand_mat.shader = load("res://viewmodel.gdshader")
	hand_mat.set_shader_parameter("albedo_texture", texture)
	
	for hand in [slim_hand, wide_hand]:
		for child in hand.find_children("*", "MeshInstance3D", true):
			child.material_override = hand_mat
			child.layers = 2
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			
	_update_held_item_mesh()

func _update_held_item_mesh():
	var state = get_node_or_null("/root/GameState")
	var is_slim = state.is_slim if state else false
	var item = inventory.hotbar[selected_slot]
	var is_fp = current_camera_mode == CameraMode.FIRST_PERSON
	
	# Light management - World Light
	if not _hand_light_ref:
		_hand_light_ref = OmniLight3D.new()
		_hand_light_ref.name = "HandLight"
		_hand_light_ref.add_to_group("torch_lights")
		_hand_light_ref.light_color = Color(1.0, 0.7, 0.3)
		_hand_light_ref.light_energy = 1.5
		_hand_light_ref.omni_range = 12.0
		_hand_light_ref.shadow_enabled = false
		_hand_light_ref.shadow_bias = 0.05
		_hand_light_ref.shadow_blur = 1.5
		# Default to hitting only World (Layer 1)
		_hand_light_ref.light_cull_mask = 1
		add_child(_hand_light_ref)
		_update_light_shadows()

	# Light management - ViewModel Light
	if not _viewmodel_light_ref:
		_viewmodel_light_ref = OmniLight3D.new()
		_viewmodel_light_ref.name = "ViewModelLight"
		_viewmodel_light_ref.light_color = Color(1.0, 0.7, 0.3)
		_viewmodel_light_ref.light_energy = 2.0
		_viewmodel_light_ref.omni_range = 5.0
		_viewmodel_light_ref.light_cull_mask = 2 # Only affect Viewmodel layer
		view_model_camera.add_child(_viewmodel_light_ref)
	
	# Always manage hand visibility in FP - Hide hand if holding an item
	var show_hand = is_fp and not item
	slim_hand.visible = is_slim and show_hand
	wide_hand.visible = not is_slim and show_hand
	
	if not item:
		held_item_mesh.visible = false
		held_item_mesh.mesh = null
		if tp_held_item_mesh: 
			tp_held_item_mesh.visible = false
			tp_held_item_mesh.mesh = null
		held_torch_root.visible = false
		if tp_held_torch_root: tp_held_torch_root.visible = false
		_hand_light_ref.visible = false
		_viewmodel_light_ref.visible = false
		return
	
	if item.type == 9: # Torch
		held_item_mesh.visible = false
		held_item_mesh.mesh = null
		if tp_held_item_mesh: 
			tp_held_item_mesh.visible = false
			tp_held_item_mesh.mesh = null
			
		_hand_light_ref.visible = true
		# Set light to ONLY hit World (Layer 1) and Decorations (Layer 4)
		# This explicitly ignores Layer 2 (Viewmodel) and Layer 3 (Player)
		# This ensures the held light cannot cast a shadow of any player model parts.
		_hand_light_ref.light_cull_mask = 1 | 8
		
		# First Person handling
		if is_fp:
			held_torch_root.visible = true
			if tp_held_torch_root: tp_held_torch_root.visible = false
			
			if hand_torch_mesh and world.torch_mesh:
				hand_torch_mesh.mesh = world.torch_mesh
				hand_torch_mesh.material_override = world.torch_material
				hand_torch_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				hand_torch_mesh.layers = 2 # Viewmodel Layer
				hand_torch_mesh.scale = Vector3.ONE * 0.8
				hand_torch_mesh.visible = true
			
			# Parent world light to the camera (main world) so it lights chunks,
			# but position it to match the hand torch.
			if _hand_light_ref.get_parent() != camera:
				_hand_light_ref.reparent(camera, false)
			# Approximate the hand position relative to camera
			_hand_light_ref.position = Vector3(0.5, -0.3, -0.5)
			
			# Position and enable viewmodel light (this only hits the hand/torch)
			_viewmodel_light_ref.visible = true
			_viewmodel_light_ref.global_position = hand_torch_mesh.global_position
			
		# Third Person handling
		else:
			held_torch_root.visible = false
			if hand_torch_mesh: hand_torch_mesh.visible = false
			_viewmodel_light_ref.visible = false
			
			if tp_held_torch_root:
				tp_held_torch_root.visible = true
				
				if tp_held_torch_mesh and world.torch_mesh:
					tp_held_torch_mesh.mesh = world.torch_mesh
					tp_held_torch_mesh.material_override = world.torch_material
					tp_held_torch_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					tp_held_torch_mesh.layers = 4 # Layer 3
					tp_held_torch_mesh.visible = true
				
				# Parent light to TP root
				if _hand_light_ref.get_parent() != tp_held_torch_root:
					_hand_light_ref.reparent(tp_held_torch_root, false)
				_hand_light_ref.position = Vector3(0, 0.5, 0) # Relative to TP root
	else:
		held_torch_root.visible = false
		if hand_torch_mesh: hand_torch_mesh.visible = false
		if tp_held_torch_root: tp_held_torch_root.visible = false
		if tp_held_torch_mesh: tp_held_torch_mesh.visible = false
		_hand_light_ref.visible = false
		_viewmodel_light_ref.visible = false

		# Handle regular blocks
		var type = item.type
		var block_mesh = _generate_block_mesh(type)
		var mat = _get_block_material(type)
		
		# FP Mesh
		held_item_mesh.visible = is_fp
		held_item_mesh.mesh = block_mesh
		held_item_mesh.material_override = mat
		held_item_mesh.layers = 2
		held_item_mesh.scale = Vector3.ONE * 0.4
		
		# TP Mesh
		if tp_held_item_mesh:
			tp_held_item_mesh.visible = not is_fp
			tp_held_item_mesh.mesh = block_mesh
			tp_held_item_mesh.material_override = mat
			tp_held_item_mesh.layers = 4 # Layer 3
			tp_held_item_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Scale is now controlled entirely by the editor transform on the mesh node

func _get_block_material(type: int) -> Material:
	if world and world.materials.has(type):
		return world.materials[type]
	return StandardMaterial3D.new()

func _generate_block_mesh(_type: int) -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var faces = [
		{"dir": Vector3.UP, "verts": [Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.DOWN, "verts": [Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5)], "uvs": [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]},
		{"dir": Vector3.LEFT, "verts": [Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.RIGHT, "verts": [Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.FORWARD, "verts": [Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
		{"dir": Vector3.BACK, "verts": [Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)], "uvs": [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]},
	]
	
	for face in faces:
		st.set_normal(face.dir)
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(face.uvs[i])
			st.add_vertex(face.verts[i])
	
	return st.commit()

var _debug_timer = 0.0

func _process(delta):
	_debug_timer += delta
	if _debug_timer > 2.0:
		_debug_timer = 0.0
		if view_model_arm:
			print("DEBUG: ViewModelArm pos: ", view_model_arm.position, " visible: ", view_model_arm.visible, " parent: ", view_model_arm.get_parent().name)
	
	_update_swing(delta)
	_update_selection_box()
	_animate_walk(delta)
	_update_view_model(delta)

	# Synchronize view model camera
	if view_model_camera:
		view_model_camera.global_transform = camera.global_transform
		view_model_camera.fov = 85 # Increased FOV to make the hand look smaller and further away

	# Fallback safety: If we are stuck in a block, reset fall damage to prevent unfair death
	if get_last_slide_collision() != null and not is_on_floor() and velocity.length() < 1.0:
		_fall_start_y = global_position.y

func _update_swing(delta):
	if is_swinging:
		swing_progress += delta * SWING_SPEED
		if swing_progress >= 1.0:
			is_swinging = false
			swing_progress = 0.0

func swing():
	is_swinging = true
	swing_progress = 0.0

func _update_view_model(_delta = 0.0):
	if not view_model_arm: return
	
	if current_camera_mode == CameraMode.FIRST_PERSON:
		view_model_arm.visible = true
		view_model_arm.scale = Vector3.ONE
		# Position slightly lower and further away
		view_model_base_pos = Vector3(0.4, -0.5, -0.8)
	else:
		view_model_arm.visible = false

func _animate_walk(delta):
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	idle_time += delta
	
	var item = inventory.hotbar[selected_slot]
	var is_holding = item != null

	if horizontal_speed > 0.1:
		walk_time += delta * horizontal_speed * 2.5
	else:
		walk_time = move_toward(walk_time, 0.0, delta * 10.0)
	
	# View model bobbing & swing
	if view_model_arm:
		var swing_rot = 0.0
		var swing_pos = Vector3.ZERO
		if is_swinging:
			# Simple punch-like curve
			var s = sin(swing_progress * PI)
			swing_rot = -s * 0.5
			swing_pos = Vector3(0, s * 0.1, -s * 0.2)
		
		view_model_arm.position.x = lerp(view_model_arm.position.x, view_model_base_pos.x + swing_pos.x, delta * 10.0)
		view_model_arm.position.y = lerp(view_model_arm.position.y, view_model_base_pos.y + swing_pos.y, delta * 10.0)
		view_model_arm.position.z = lerp(view_model_arm.position.z, view_model_base_pos.z + swing_pos.z, delta * 10.0)
		view_model_arm.rotation.x = lerp(view_model_arm.rotation.x, view_model_base_rot.x + swing_rot, delta * 15.0)

	if horizontal_speed > 0.1:
		var angle = sin(walk_time) * 0.6
		
		right_leg.rotation = Vector3(-angle, 0, 0)
		left_leg.rotation = Vector3(angle, 0, 0)
		
		# 3rd person arm swing
		if is_swinging:
			var s = sin(swing_progress * PI)
			right_arm.rotation = Vector3(-s * -0.8, 0, 0)
		else:
			if is_holding:
				right_arm.rotation = Vector3(0.3 + (angle * 0.3), 0, 0)
			else:
				right_arm.rotation = Vector3(angle, 0, 0)
			
		left_arm.rotation = Vector3(-angle, 0, 0)
	else:
		# Idle / Neutral pose (applies on floor and in air)
		var breathe = sin(idle_time * 1.5) * 0.05
		var sway = cos(idle_time * 0.7) * 0.02
		
		for part in [right_leg, left_leg]:
			if part:
				part.rotation.x = move_toward(part.rotation.x, 0, delta * 5.0)
				part.rotation.y = move_toward(part.rotation.y, 0, delta * 5.0)
				part.rotation.z = move_toward(part.rotation.z, 0, delta * 5.0)
		
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, breathe, delta * 5.0)
			left_arm.rotation.z = lerp(left_arm.rotation.z, -abs(sway), delta * 5.0)
		
		if is_swinging:
			var s = sin(swing_progress * PI)
			right_arm.rotation = Vector3(-s * -0.8, 0, 0)
		elif right_arm:
			var target_x = 0.3 + breathe if is_holding else breathe
			right_arm.rotation.x = lerp(right_arm.rotation.x, target_x, delta * 5.0)
			right_arm.rotation.z = lerp(right_arm.rotation.z, abs(sway), delta * 5.0)

func _update_selection_box():
	if raycast.is_colliding() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var col_pos = raycast.get_collision_point()
		var col_normal = raycast.get_collision_normal()
		
		# Current block selection box (Black wireframe)
		var look_pos = col_pos - col_normal * 0.5
		var look_block_pos = Vector3i(floor(look_pos.x), floor(look_pos.y), floor(look_pos.z))
		var look_type = world.get_block(look_block_pos)
		
		if look_type >= 0:
			selection_box.global_position = Vector3(look_block_pos) + Vector3(0.5, 0.5, 0.5)
			selection_box.visible = true
			return
			
	selection_box.visible = false

func _unhandled_input(event):
	if get_tree().paused: return
	if event.is_action_pressed("ui_cancel"):
		if inventory_ui and inventory_ui.main_inventory_panel.visible:
			inventory_ui.toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		if chat_ui and chat_ui.is_chat_active():
			chat_ui.close_chat()
			get_viewport().set_input_as_handled()
			return
		if pause_menu: 
			pause_menu.open()
		return
	
	if chat_ui and chat_ui.is_chat_active():
		return

	if (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		inventory_ui.toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	
	# Camera mode toggle (F5)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		current_camera_mode = ((current_camera_mode + 1) % 3) as CameraMode
		_update_camera_mode()
		get_viewport().set_input_as_handled()
		return
	
	# Chat opening
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_T or event.keycode == KEY_ENTER:
			if not inventory_ui.main_inventory_panel.visible:
				chat_ui.open_chat()
				get_viewport().set_input_as_handled()
				return
	
	# Debug health
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE and not event.is_echo():
			var state = get_node_or_null("/root/GameState")
			if state and state.gamemode == state.GameMode.CREATIVE:
				var current_time = Time.get_ticks_msec() / 1000.0
				if current_time - _last_jump_press_time < DOUBLE_TAP_TIME:
					is_flying = !is_flying
					if is_flying:
						velocity.y = 0
					_last_jump_press_time = -1.0 # Reset
				else:
					_last_jump_press_time = current_time
		
		if event.keycode == KEY_H:
			health -= 1
			return
		if event.keycode == KEY_J:
			health += 1
			return

	# Manual item drop
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		inventory.drop_single(selected_slot, true, global_position + Vector3(0, 1.5, 0), -camera.global_transform.basis.z, world)
		get_viewport().set_input_as_handled()
		return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pitch -= event.relative.y * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch, -PI/2, PI/2)
		
		_apply_rotations()
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: _break_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT: _place_block()
		elif event.button_index == MOUSE_BUTTON_MIDDLE: _pick_block()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			selected_slot = (selected_slot - 1 + 9) % 9
			inventory_ui.set_selected(selected_slot)
			_update_held_item_mesh()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			selected_slot = (selected_slot + 1) % 9
			inventory_ui.set_selected(selected_slot)
			_update_held_item_mesh()
	
	if event is InputEventKey and event.pressed:
		for i in range(9):
			if event.keycode == KEY_1 + i:
				selected_slot = i
				inventory_ui.set_selected(selected_slot)
				_update_held_item_mesh()

func _apply_rotations():
	if head_node:
		head_node.rotation.x = camera_pitch
	
	if raycast_pivot:
		raycast_pivot.rotation.x = camera_pitch
	
	if current_camera_mode == CameraMode.THIRD_PERSON_FRONT:
		# In front view, the spring arm is rotated 180 degrees on Y.
		# This inverts the X axis relative to the player, so we must invert the pitch.
		spring_arm.rotation.x = -camera_pitch
	else:
		spring_arm.rotation.x = camera_pitch
		if raycast_pivot:
			raycast_pivot.rotation.y = 0

func _pick_block():
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var pos = raycast.get_collision_point() - raycast.get_collision_normal() * 0.5
		var block_pos = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		
		if collider is StaticBody3D and collider.collision_layer == 4:
			block_pos = Vector3i(floor(collider.global_position.x), floor(collider.global_position.y), floor(collider.global_position.z))
		
		var block_type = world.get_block(block_pos)
		
		if block_type >= 0:
			var state_gm = get_node_or_null("/root/GameState")
			if state_gm and state_gm.gamemode == state_gm.GameMode.CREATIVE:
				# 1. Check if already in hotbar
				var found_hotbar_idx = -1
				for i in range(inventory.HOTBAR_SIZE):
					if inventory.hotbar[i] and inventory.hotbar[i].type == block_type:
						found_hotbar_idx = i
						break
				
				if found_hotbar_idx != -1:
					selected_slot = found_hotbar_idx
				else:
					# 2. Look for empty hotbar slot
					var empty_hotbar_idx = -1
					for i in range(inventory.HOTBAR_SIZE):
						if inventory.hotbar[i] == null:
							empty_hotbar_idx = i
							break
					
					if empty_hotbar_idx != -1:
						inventory.hotbar[empty_hotbar_idx] = {"type": block_type, "count": 1}
						selected_slot = empty_hotbar_idx
					else:
						# 3. Hotbar is full. Replace selected and move old to inventory.
						var old_item = inventory.hotbar[selected_slot]
						inventory.hotbar[selected_slot] = {"type": block_type, "count": 1}
						if old_item:
							# Try to put old_item in inventory (returns false if full, effectively deleting it)
							inventory.add_item(old_item.type, old_item.count)
				
				inventory_ui.set_selected(selected_slot)
				inventory.inventory_changed.emit()
				_update_held_item_mesh()
			else:
				var new_slot = inventory.pick_block(block_type, selected_slot)
				if new_slot != -1:
					selected_slot = new_slot
					inventory_ui.set_selected(selected_slot)
					_update_held_item_mesh()

func _break_block():
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var block_pos: Vector3i
		
		if collider is StaticBody3D and collider.collision_layer == 4:
			# We hit a torch collision box
			# Torch collisions are children of the deco_node, which is a child of the chunk.
			# But we placed the collision shape directly at the torch's center.
			# However, getting the position from the shape index is complex.
			# Easier: use the hit point and normal to find the block center.
			var pos = raycast.get_collision_point() - raycast.get_collision_normal() * 0.1
			block_pos = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		else:
			# Standard block
			var pos = raycast.get_collision_point() - raycast.get_collision_normal() * 0.1
			block_pos = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		
		var block_type = world.get_block(block_pos)
		
		var state_gm = get_node_or_null("/root/GameState")
		var is_creative_mode = state_gm and state_gm.gamemode == state_gm.GameMode.CREATIVE
		
		if block_type >= 0 and (block_type != 4 or is_creative_mode): # Not air and (not bedrock or creative)
			swing()
			
			if not is_creative_mode:
				inventory.spawn_dropped_item(block_type, 1, Vector3(block_pos) + Vector3(0.5, 0.5, 0.5), world)
			
			world.remove_block(block_pos)

func _place_block():
	var item = inventory.hotbar[selected_slot]
	if not item: return
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		# Don't allow placing blocks inside or against torches
		if collider is StaticBody3D and collider.collision_layer == 4:
			return
			
		var pos = raycast.get_collision_point() + raycast.get_collision_normal() * 0.5
		var block_pos = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		
		# Prevent placing inside a torch that we might have missed hitting directly
		if world.get_block(block_pos) == 9:
			return
		
		# Check if the block position overlaps with the player's hitbox
		# We use a smaller block AABB to allow placing while standing on the edge
		var block_aabb = AABB(Vector3(block_pos) + Vector3(0.1, 0.1, 0.1), Vector3(0.8, 0.8, 0.8))
		# Player AABB for placement: smaller than physical hitbox to avoid "edge blocking"
		var player_aabb = AABB(global_position + Vector3(-0.1, -0.9, -0.1), Vector3(0.2, 1.7, 0.2))
		
		if player_aabb.intersects(block_aabb):
			return

		swing()

		if world.has_method("set_block"):
			world.set_block(block_pos, item.type)
			if world.has_method("play_place_sound"):
				world.play_place_sound(Vector3(block_pos), item.type)
			var state_gm = get_node_or_null("/root/GameState")
			if not state_gm or state_gm.gamemode != state_gm.GameMode.CREATIVE:
				item.count -= 1
				if item.count <= 0: inventory.hotbar[selected_slot] = null
				inventory.inventory_changed.emit()

func _get_surface_friction():
	if not is_on_floor(): return 1.0 # Air
	if world:
		var below_pos = Vector3i(floor(global_position.x), floor(global_position.y - 0.1), floor(global_position.z))
		var _block_type = world.get_block(below_pos)
		# Future: check for ice (type 9 etc)
		# For now, everything is normal ground
		return 0.6
	return 0.6

func _update_camera_mode():
	# Eye height relative to player root
	# Feet are at -0.99 (PlayerModel position)
	# Center of head is roughly 0.6 - 0.7
	var base_pos = Vector3(0, 0.65, 0) 
	
	spring_arm.position = base_pos
	camera.scale = Vector3.ONE # Ensure no distortion
	
	# Adjust camera local Y so first person eye level remains correct
	# Target total height is ~0.94 (0.2 + 0.74 from previous version)
	camera.position.y = 0.94 - 0.65
	
	match current_camera_mode:
		CameraMode.FIRST_PERSON:
			_set_model_visible(false)
			spring_arm.spring_length = 0.05
			spring_arm.rotation.y = 0
			spring_arm.collision_mask = 1
			if crosshair: crosshair.visible = true
		CameraMode.THIRD_PERSON_BACK:
			_set_model_visible(true)
			spring_arm.spring_length = 4.0
			spring_arm.rotation.y = 0
			spring_arm.collision_mask = 1
			if crosshair: crosshair.visible = false
		CameraMode.THIRD_PERSON_FRONT:
			_set_model_visible(true)
			spring_arm.spring_length = 4.0
			spring_arm.rotation.y = PI
			spring_arm.collision_mask = 1
			if crosshair: crosshair.visible = false
	
	_update_held_item_mesh()
	_apply_rotations()

func _set_model_visible(v: bool):
	var nodes_to_check = player_model.find_children("*", "VisualInstance3D", true)
	if player_model is VisualInstance3D:
		nodes_to_check.append(player_model)
		
	for child in nodes_to_check:
		# Don't hide the viewmodel (descendant of camera)
		if camera.is_ancestor_of(child):
			child.visible = true
			if child is GeometryInstance3D:
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			continue
			
		if not v:
			# In first person, hide the mesh from the camera but keep it for shadows
			if child is GeometryInstance3D:
				child.visible = true
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			else:
				child.visible = false
		else:
			child.visible = true
			if child is GeometryInstance3D:
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _physics_process(delta):
	if chat_ui and chat_ui.is_chat_active():
		velocity.x = move_toward(velocity.x, 0, 60.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 60.0 * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	var in_water = false
	var head_in_water = false
	if world:
		var head_pos = Vector3i(floor(camera.global_position.x), floor(camera.global_position.y), floor(camera.global_position.z))
		var feet_pos = Vector3i(floor(global_position.x), floor(global_position.y), floor(global_position.z))
		head_in_water = world.get_block(head_pos) == 7 or world.get_block(head_pos) == 8
		if head_in_water or world.get_block(feet_pos) == 7 or world.get_block(feet_pos) == 8:
			in_water = true

	# Gravity
	if not is_on_floor() and not is_flying:
		if in_water:
			velocity.y -= gravity * 0.1 * delta
			velocity.y = max(velocity.y, -2.0) 
		else:
			velocity.y -= gravity * delta

	# Jump / Swim / Fly
	var is_sprinting = Input.is_key_pressed(KEY_CTRL)

	if is_flying:
		var v_dir = 0.0
		if Input.is_action_pressed("jump"): v_dir += 1.0
		if Input.is_action_pressed("sneak"): v_dir -= 1.0
		
		var target_v_speed = v_dir * (FLY_SPRINT_SPEED if is_sprinting else FLY_SPEED)
		velocity.y = move_toward(velocity.y, target_v_speed, delta * FLY_SPEED * 5.0)
	else:
		if Input.is_action_pressed("jump"):
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
			elif in_water:
				velocity.y = 6.0 
				if not head_in_water: velocity.y = 9.0 

	# Input Direction
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_left"): input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"): input_dir.x += 1.0
	if Input.is_action_pressed("move_forward"): input_dir.y -= 1.0
	if Input.is_action_pressed("move_back"): input_dir.y += 1.0
	
	var target_speed = SPRINT_SPEED if is_sprinting else SPEED
	if is_flying:
		target_speed = FLY_SPRINT_SPEED if is_sprinting else FLY_SPEED
	
	var move_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var horizontal_vel = Vector2(velocity.x, velocity.z)
	
	if is_flying:
		var fly_accel = 60.0 if move_dir.length() > 0 else 40.0
		var target_h_vel = Vector2(move_dir.x, move_dir.z) * target_speed
		horizontal_vel = horizontal_vel.move_toward(target_h_vel, fly_accel * delta)
	elif in_water:
		var water_accel = 15.0
		var target_h_vel = Vector2(move_dir.x, move_dir.z) * target_speed * 0.6
		horizontal_vel = horizontal_vel.move_toward(target_h_vel, water_accel * delta)
		
		if not Input.is_action_pressed("jump") and not is_on_floor():
			velocity.y = move_toward(velocity.y, -1.0, 5.0 * delta)
	elif is_on_floor():
		var accel = 80.0 # High acceleration for precision
		var friction = 60.0 # High friction for snappiness
		
		if move_dir.length() > 0:
			var target_h_vel = Vector2(move_dir.x, move_dir.z) * target_speed
			horizontal_vel = horizontal_vel.move_toward(target_h_vel, accel * delta)
		else:
			horizontal_vel = horizontal_vel.move_toward(Vector2.ZERO, friction * delta)
	else:
		# Air control
		var air_accel = 25.0
		var air_friction = 5.0
		
		if move_dir.length() > 0:
			var target_h_vel = Vector2(move_dir.x, move_dir.z) * target_speed
			horizontal_vel = horizontal_vel.move_toward(target_h_vel, air_accel * delta)
		else:
			horizontal_vel = horizontal_vel.move_toward(Vector2.ZERO, air_friction * delta)

	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.y

	# Minecraft-style Fall Damage (Distance based)
	var fall_damage_reset = is_on_floor() or in_water or (get_last_slide_collision() != null and velocity.length() < 0.5)
	
	if fall_damage_reset:
		if _fall_start_y > global_position.y:
			var fall_dist = _fall_start_y - global_position.y
			if fall_dist > 3.5 and not in_water: # 3 blocks safe, take damage on 4th
				var damage = floor(fall_dist - 3.0)
				if damage > 0:
					var state_gm = get_node_or_null("/root/GameState")
					var is_creative_mode = state_gm and state_gm.gamemode == state_gm.GameMode.CREATIVE
					
					if not is_creative_mode:
						_play_fall_sound(fall_dist)
						health -= damage
		_fall_start_y = global_position.y
	else:
		# If we are moving up, reset fall start to current height
		if velocity.y > 0 or global_position.y > _fall_start_y:
			_fall_start_y = global_position.y

	_was_on_floor = is_on_floor()

	move_and_slide()
	_handle_stuck(delta)
	
	# Void Damage
	if global_position.y < -20.0:
		_void_damage_timer += delta
		if _void_damage_timer >= 0.5:
			var state_gm = get_node_or_null("/root/GameState")
			if state_gm and state_gm.gamemode == state_gm.GameMode.CREATIVE:
				health = 0 # Creative players die to void
			else:
				health -= 4
			_void_damage_timer = 0.0
	else:
		_void_damage_timer = 0.0

func _handle_stuck(_delta):
	if not world: return
	
	# Check points at feet, waist, and head level
	# We use smaller offsets to ensure we are actually INSIDE the block
	var check_offsets = [
		Vector3(0, -0.5, 0), Vector3(0, 0, 0), Vector3(0, 0.5, 0),
		Vector3(0.1, 0, 0), Vector3(-0.1, 0, 0),
		Vector3(0, 0, 0.1), Vector3(0, 0, -0.1)
	]
	
	var stuck_block_pos = Vector3i.ZERO
	var is_stuck = false
	
	for offset in check_offsets:
		var p = global_position + offset
		var block_pos = Vector3i(floor(p.x), floor(p.y), floor(p.z))
		var type = world.get_block(block_pos)
		if type >= 0 and type != 7 and type != 8 and type != 9: # Ignore Air, Water, and Torches
			stuck_block_pos = block_pos
			is_stuck = true
			break
	
	if is_stuck:
		var bc = Vector3(stuck_block_pos) + Vector3(0.5, 0.5, 0.5)
		var diff = global_position - bc
		if diff.length_squared() < 0.001: diff = Vector3(1, 0, 0)
		
		var abs_diff = diff.abs()
		# Match the actual collision shape radius (0.16) plus a small buffer
		var player_radius = 0.18 
		var player_half_height = 0.9
		
		if abs_diff.x > abs_diff.y and abs_diff.x > abs_diff.z:
			global_position.x = bc.x + sign(diff.x) * (0.5 + player_radius + 0.01)
			velocity.x = 0
		elif abs_diff.y > abs_diff.x and abs_diff.y > abs_diff.z:
			global_position.y = bc.y + sign(diff.y) * (0.5 + player_half_height + 0.01)
			velocity.y = 0
		else:
			global_position.z = bc.z + sign(diff.z) * (0.5 + player_radius + 0.01)
			velocity.z = 0
