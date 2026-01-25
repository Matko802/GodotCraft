extends PanelContainer

signal slot_clicked(index, is_hotbar, is_right_click)

var slot_index = -1
var is_hotbar_slot = false

func _ready():
	$ClickArea.gui_input.connect(_on_click_area_input)
	$ClickArea.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if has_node("Background"):
		$Background.visible = false

func _on_click_area_input(event):
	if event is InputEventMouseButton and event.pressed:
		print("Slot clicked (Button): ", slot_index, " Hotbar: ", is_hotbar_slot, " Button: ", event.button_index)
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(slot_index, is_hotbar_slot, false)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_clicked.emit(slot_index, is_hotbar_slot, true)

func _gui_input(event):
	# Fallback if clicked outside button (unlikely)
	if event is InputEventMouseButton and event.pressed:
		print("Slot clicked (Root): ", slot_index)
		pass
