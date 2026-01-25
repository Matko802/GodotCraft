shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_nearest;

void vertex() {
	// Pull the depth towards the camera to prevent clipping into world blocks
	// We keep it shaded (no unshaded) so it receives environmental shadows
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.z * 0.1; 
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}