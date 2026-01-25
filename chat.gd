extends Control

@onready var display = $MarginContainer/VBoxContainer/ChatDisplay
@onready var input = $MarginContainer/VBoxContainer/ChatInput
@onready var suggestions_panel = $MarginContainer/VBoxContainer/SuggestionsPanel
@onready var suggestions_list = $MarginContainer/VBoxContainer/SuggestionsPanel/SuggestionsList

signal chat_active(is_active)

var history = []
var history_index = -1
var current_input_backup = ""

var commands = ["/op", "/deop", "/rule", "/help", "/tp", "/gamemode", "/spawn", "/ops", "/time", "/kill"]
var rules_list = ["dropitems"]

var fade_timer = 0.0
const FADE_TIME = 5.0 # Seconds before messages start to fade

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true # Parent PanelContainer always visible to show ChatDisplay
	# But hide background until chat is opened
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0) # Transparent initially
	add_theme_stylebox_override("panel", style)
	
	input.visible = false
	suggestions_panel.visible = false
	
	input.text_submitted.connect(_on_text_submitted)
	input.gui_input.connect(_on_input_gui_input)
	input.text_changed.connect(_on_input_text_changed)
	
	# Style suggestions panel - make it very obvious
	var sug_style = StyleBoxFlat.new()
	sug_style.bg_color = Color(0, 0, 0, 0.9) # Dark background
	sug_style.set_content_margin_all(8)
	suggestions_panel.add_theme_stylebox_override("panel", sug_style)
	
	display.bbcode_enabled = true
	display.text = "[color=yellow]Welcome to GodotCraft![/color]\n"
	
	# Add a background to the chat display itself
	var display_style = StyleBoxFlat.new()
	display_style.bg_color = Color(0, 0, 0, 0.4)
	display_style.set_content_margin_all(5)
	display.add_theme_stylebox_override("normal", display_style)
	
	# Add shadow for better visibility
	display.add_theme_color_override("font_shadow_color", Color.BLACK)
	display.add_theme_constant_override("shadow_offset_x", 1)
	display.add_theme_constant_override("shadow_offset_y", 1)
	display.add_theme_constant_override("shadow_outline_size", 1)
	
	_reset_fade()

func _process(delta):
	if not is_chat_active():
		fade_timer -= delta
		if fade_timer <= 0:
			var alpha = clamp(1.0 + (fade_timer / 2.0), 0.0, 1.0)
			display.modulate.a = alpha
			# If completely invisible, hide to prevent any accidental interaction
			if alpha <= 0:
				display.visible = false
			else:
				display.visible = true
		else:
			display.modulate.a = 1.0
			display.visible = true
	else:
		display.modulate.a = 1.0
		display.visible = true

func _reset_fade():
	fade_timer = FADE_TIME
	display.modulate.a = 1.0
	display.visible = true

func _on_input_text_changed(new_text):
	if suggestions_panel == null: return
	
	# Clear existing
	for child in suggestions_list.get_children():
		child.queue_free()

	if not new_text.begins_with("/"):
		suggestions_panel.visible = false
		return

	var parts = new_text.substr(1).split(" ", true)
	var cmd_part = parts[0].to_lower()
	var suggested = []
	
	if parts.size() == 1:
		# Suggesting the command itself
		for c in commands:
			if cmd_part == "" or c.substr(1).begins_with(cmd_part):
				suggested.append(c)
	elif parts.size() >= 2:
		# Suggesting arguments
		if cmd_part == "rule":
			var rule_part = parts[1].to_lower()
			for r in rules_list:
				if r.begins_with(rule_part):
					suggested.append(r)
		elif cmd_part == "op" or cmd_part == "deop":
			var name_part = parts[1].to_lower()
			# In a real game we'd get all online players
			var players = ["Player"] 
			var state = get_node_or_null("/root/GameState")
			if state:
				if not state.username in players: players.append(state.username)
			
			for p in players:
				if p.to_lower().begins_with(name_part):
					suggested.append(p)
		elif cmd_part == "help":
			var help_part = parts[1].to_lower()
			for c in commands:
				if c.substr(1).begins_with(help_part):
					suggested.append(c.substr(1))
		elif cmd_part == "kill":
			var name_part = parts[1].to_lower()
			var players = ["self", "Player"]
			var state = get_node_or_null("/root/GameState")
			if state:
				if not state.username in players: players.append(state.username)
			for p in players:
				if p.to_lower().begins_with(name_part):
					suggested.append(p)
	
	if suggested.size() > 0:
		for s in suggested:
			var btn = Button.new()
			btn.text = s
			btn.flat = true
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.3))
			btn.add_theme_font_size_override("font_size", 16)
			btn.pressed.connect(_apply_suggestion.bind(s))
			suggestions_list.add_child(btn)
		suggestions_panel.visible = true
	else:
		suggestions_panel.visible = false

func _on_input_gui_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			if suggestions_panel.visible and suggestions_list.get_child_count() > 0:
				var first_btn = suggestions_list.get_child(0)
				_apply_suggestion(first_btn.text)
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP:
			if history.size() > 0:
				if history_index == -1:
					current_input_backup = input.text
				
				history_index = min(history_index + 1, history.size() - 1)
				input.text = history[history.size() - 1 - history_index]
				input.caret_column = input.text.length()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			if history_index != -1:
				history_index -= 1
				if history_index == -1:
					input.text = current_input_backup
				else:
					input.text = history[history.size() - 1 - history_index]
				input.caret_column = input.text.length()
				get_viewport().set_input_as_handled()

func _apply_suggestion(suggestion: String):
	var text = input.text
	var parts = text.split(" ")
	if parts.size() > 0:
		# Replace the last part being typed
		parts[parts.size() - 1] = suggestion
		# If it's the command itself and doesn't have /, add it (unless it's already there)
		if parts.size() == 1 and not parts[0].begins_with("/"):
			parts[0] = "/" + parts[0]
			
		input.text = " ".join(parts) + " "
		input.caret_column = input.text.length()
		_on_input_text_changed(input.text)

func is_chat_active():
	return input.visible

func open_chat():
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style = get_theme_stylebox("panel").duplicate()
	style.bg_color = Color(0, 0, 0, 0.3)
	add_theme_stylebox_override("panel", style)
	
	input.visible = true
	input.grab_focus()
	chat_active.emit(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	history_index = -1
	current_input_backup = ""
	suggestions_panel.visible = false
	_on_input_text_changed(input.text) # Refresh suggestions
	_reset_fade()

func close_chat():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = get_theme_stylebox("panel").duplicate()
	style.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", style)
	
	input.visible = false
	input.release_focus()
	input.text = ""
	suggestions_panel.visible = false
	chat_active.emit(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_reset_fade()

func _on_text_submitted(new_text):
	if new_text.strip_edges() != "":
		history.append(new_text)
		if history.size() > 50:
			history.pop_front()
		
		var user = "Player"
		var state = get_node_or_null("/root/GameState")
		if state:
			user = state.username
			
		if new_text.begins_with("/"):
			_handle_command(new_text, user, state)
		else:
			add_message("[color=white]<" + user + "> " + new_text + "[/color]")
	close_chat()

func _handle_command(command_text: String, user: String, state: Node):
	var parts = command_text.substr(1).split(" ")
	var cmd = parts[0].to_lower()
	
	if cmd == "op":
		if parts.size() > 1:
			var target = parts[1]
			if not state.ops.has(target):
				state.ops.append(target)
				add_message("[color=yellow]" + target + " is now an operator.[/color]")
			else:
				add_message("[color=yellow]" + target + " is already an operator.[/color]")
		else:
			add_message("[color=red]Usage: /op <player_name>[/color]")
			
	elif cmd == "deop":
		if parts.size() > 1:
			var target = parts[1]
			if state.ops.has(target):
				state.ops.erase(target)
				add_message("[color=yellow]" + target + " is no longer an operator.[/color]")
			else:
				add_message("[color=yellow]" + target + " is not an operator.[/color]")
		else:
			add_message("[color=red]Usage: /deop <player_name>[/color]")
			
	elif cmd == "ops":
		add_message("[color=yellow]Operators: " + ", ".join(state.ops) + "[/color]")
			
	elif cmd == "time":
		if not state.ops.has(user):
			add_message("[color=red]You do not have permission to use this command.[/color]")
			return
			
		var world = get_node_or_null("/root/World")
		if not world: 
			add_message("[color=red]Error: World not found.[/color]")
			return
			
		if parts.size() > 2:
			var sub_cmd = parts[1].to_lower()
			var value_str = parts[2].to_lower()
			
			if sub_cmd == "set":
				if value_str == "day": world.time = 1000.0
				elif value_str == "noon": world.time = 6000.0
				elif value_str == "night": world.time = 13000.0
				elif value_str == "midnight": world.time = 18000.0
				else: world.time = value_str.to_float()
				
				add_message("[color=yellow]Set the time to " + str(int(world.time)) + "[/color]")
			elif sub_cmd == "add":
				world.time += value_str.to_float()
				add_message("[color=yellow]Added " + value_str + " to the time.[/color]")
			else:
				add_message("[color=red]Usage: /time <set|add|query> <value>[/color]")
		elif parts.size() > 1 and parts[1].to_lower() == "query":
			add_message("[color=yellow]The time is " + str(int(world.time)) + "[/color]")
		else:
			add_message("[color=red]Usage: /time <set|add|query> <value>[/color]")

	elif cmd == "kill":
		if not state.ops.has(user):
			add_message("[color=red]You do not have permission to use this command.[/color]")
			return
		
		var target_name = "self"
		if parts.size() > 1:
			target_name = parts[1].to_lower()
		
		if target_name == "self" or target_name == user.to_lower():
			var player = get_tree().get_first_node_in_group("player")
			if player:
				player.health = 0
				add_message("[color=yellow]Killed " + user + "[/color]")
		else:
			# In a real multiplayer setup we'd search for the player by name.
			# For now, we only have one player.
			if target_name == "player": # Default fallback name
				var player = get_tree().get_first_node_in_group("player")
				if player:
					player.health = 0
					add_message("[color=yellow]Killed player[/color]")
			else:
				add_message("[color=red]Player not found: " + target_name + "[/color]")

	elif cmd == "rule":
		if not state.ops.has(user):
			add_message("[color=red]You do not have permission to use this command.[/color]")
			return
			
		if parts.size() > 2:
			var rule_name = parts[1].to_lower()
			var value_str = parts[2].to_lower()
			var value = value_str == "true"
			
			if rule_name == "dropitems":
				state.rules["drop_items"] = value
				add_message("[color=yellow]Game rule dropitems has been updated to: " + str(value) + "[/color]")
			else:
				add_message("[color=red]Unknown game rule: " + rule_name + "[/color]")
		else:
			add_message("[color=red]Usage: /rule <rulename> <value>[/color]")
	elif cmd == "help":
		add_message("[color=yellow]Available commands: " + ", ".join(commands) + "[/color]")
	else:
		add_message("[color=red]Unknown command.[/color]")

func add_message(msg):
	display.text += msg + "\n"
	_reset_fade()
	# Auto-scroll to bottom
	await get_tree().process_frame
	display.scroll_to_line(display.get_line_count())
