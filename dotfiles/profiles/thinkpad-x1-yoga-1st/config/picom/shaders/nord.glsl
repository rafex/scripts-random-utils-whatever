#version 330

in vec2 texcoord;
uniform sampler2D tex;

vec4 window_shader() {
    vec2 texsize = textureSize(tex, 0);
    vec4 color = texture2D(tex, texcoord / texsize, 0);
    float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 cool = color.rgb * vec3(0.985, 1.000, 1.015);
    cool = mix(vec3(luminance), cool, 1.05);
    color.rgb = clamp(mix(color.rgb, cool, 0.18), 0.0, 1.0);
    return default_post_processing(color);
}
