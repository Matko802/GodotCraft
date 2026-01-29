extends PanelContainer

signal slot_clicked(index, is_hotbar, is_right_click)

var slot_index = -1
var is_hotbar_slot = false
var custom_tooltip = ""

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	$ClickArea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.4, 1.0) # Subtle lighter gray
	add_theme_stylebox_override("panel", style)
	
	if has_node("Background"):
		$Background.visible = false

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		print("Slot clicked: ", slot_index, " Hotbar: ", is_hotbar_slot, " Button: ", event.button_index)
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(slot_index, is_hotbar_slot, false)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_clicked.emit(slot_index, is_hotbar_slot, true)
