shader_type spatial;
render_mode depth_draw_always;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float viewmodel_fov = 75.0;

void vertex() {
	float current_fov_rad = 2.0 * atan(1.0 / abs(PROJECTION_MATRIX[1][1]));
	float target_fov_rad = viewmodel_fov * PI / 180.0;
	float scale = tan(current_fov_rad * 0.5) / tan(target_fov_rad * 0.5);
	
	mat4 p = PROJECTION_MATRIX;
	p[0][0] *= scale;
	p[1][1] *= scale;
	
	POSITION = p * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
}

void fragment() {
	vec4 color = texture(albedo_texture, UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
