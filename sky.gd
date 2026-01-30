extends Node3D

@onready var sun = $Sun
@onready var moon = $Moon

var time: float = 0.0
const MAX_TIME = 24000.0

func _ready():
	_setup_materials()

func _setup_materials():
	var quad = QuadMesh.new()
	quad.size = Vector2(60, 60)
	
	# Sun setup
	sun.mesh = quad
	sun.position = Vector3(0, 0, -500) # Increased distance to 500
	var sun_mat = StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_texture = load("res://textures/sky/sun.png")
	sun_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sun_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sun_mat.render_priority = -10 # Render before everything
	sun.material_override = sun_mat
	
	# Moon setup
	moon.mesh = quad
	moon.position = Vector3(0, 0, 500) # Increased distance to 500
	moon.rotation_degrees.y = 180
	var moon_mat = StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_texture = load("res://textures/sky/moon.png")
	moon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	moon_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	moon_mat.render_priority = -10
	moon.material_override = moon_mat

func update_time(new_time: float, player_pos: Vector3):
	time = new_time
	global_position = player_pos
	
	var angle = (time / MAX_TIME) * 360.0
	rotation_degrees.x = angle
