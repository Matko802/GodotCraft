shader_type sky;

uniform sampler2D sun_texture : filter_nearest;
uniform sampler2D moon_texture : filter_nearest;
uniform float sun_angle; // radians
uniform float moon_angle; // radians
uniform vec3 sun_color : source_color = vec3(1.0);
uniform vec3 moon_color : source_color = vec3(1.0);

// Default Godot Procedural Sky Parameters
uniform vec3 sky_top_color : source_color = vec3(0.385, 0.454, 0.543);
uniform vec3 sky_horizon_color : source_color = vec3(0.646, 0.656, 0.67);
uniform float sky_curve : hint_range(0, 1) = 0.15;
uniform float sky_energy = 1.0;

uniform vec3 ground_bottom_color : source_color = vec3(0.2, 0.169, 0.133);
uniform vec3 ground_horizon_color : source_color = vec3(0.646, 0.656, 0.67);
uniform float ground_curve : hint_range(0, 1) = 0.02;
uniform float ground_energy = 1.0;

void sky() {
    float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
    float c = (1.0 - v_angle / (PI * 0.5));
    vec3 sky;
    if (EYEDIR.y > 0.0) {
        sky = mix(sky_horizon_color, sky_top_color, pow(c, 1.0 / sky_curve)) * sky_energy;
    } else {
        sky = mix(ground_horizon_color, ground_bottom_color, pow(1.0 + c, 1.0 / ground_curve)) * ground_energy;
    }

    // Draw Sun
    // The sun/moon move along a circle in the sky.
    // We assume they rotate around the X axis (or whatever your day/night cycle uses)
    // Here we use a simpler approach: pass the sun/moon direction.
    
    // Instead of complex math, we can just use the built-in sun/moon direction 
    // if we pass them as uniforms, but Godot Sky shaders can also just use LIGHT_DIR
    // if they are linked to a light.
    
    // However, to use TEXTURES, we need UVs on the sky dome relative to light dir.
    
    // Simplest: use sprites but with a fix. 
    // BUT the user asked for "deafult godot sky not custom".
    // I will go back to Sprites but fix the material and rendering.
    
    COLOR = sky;
}
