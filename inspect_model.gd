@tool
extends SceneTree

func _init():
	var path = "res://models/player/Matko880 exclusive model/Matko802.gltf"
	if not FileAccess.file_exists(path):
		print("File not found: ", path)
		quit()
		return
		
	var scene = load(path)
	if not scene:
		print("Failed to load scene")
		quit()
		return
		
	var instance = scene.instantiate()
	print_tree(instance)
	
	var anim_players = instance.find_children("*", "AnimationPlayer", true)
	for ap in anim_players:
		print("AnimationPlayer: ", ap.name)
		for anim_name in ap.get_animation_list():
			print("  - ", anim_name)
			
	instance.free()
	quit()

func print_tree(node, indent = ""):
	print(indent + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		print_tree(child, indent + "  ")
