shader_type spatial;
render_mode depth_draw_always, depth_test_disabled;

uniform sampler2D top_texture : source_color, filter_nearest;
uniform sampler2D side_texture : source_color, filter_nearest;
uniform sampler2D bottom_texture : source_color, filter_nearest;

varying float v_normal_y;

void vertex() {
	// Use local normal for the held item so textures stay on the correct faces
	v_normal_y = NORMAL.y;
	
	// Desired fixed FOV
	float fixed_fov = 75.0;
	float f = 1.0 / tan(fixed_fov * PI / 360.0);
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	
	// Preserve the original sign of the projection matrix (handles Y-flip if present)
	float sign_y = sign(PROJECTION_MATRIX[1][1]);
	
	PROJECTION_MATRIX[0][0] = f / aspect;
	PROJECTION_MATRIX[1][1] = f * sign_y;
	
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, 0.0, 0.99);
}

void fragment() {
	vec4 color;
	if (v_normal_y > 0.5) {
		color = texture(top_texture, UV);
	} else if (v_normal_y < -0.5) {
		color = texture(bottom_texture, UV);
	} else {
		color = texture(side_texture, UV);
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
