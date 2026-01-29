extends Node

signal inventory_changed

const HOTBAR_SIZE = 9
const INVENTORY_SIZE = 27
const MAX_STACK = 64

# Each slot is { "type": BlockType, "count": int } or null
var hotbar = []
var inventory = []

func _ready():
	for i in range(HOTBAR_SIZE):
		hotbar.append(null)
	for i in range(INVENTORY_SIZE):
		inventory.append(null)
	
	# Starting items removed for empty default
	inventory_changed.emit()

func clear():
	for i in range(HOTBAR_SIZE):
		hotbar[i] = null
	for i in range(INVENTORY_SIZE):
		inventory[i] = null
	inventory_changed.emit()

const DROPPED_ITEM_SCENE = preload("res://dropped_item.tscn")

func drop_all(pos: Vector3, world: Node):
	for i in range(HOTBAR_SIZE):
		if hotbar[i]:
			spawn_dropped_item(hotbar[i].type, hotbar[i].count, pos, world)
			hotbar[i] = null
	for i in range(INVENTORY_SIZE):
		if inventory[i]:
			spawn_dropped_item(inventory[i].type, inventory[i].count, pos, world)
			inventory[i] = null
	inventory_changed.emit()

func drop_single(index: int, is_hotbar: bool, pos: Vector3, dir: Vector3, world: Node):
	var slot_data = hotbar[index] if is_hotbar else inventory[index]
	if slot_data:
		var count_to_drop = 1
		# If we wanted to drop whole stack we could change this
		var item = spawn_dropped_item(slot_data.type, count_to_drop, pos, world, dir * 5.0)
		item.pickup_delay = 1.5 # Manually dropped items have a delay
		slot_data.count -= count_to_drop
		if slot_data.count <= 0:
			if is_hotbar: hotbar[index] = null
			else: inventory[index] = null
		inventory_changed.emit()

func spawn_dropped_item(type: int, count: int, pos: Vector3, world: Node, custom_vel: Vector3 = Vector3.ZERO):
	var item = DROPPED_ITEM_SCENE.instantiate()
	item.type = type
	item.count = count
	world.add_child(item)
	item.global_position = pos
	
	if custom_vel != Vector3.ZERO:
		item.velocity = custom_vel
	else:
		# Random spread for death drops
		item.velocity = Vector3(randf() - 0.5, randf(), randf() - 0.5) * 4.0
	
	return item

func add_item(type, count = 1):
	if type < 0: return 0 # Don't add air blocks
	
	var remaining = count
	
	# Try to stack in hotbar first
	for i in range(HOTBAR_SIZE):
		if hotbar[i] and hotbar[i].type == type and hotbar[i].count < MAX_STACK:
			var add = min(remaining, MAX_STACK - hotbar[i].count)
			hotbar[i].count += add
			remaining -= add
			if remaining <= 0:
				inventory_changed.emit()
				return count
				
	# Try to stack in inventory
	for i in range(INVENTORY_SIZE):
		if inventory[i] and inventory[i].type == type and inventory[i].count < MAX_STACK:
			var add = min(remaining, MAX_STACK - inventory[i].count)
			inventory[i].count += add
			remaining -= add
			if remaining <= 0:
				inventory_changed.emit()
				return count
				
	# Try empty hotbar slots
	for i in range(HOTBAR_SIZE):
		if hotbar[i] == null:
			var add = min(remaining, MAX_STACK)
			hotbar[i] = {"type": type, "count": add}
			remaining -= add
			if remaining <= 0:
				inventory_changed.emit()
				return count
			
	# Try empty inventory slots
	for i in range(INVENTORY_SIZE):
		if inventory[i] == null:
			var add = min(remaining, MAX_STACK)
			inventory[i] = {"type": type, "count": add}
			remaining -= add
			if remaining <= 0:
				inventory_changed.emit()
				return count
			
	if remaining < count:
		inventory_changed.emit()
		return count - remaining
		
	return 0 # Full

func can_add_item(type: int, count: int = 1) -> bool:
	if type < 0: return false
	
	# Check for existing stacks
	for slot in hotbar:
		if slot and slot.type == type and slot.count < MAX_STACK:
			count -= (MAX_STACK - slot.count)
			if count <= 0: return true
	for slot in inventory:
		if slot and slot.type == type and slot.count < MAX_STACK:
			count -= (MAX_STACK - slot.count)
			if count <= 0: return true
			
	# Check for empty slots
	for slot in hotbar:
		if slot == null: return true
	for slot in inventory:
		if slot == null: return true
		
	return false

func pick_block(type: int, current_selected_slot: int):
	# 1. Check if it's already in the hotbar
	for i in range(HOTBAR_SIZE):
		if hotbar[i] and hotbar[i].type == type:
			# Just return the index so player can switch to it
			return i
			
	# 2. Check if it's in the main inventory
	for i in range(INVENTORY_SIZE):
		if inventory[i] and inventory[i].type == type:
			# Swap with current hotbar slot
			var temp = hotbar[current_selected_slot]
			hotbar[current_selected_slot] = inventory[i]
			inventory[i] = temp
			inventory_changed.emit()
			return current_selected_slot
			
	return -1 # Not found
