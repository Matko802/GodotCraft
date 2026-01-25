shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
    
    // Invert the screen color where the crosshair is opaque
    COLOR.rgb = 1.0 - screen_color.rgb;
    COLOR.a = tex_color.a;
}
