shader_type spatial;

uniform sampler2D top_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D side_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D bottom_texture : source_color, filter_nearest, repeat_disable;

varying vec3 v_normal;

void vertex() {
    v_normal = NORMAL;
}

void fragment() {
    vec3 normal = v_normal;
    vec4 color = vec4(1.0);
    vec2 uv = UV;
    
    // Top face (Normal Y+)
    if (normal.y > 0.5) {
        color = texture(top_texture, uv);
    // Bottom face (Normal Y-)
    } else if (normal.y < -0.5) {
        color = texture(bottom_texture, uv);
    // Side faces (Normal X or Z)
    } else {
        color = texture(side_texture, uv);
    }
    
    ALBEDO = color.rgb;
}