shader_type spatial;
render_mode depth_draw_always, depth_test_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;

void vertex() {
	// Desired fixed FOV
	float fixed_fov = 75.0;
	float f = 1.0 / tan(fixed_fov * PI / 360.0);
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	
	// Preserve the original sign of the projection matrix (handles Y-flip if present)
	float sign_y = sign(PROJECTION_MATRIX[1][1]);
	
	PROJECTION_MATRIX[0][0] = f / aspect;
	PROJECTION_MATRIX[1][1] = f * sign_y;
	
	// Standard projection
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	
	// Ensure it stays in front of everything
	POSITION.z = mix(POSITION.z, 0.0, 0.99); 
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
