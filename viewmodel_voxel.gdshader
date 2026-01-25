shader_type spatial;

uniform sampler2D top_texture : source_color, filter_nearest;
uniform sampler2D side_texture : source_color, filter_nearest;
uniform sampler2D bottom_texture : source_color, filter_nearest;

varying vec3 v_normal;

void vertex() {
	v_normal = NORMAL;
	// Pull the depth towards the camera to prevent clipping into world blocks
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.z * 0.1;
}

void fragment() {
	vec3 color;
	if (v_normal.y > 0.5) {
		color = texture(top_texture, UV).rgb;
	} else if (v_normal.y < -0.5) {
		color = texture(bottom_texture, UV).rgb;
	} else {
		color = texture(side_texture, UV).rgb;
	}
	ALBEDO = color;
}