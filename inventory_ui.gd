extends Control

# FORCE RECOMPILE
# Refreshed
@onready var main_inventory_panel = $MainInventoryPanel
@onready var selection_outline = $SelectionOutline
@onready var floating_item_ui = $FloatingItem
@onready var hearts_container = $HeartsContainer
@onready var hotbar_container = $HotbarPanel/HotbarContainer
@onready var main_inventory_grid = $MainInventoryPanel/InventoryTabs/Inventory/InventoryGridContainer
@onready var main_hotbar_grid = $MainInventoryPanel/InventoryTabs/Inventory/MainHotbarGridContainer
@onready var creative_grid = $MainInventoryPanel/InventoryTabs/Creative/CreativeGridContainer
@onready var tabs = $MainInventoryPanel/InventoryTabs

var slot_scene = preload("res://inventory_slot.tscn")
var inventory_ref = null
var selected_slot = 0
var holding_item = null # { "type": int, "count": int }

var block_textures = {
	0: preload("res://textures/stone.png"),
	1: preload("res://textures/dirt.png"),
	2: preload("res://textures/grass_top.png"),
	3: preload("res://textures/Sand.png"),
	4: preload("res://textures/bedrock.png"),
	5: preload("res://textures/oak_wood_side.png"),
	6: preload("res://textures/leaves.png"),
	7: preload("res://textures/water0.png")
}

var heart_full = preload("res://textures/hearts/heart_full.png")
var heart_half = preload("res://textures/hearts/heart_half.png")

func _ready():
	main_inventory_panel.visible = false
	
	if creative_grid:
		creative_grid.columns = 9
		_setup_creative_inventory()

	# Selection outline settings
	var sel_style = StyleBoxFlat.new()
	sel_style.draw_center = false
	sel_style.border_width_left = 2
	sel_style.border_width_top = 2
	sel_style.border_width_right = 2
	sel_style.border_width_bottom = 2
	sel_style.border_color = Color.WHITE
	sel_style.expand_margin_left = 2
	sel_style.expand_margin_top = 2
	sel_style.expand_margin_right = 2
	sel_style.expand_margin_bottom = 2
	selection_outline.add_theme_stylebox_override("panel", sel_style)
	
	selection_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_outline.custom_minimum_size = Vector2(52, 52)
	selection_outline.z_index = 5
	selection_outline.top_level = true 
	selection_outline.visible = false	
	# Fix for resolution changes
	resized.connect(_update_selection_outline)
	resized.connect(_update_hearts_position)
	var state = get_node_or_null("/root/GameState")
	if state:
		state.settings_changed.connect(_update_selection_outline)
		state.settings_changed.connect(_update_hearts_position)

func _process(_delta):
	if holding_item:
		# Center 48x48 icon on cursor
		floating_item_ui.global_position = get_global_mouse_position() - Vector2(24, 24)

func setup(player):
	inventory_ref = player.inventory
	if not inventory_ref.inventory_changed.is_connected(update_ui):
		inventory_ref.inventory_changed.connect(update_ui)
	
	if player.has_signal("health_changed") and not player.health_changed.is_connected(update_health):
		player.health_changed.connect(update_health)
	
	var state = get_node_or_null("/root/GameState")
	if state and not state.gamemode_changed.is_connected(_on_gamemode_changed):
		state.gamemode_changed.connect(_on_gamemode_changed)
	
	# Clear existing if any
	for child in hotbar_container.get_children(): child.queue_free()
	for child in main_inventory_grid.get_children(): child.queue_free()
	if main_hotbar_grid:
		for child in main_hotbar_grid.get_children(): child.queue_free()
	
	# Create Hotbar slots (the one at the bottom of the screen)
	for i in range(inventory_ref.HOTBAR_SIZE):
		var slot = slot_scene.instantiate()
		hotbar_container.add_child(slot)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.slot_index = i
		slot.is_hotbar_slot = true
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Create Main Inventory slots
	for i in range(inventory_ref.INVENTORY_SIZE):
		var slot = slot_scene.instantiate()
		main_inventory_grid.add_child(slot)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.slot_index = i
		slot.is_hotbar_slot = false
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		
	# Create Main Hotbar slots (the one inside the inventory panel)
	if main_hotbar_grid:
		for i in range(inventory_ref.HOTBAR_SIZE):
			var slot = slot_scene.instantiate()
			main_hotbar_grid.add_child(slot)
			slot.custom_minimum_size = Vector2(48, 48)
			slot.slot_index = i
			slot.is_hotbar_slot = true
			slot.slot_clicked.connect(_on_slot_clicked)
			slot.mouse_filter = Control.MOUSE_FILTER_PASS

	update_ui()
	update_health(player.health)

func _on_gamemode_changed(_new_mode):
	var player = get_tree().get_first_node_in_group("player")
	if player:
		update_health(player.health)
		_update_hearts_position()

func update_health(health):
	var state = get_node_or_null("/root/GameState")
	if (state and state.gamemode == state.GameMode.CREATIVE) or (main_inventory_panel and main_inventory_panel.visible):
		hearts_container.visible = false
		return
	else:
		hearts_container.visible = true

	# Clear existing hearts
	for child in hearts_container.get_children():
		child.queue_free()
	
	# Wait for children to be freed before potentially rebuilding
	# Actually queue_free is enough, we just add new ones.
	
	var heart_size_val = 18
	if hotbar_container.get_child_count() > 0:
		heart_size_val = int(hotbar_container.get_child(0).size.x * 0.375)
		if heart_size_val < 8: heart_size_val = 18 
	
	for i in range(10):
		var heart_val = health - (i * 2)
		if heart_val <= 0:
			# Still add a placeholder or empty heart if we had one, 
			# but here we just stop or show nothing. 
			# To fix "not unhiding" we MUST ensure we add nodes if health > 0.
			continue 
		
		var rect = TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(heart_size_val, heart_size_val)
		rect.texture_filter = Control.TEXTURE_FILTER_NEAREST
		
		if heart_val >= 2:
			rect.texture = heart_full
		elif heart_val == 1:
			rect.texture = heart_half
			
		hearts_container.add_child(rect)
	
	# Force position update
	_update_hearts_position()

func _on_slot_clicked(index, is_hotbar, is_right_click):
	if not main_inventory_panel.visible: 
		return 

	var slot_data = inventory_ref.hotbar[index] if is_hotbar else inventory_ref.inventory[index]
	
	if is_right_click:
		_handle_right_click(index, is_hotbar, slot_data)
	else:
		_handle_left_click(index, is_hotbar, slot_data)
	
	inventory_ref.inventory_changed.emit()

func _handle_left_click(index, is_hotbar, slot_data):
	if holding_item == null:
		if slot_data != null:
			# Pick up whole stack
			holding_item = slot_data.duplicate()
			if is_hotbar: inventory_ref.hotbar[index] = null
			else: inventory_ref.inventory[index] = null
	else:
		if slot_data == null:
			# Place whole stack
			if is_hotbar: inventory_ref.hotbar[index] = holding_item.duplicate()
			else: inventory_ref.inventory[index] = holding_item.duplicate()
			holding_item = null
		else:
			if slot_data.type == holding_item.type:
				# Stack
				var add = min(holding_item.count, inventory_ref.MAX_STACK - slot_data.count)
				slot_data.count += add
				holding_item.count -= add
				if holding_item.count <= 0: holding_item = null
			else:
				# Swap
				var temp = slot_data.duplicate()
				if is_hotbar: inventory_ref.hotbar[index] = holding_item.duplicate()
				else: inventory_ref.inventory[index] = holding_item.duplicate()
				holding_item = temp

func _handle_right_click(index, is_hotbar, slot_data):
	if holding_item == null:
		if slot_data != null:
			# Split stack: pick up half
			var take = ceil(slot_data.count / 2.0)
			holding_item = {"type": slot_data.type, "count": take}
			slot_data.count -= take
			if slot_data.count <= 0:
				if is_hotbar: inventory_ref.hotbar[index] = null
				else: inventory_ref.inventory[index] = null
	else:
		# Drop 1 item from mouse into slot
		if slot_data == null:
			# Place one item
			var one_item = {"type": holding_item.type, "count": 1}
			if is_hotbar: inventory_ref.hotbar[index] = one_item
			else: inventory_ref.inventory[index] = one_item
			holding_item.count -= 1
			if holding_item.count <= 0: holding_item = null
		elif slot_data.type == holding_item.type and slot_data.count < inventory_ref.MAX_STACK:
			# Add one item to stack
			slot_data.count += 1
			holding_item.count -= 1
			if holding_item.count <= 0: holding_item = null

func update_ui():
	if not inventory_ref: return
	
	# Update Hotbar (bottom of screen)
	for i in range(inventory_ref.HOTBAR_SIZE):
		var slot_ui = hotbar_container.get_child(i)
		_update_slot_visual(slot_ui, inventory_ref.hotbar[i])
		
	# Update Main Hotbar (inside inventory)
	for i in range(inventory_ref.HOTBAR_SIZE):
		var slot_ui = main_hotbar_grid.get_child(i)
		_update_slot_visual(slot_ui, inventory_ref.hotbar[i])
		
	# Update Main Inventory
	for i in range(inventory_ref.INVENTORY_SIZE):
		var slot_ui = main_inventory_grid.get_child(i)
		_update_slot_visual(slot_ui, inventory_ref.inventory[i])
	
	call_deferred("_update_selection_outline")
	call_deferred("_update_hearts_position")
	
	# Update Floating Item
	if holding_item:
		var f_label = floating_item_ui.get_node("CountLabel")
		f_label.add_theme_font_size_override("font_size", 18)
		f_label.add_theme_color_override("font_outline_color", Color.BLACK)
		f_label.add_theme_constant_override("outline_size", 4)
		
		floating_item_ui.get_node("Icon").texture = block_textures.get(holding_item.type)
		f_label.text = str(holding_item.count) if holding_item.count > 1 else ""
		floating_item_ui.visible = true
	else:
		floating_item_ui.visible = false

func _update_hearts_position():
	if hotbar_container.get_child_count() > 0:
		var first_slot = hotbar_container.get_child(0)
		var offset_y = int(first_slot.size.y * 0.52)
		if offset_y < 10: offset_y = 25 # Fallback
		hearts_container.global_position = first_slot.global_position - Vector2(0, offset_y)

func _update_selection_outline():
	if main_inventory_panel and main_inventory_panel.visible:
		selection_outline.visible = false
		return
		
	if hotbar_container.get_child_count() > selected_slot:
		var target_slot = hotbar_container.get_child(selected_slot)
		selection_outline.global_position = target_slot.global_position - Vector2(2, 2)
		selection_outline.visible = true

func _update_slot_visual(slot_ui, data):
	var icon = slot_ui.get_node("Icon")
	var label = slot_ui.get_node("CountLabel")
	
	icon.texture_filter = Control.TEXTURE_FILTER_NEAREST
	
	# Apply styling to make numbers more visible
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)

	if data:
		icon.texture = block_textures.get(data.type)
		icon.visible = true
		label.text = str(data.count) if data.count > 1 else ""
	else:
		icon.visible = false
		label.text = ""

func _setup_creative_inventory():
	if not creative_grid: return
	
	# Clear existing
	for child in creative_grid.get_children():
		child.queue_free()
		
	# All solid blocks
	var blocks = [0, 1, 2, 3, 4, 5, 6, 7]
	
	for type in blocks:
		var slot = slot_scene.instantiate()
		creative_grid.add_child(slot)
		slot.custom_minimum_size = Vector2(48, 48)
		slot.slot_index = type
		slot.slot_clicked.connect(_on_creative_slot_clicked)
		_update_slot_visual(slot, {"type": type, "count": 1})
		slot.get_node("CountLabel").text = "" # Hide count in creative menu

func _on_creative_slot_clicked(type, _is_hotbar, _is_right_click):
	# In creative, clicking gives you a full stack
	holding_item = {"type": type, "count": inventory_ref.MAX_STACK}
	update_ui()

func set_selected(index):
	selected_slot = index
	update_ui()

func toggle_inventory():
	main_inventory_panel.visible = !main_inventory_panel.visible
	
	var state = get_node_or_null("/root/GameState")
	var is_creative = state and state.gamemode == state.GameMode.CREATIVE
	
	# Toggle creative tab accessibility
	tabs.set_tab_disabled(1, not is_creative)
	if is_creative:
		tabs.current_tab = 1
	else:
		tabs.current_tab = 0

	if main_inventory_panel.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mouse_filter = Control.MOUSE_FILTER_STOP
		$HotbarPanel.mouse_filter = Control.MOUSE_FILTER_STOP
		main_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		$HotbarPanel.visible = false # Hide bottom hotbar when inventory is open
		selection_outline.visible = false
		hearts_container.visible = false
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		$HotbarPanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main_inventory_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$HotbarPanel.visible = true
		
		# Force refresh to show selector and hearts
		update_ui()
		var player = get_tree().get_first_node_in_group("player")
		if player:
			update_health(player.health)
			
		if holding_item:
			inventory_ref.add_item(holding_item.type, holding_item.count)
			holding_item = null
			inventory_ref.inventory_changed.emit()
			
	return main_inventory_panel.visible
