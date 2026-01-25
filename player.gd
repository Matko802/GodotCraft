extends CharacterBody3D

const SPEED = 4.3
const SPRINT_SPEED = 5.6
const JUMP_VELOCITY = 8.5
const MOUSE_SENSITIVITY = 0.002

@onready var camera = $SpringArm3D/Camera3D
@onready var spring_arm = $SpringArm3D
@onready var raycast = $SpringArm3D/Camera3D/RayCast3D
@onready var inventory = $Inventory
@onready var inventory_ui = $HUD/InventoryUI
@onready var chat_ui = $HUD/ChatUI
@onready var crosshair = $HUD/CrosshairContainer
@onready var pause_menu = $PauseLayer/PauseMenu
@onready var player_model = $PlayerModel

@onready var view_model_arm = $SpringArm3D/Camera3D/ViewModelArm
@onready var slim_hand = $SpringArm3D/Camera3D/ViewModelArm/SlimHandModel
@onready var wide_hand = $SpringArm3D/Camera3D/ViewModelArm/WideHandModel
@onready var held_item_mesh = $SpringArm3D/Camera3D/ViewModelArm/HeldItemRoot/HeldItemMesh
@onready var view_model_anim = $ViewModelAnimationPlayer

@onready var tp_held_item_mesh = $TPHeldItemRoot/TPHeldItemMesh
@onready var tp_held_item_root = $TPHeldItemRoot

@onready var right_arm = $PlayerModel/Waist/"Right Arm2"
@onready var left_arm = $PlayerModel/Waist/"Left Arm2"
@onready var right_leg = $"PlayerModel/Right Leg2"
@onready var left_leg = $"PlayerModel/Left Leg2"

var walk_time = 0.0
var is_swinging = false
var swing_progress = 0.0
const SWING_SPEED = 8.0

@onready var head_node = null

signal health_changed(new_health)

var max_health = 20
var health = 20:
	set(value):
		if value < health:
			_play_damage_sound()
		health = clamp(value, 0, max_health)
		health_changed.emit(health)
		if health <= 0:
			_die()

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

@onready var raycast_pivot: Node3D = null

func _ready():
	add_to_group("player")
	collision_layer = 2 # Player on layer 2
	collision_mask = 1  # Collide with world (layer 1)
	print("Player ready. World: ", get_parent().name)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	world = get_parent()
	
	_setup_selection_box()
	_setup_player_model()
	
	if inventory_ui:
		inventory_ui.setup(self)
	
	_setup_view_model()
	_update_view_model()
	
	if inventory:
		if not inventory.inventory_changed.is_connected(_update_held_item_mesh):
			inventory.inventory_changed.connect(_update_held_item_mesh)
	
	# Create a RayCast pivot at eye level that doesn't move with the SpringArm's spring
	raycast_pivot = Node3D.new()
	raycast_pivot.name = "RayCastPivot"
	add_child(raycast_pivot)
	raycast_pivot.position = Vector3(0, 0.7, 0) # Eye level
	
	raycast.reparent(raycast_pivot)
	raycast.position = Vector3.ZERO
	raycast.rotation = Vector3.ZERO
	raycast.add_exception(self)
	# Set RayCast mask to only hit the world (layer 1)
	raycast.collision_mask = 1
	
	# Ensure SpringArm ignores the player
	spring_arm.add_excluded_object(get_rid())
	
	_update_camera_mode()
	_apply_rotations()
	
	var state = get_node_or_null("/root/GameState")
	if state:
		state.settings_changed.connect(_on_settings_changed)
		_on_settings_changed() # Initialize FOV

var camera_pitch = 0.0

func _setup_player_model():
	var state = get_node_or_null("/root/GameState")
	var is_slim = state.is_slim if state else false
	var tex_path = state.custom_texture_path if state and state.custom_texture_path != "" else ("res://models/player/slim/model_0.png" if is_slim else "res://models/player/wide/model_0.png")
	
	# Find body parts for animation
	right_arm = player_model.find_child("Right Arm2", true)
	left_arm = player_model.find_child("Left Arm2", true)
	right_leg = player_model.find_child("Right Leg2", true)
	left_leg = player_model.find_child("Left Leg2", true)
	
	# Reset any inherited bone/part rotations to ensure they are straight
	if right_arm: right_arm.quaternion = Quaternion.IDENTITY
	if left_arm: left_arm.quaternion = Quaternion.IDENTITY
	if right_leg: right_leg.quaternion = Quaternion.IDENTITY
	if left_leg: left_leg.quaternion = Quaternion.IDENTITY

	# Replace model if type changed
	var model_path = "res://models/player/slim/model.gltf" if is_slim else "res://models/player/wide/model.gltf"
	
	# Use metadata or name check to ensure we don't duplicate
	var current_path = player_model.scene_file_path
	if current_path != model_path:
		print("Swapping player model from ", current_path, " to ", model_path)
		var new_model = load(model_path).instantiate()
		new_model.name = "PlayerModel"
		
		# Transfer transform
		new_model.transform = player_model.transform
		
		var parent = player_model.get_parent()
		parent.add_child(new_model)
		
		# Re-find body parts for animation BEFORE freeing old ones
		right_arm = new_model.find_child("Right Arm2", true)
		left_arm = new_model.find_child("Left Arm2", true)
		right_leg = new_model.find_child("Right Leg2", true)
		left_leg = new_model.find_child("Left Leg2", true)
		var new_head = new_model.find_child("Head2", true)
		if not new_head: new_head = new_model.find_child("Head", true)
		
		# Ensure we don't parent camera to a mesh that might be hidden
		if new_head is MeshInstance3D:
			var p = new_head.get_parent()
			if p and not p is MeshInstance3D:
				new_head = p
		
		# Update camera parent if it was on the old head
		if head_node and camera.get_parent() == head_node:
			camera.reparent(new_head)
			camera.position = Vector3(0, 0, 0.1)
			camera.rotation = Vector3.ZERO
		
		head_node = new_head
		
		# Clean up old model
		player_model.queue_free()
		player_model = new_model
		
		# Reset any inherited bone/part rotations
		right_arm.rotation = Vector3.ZERO
		left_arm.rotation = Vector3.ZERO
		right_leg.rotation = Vector3.ZERO
		left_leg.rotation = Vector3.ZERO

	# Setup Third Person held item attachment from scene
	if right_arm and tp_held_item_root:
		tp_held_item_root.reparent(right_arm)
		# We no longer overwrite position/rotation here so editor changes persist
		tp_held_item_mesh.scale = Vector3.ONE * 0.8 # Slightly smaller for TP

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
	
	for child in player_model.find_children("*", "MeshInstance3D"):
		child.material_override = mat
	
	# Final check on visibility
	_update_camera_mode()

func _on_settings_changed():
	var state = get_node_or_null("/root/GameState")
	if state:
		camera.fov = state.fov

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
	selection_box.material_override = mat
	add_child(selection_box)
	selection_box.top_level = true
	selection_box.visible = false

func _setup_view_model():
	if not view_model_arm: return
	
	var state = get_node_or_null("/root/GameState")
	var is_slim = state.is_slim if state else false
	
	# Toggle hands based on slim setting
	slim_hand.visible = is_slim
	wide_hand.visible = not is_slim
	
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
			child.layers = 1 | 2
			
	_update_held_item_mesh()

func _update_held_item_mesh():
	var item = inventory.hotbar[selected_slot]
	if not item:
		held_item_mesh.visible = false
		if tp_held_item_mesh: tp_held_item_mesh.visible = false
		return
	
	held_item_mesh.visible = current_camera_mode == CameraMode.FIRST_PERSON
	if tp_held_item_mesh: 
		tp_held_item_mesh.visible = current_camera_mode != CameraMode.FIRST_PERSON

	# Re-use block mesh logic
	var type = item.type
	var mesh = ArrayMesh.new()
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
			st.add_vertex(face.verts[i] * 0.4) # Scaling for hand
	
	var final_mesh = st.commit()
	held_item_mesh.mesh = final_mesh
	if tp_held_item_mesh:
		tp_held_item_mesh.mesh = final_mesh
	
	# Material logic for held block (re-use from world or simplified)
	var shader = load("res://viewmodel_voxel.gdshader")
	var smat = ShaderMaterial.new()
	smat.shader = shader
	
	if type == 2: # Grass
		smat.set_shader_parameter("top_texture", load("res://textures/grass_top.png"))
		smat.set_shader_parameter("side_texture", load("res://textures/grass_side.png"))
		smat.set_shader_parameter("bottom_texture", load("res://textures/dirt.png"))
	elif type == 5: # Wood
		smat.set_shader_parameter("top_texture", load("res://textures/oak_wood_top.png"))
		smat.set_shader_parameter("side_texture", load("res://textures/oak_wood_side.png"))
		smat.set_shader_parameter("bottom_texture", load("res://textures/oak_wood_top.png"))
	else:
		var tex = world.BLOCK_TEXTURES.get(type, load("res://textures/stone.png"))
		if tex is String: tex = load(tex)
		smat.set_shader_parameter("top_texture", tex)
		smat.set_shader_parameter("side_texture", tex)
		smat.set_shader_parameter("bottom_texture", tex)
	
	held_item_mesh.material_override = smat
	held_item_mesh.layers = 1 | 2
	held_item_mesh.position = Vector3(0.1, -0.1, -0.2) # Relative to arm/hand
	
	if tp_held_item_mesh:
		var tp_smat = smat.duplicate()
		tp_smat.shader = load("res://voxel.gdshader") # Regular world shader
		tp_held_item_mesh.material_override = tp_smat
		# Note: We don't set layers for TP mesh, it should use default (Layer 1)

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
		# It's already a child of the camera, so it moves with it automatically
	else:
		view_model_arm.visible = false

func _animate_walk(delta):
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	# View model bobbing & swing
	if view_model_arm:
		var bob_amount = 0.0
		var bob_offset_y = 0.0
		if is_on_floor() and horizontal_speed > 0.1:
			bob_amount = sin(walk_time * 1.5) * 0.02
			bob_offset_y = abs(sin(walk_time * 1.5)) * 0.01
		
		var swing_rot = 0.0
		var swing_pos = Vector3.ZERO
		if is_swinging:
			# Simple punch-like curve
			var s = sin(swing_progress * PI)
			swing_rot = -s * 0.5
			swing_pos = Vector3(0, s * 0.1, -s * 0.2)
		
		view_model_arm.position.x = lerp(view_model_arm.position.x, bob_amount + swing_pos.x, delta * 10.0)
		view_model_arm.position.y = lerp(view_model_arm.position.y, -bob_offset_y + swing_pos.y, delta * 10.0)
		view_model_arm.position.z = lerp(view_model_arm.position.z, swing_pos.z, delta * 10.0)
		view_model_arm.rotation.x = lerp(view_model_arm.rotation.x, swing_rot, delta * 15.0)

	if is_on_floor() and horizontal_speed > 0.1:
		walk_time += delta * horizontal_speed * 2.5
		var angle = sin(walk_time) * 0.6
		
		right_leg.rotation = Vector3(-angle, 0, 0)
		left_leg.rotation = Vector3(angle, 0, 0)
		
		# 3rd person arm swing
		if is_swinging:
			var s = sin(swing_progress * PI)
			right_arm.rotation = Vector3(-s * 0.8, 0, 0)
		else:
			right_arm.rotation = Vector3(angle, 0, 0)
			
		left_arm.rotation = Vector3(-angle, 0, 0)
	else:
		walk_time = move_toward(walk_time, 0.0, delta * 10.0)
		for part in [right_leg, left_leg, left_arm]:
			if part:
				part.rotation.x = move_toward(part.rotation.x, 0, delta * 5.0)
				part.rotation.y = move_toward(part.rotation.y, 0, delta * 5.0)
				part.rotation.z = move_toward(part.rotation.z, 0, delta * 5.0)
		
		if is_swinging:
			var s = sin(swing_progress * PI)
			right_arm.rotation = Vector3(-s * 0.8, 0, 0)
		elif right_arm:
			right_arm.rotation.x = move_toward(right_arm.rotation.x, 0, delta * 5.0)
			right_arm.rotation.y = move_toward(right_arm.rotation.y, 0, delta * 5.0)
			right_arm.rotation.z = move_toward(right_arm.rotation.z, 0, delta * 5.0)

func _update_selection_box():
	if raycast.is_colliding() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var pos = raycast.get_collision_point() - raycast.get_collision_normal() * 0.5
		var block_pos_i = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		var block_type = world.get_block(block_pos_i)
		
		# Only show selection box if we are looking at a real block (not air)
		if block_type >= 0:
			selection_box.global_position = Vector3(block_pos_i) + Vector3(0.5, 0.5, 0.5)
			selection_box.visible = true
			return
			
	selection_box.visible = false

func _unhandled_input(event):
	if get_tree().paused: return
	if event.is_action_pressed("ui_cancel"):
		if pause_menu: pause_menu.open()
		return
	
	if chat_ui and chat_ui.is_chat_active():
		return

	if event.is_action_pressed("inventory") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		health -= 1
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_J:
		health += 1
		return

	# Manual item drop
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		if not inventory_ui.main_inventory_panel.visible:
			var look_dir = -raycast_pivot.global_transform.basis.z
			inventory.drop_single(selected_slot, true, global_position + look_dir * 0.5, look_dir, world)
			return

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
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
		var pos = raycast.get_collision_point() - raycast.get_collision_normal() * 0.5
		var block_pos = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		var block_type = world.get_block(block_pos)
		
		if block_type >= 0:
			var new_slot = inventory.pick_block(block_type, selected_slot)
			if new_slot != -1:
				selected_slot = new_slot
				inventory_ui.set_selected(selected_slot)

func _break_block():
	if raycast.is_colliding():
		var pos = raycast.get_collision_point() - raycast.get_collision_normal() * 0.5
		var block_pos = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		var block_type = world.get_block(block_pos)
		
		if block_type >= 0 and block_type != 4: # Not air and not bedrock
			swing()
			
			var state = get_node_or_null("/root/GameState")
			var should_drop = state.rules.get("drop_items", true) if state else true
			
			if should_drop:
				inventory.spawn_dropped_item(block_type, 1, Vector3(block_pos), world)
			
			world.remove_block(block_pos)

func _place_block():
	var item = inventory.hotbar[selected_slot]
	if not item: return
	if raycast.is_colliding():
		var pos = raycast.get_collision_point() + raycast.get_collision_normal() * 0.5
		var block_pos = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))
		
		# Check if the block position overlaps with the player's hitbox
		var block_aabb = AABB(Vector3(block_pos) + Vector3(0.05, 0.05, 0.05), Vector3(0.9, 0.9, 0.9))
		# Player AABB approximate based on collision shape (capsule radius ~0.2, height ~1.8)
		# The player origin is roughly at the center of the capsule
		var player_aabb = AABB(global_position + Vector3(-0.3, -1.0, -0.3), Vector3(0.6, 1.8, 0.6))
		
		if player_aabb.intersects(block_aabb):
			return

		swing()

		if world.has_method("set_block"):
			world.set_block(block_pos, item.type)
			if world.has_method("play_place_sound"):
				world.play_place_sound(Vector3(block_pos), item.type)
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
	var base_pos = Vector3(0, 0.7, 0) 
	
	spring_arm.position = base_pos
	camera.scale = Vector3.ONE # Ensure no distortion
	
	match current_camera_mode:
		CameraMode.FIRST_PERSON:
			_set_model_visible(false)
			spring_arm.spring_length = 0.05
			spring_arm.rotation.y = 0
			spring_arm.collision_mask = 1
			camera.position = Vector3(0, -0.05, 0)
			camera.rotation = Vector3(0, 0, 0)
			if crosshair: crosshair.visible = true
		CameraMode.THIRD_PERSON_BACK:
			_set_model_visible(true)
			spring_arm.spring_length = 4.0
			spring_arm.rotation.y = 0
			spring_arm.collision_mask = 1
			camera.position = Vector3.ZERO
			camera.rotation = Vector3(0, 0, 0)
			if crosshair: crosshair.visible = false
		CameraMode.THIRD_PERSON_FRONT:
			_set_model_visible(true)
			spring_arm.spring_length = 4.0
			spring_arm.rotation.y = PI
			spring_arm.collision_mask = 1
			camera.position = Vector3.ZERO
			camera.rotation = Vector3(0, 0, 0) 
			if crosshair: crosshair.visible = false
	
	_update_held_item_mesh()
	_apply_rotations()

func _set_model_visible(v: bool):
	for child in player_model.find_children("*", "MeshInstance3D"):
		# Don't hide the viewmodel (descendant of camera)
		if camera.is_ancestor_of(child):
			child.visible = true
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			continue
			
		if not v:
			# In First Person, hide meshes from the camera but keep them for shadows
			# This ensures the camera (which is a child) stays active and visible
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			child.visible = true
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
	if not is_on_floor():
		if in_water:
			velocity.y -= gravity * 0.1 * delta
			velocity.y = max(velocity.y, -2.0) 
		else:
			velocity.y -= gravity * delta

	# Jump / Swim
	var is_sprinting = Input.is_key_pressed(KEY_CTRL)
	if Input.is_key_pressed(KEY_SPACE):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		elif in_water:
			velocity.y = 6.0 
			if not head_in_water: velocity.y = 9.0 

	# Input Direction
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	
	# Calculate move direction relative to player rotation
	var move_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target_speed = SPRINT_SPEED if is_sprinting else SPEED
	
	var horizontal_vel = Vector2(velocity.x, velocity.z)
	
	if in_water:
		var water_accel = 15.0
		var target_h_vel = Vector2(move_dir.x, move_dir.z) * target_speed * 0.6
		horizontal_vel = horizontal_vel.move_toward(target_h_vel, water_accel * delta)
		
		if not Input.is_key_pressed(KEY_SPACE) and not is_on_floor():
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
					_play_fall_sound(fall_dist)
					health -= damage
		_fall_start_y = global_position.y
	else:
		# If we are moving up, reset fall start to current height
		if velocity.y > 0 or global_position.y > _fall_start_y:
			_fall_start_y = global_position.y

	_was_on_floor = is_on_floor()

	move_and_slide()
	
	# Void Damage
	if global_position.y < -10.0:
		_void_damage_timer += delta
		if _void_damage_timer >= 1.0:
			health -= 3
			_void_damage_timer = 0.0
	else:
		_void_damage_timer = 0.0
