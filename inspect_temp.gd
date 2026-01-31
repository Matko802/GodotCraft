extends Node

func _ready():
	var models = [
		"res://models/player/wide/model.gltf",
		"res://models/player/slim/model.gltf",
		"res://models/player/Matko880 exclusive model/Matko802.gltf"
	]
	
	for path in models:
		print("\n--- Inspecting: ", path, " ---")
		var scene = load(path)
		if not scene:
			print("Failed to load")
			continue
		var instance = scene.instantiate()
		var ap = instance.find_child("AnimationPlayer", true)
		if ap:
			print("Animations: ", ap.get_animation_list())
			if ap.has_animation("holding"):
				var anim = ap.get_animation("holding")
				print("Tracks in 'holding':")
				for i in range(anim.get_track_count()):
					print("  - ", anim.track_get_path(i))
		instance.free()
	
	get_tree().quit()
