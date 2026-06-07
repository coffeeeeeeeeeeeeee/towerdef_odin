#version 330

// Heightmap overlay shader.
// Samples a small grayscale heightmap (typically GRID_SIZE x GRID_SIZE) with
// bilinear filtering to produce a smooth, continuous height gradient over the
// rendered terrain. Outputs a semi-transparent tint that brightens high cells
// and darkens low cells, plus optional topographic isolines for added definition.
//
// Bound texture: texture0 (raylib convention) is the heightmap, R channel only.
// fragTexCoord is provided by raylib's stock vertex shader.

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;

// Per-biome tuning, set from CPU each frame.
uniform float u_contrast;          // amplifies (h - 0.5). 1.0 = linear, 2-3 = pronounced
uniform float u_alpha_max;         // [0..1] max overlay alpha for extreme heights
uniform float u_contour_steps;     // number of isolines (e.g. 8 = lines every 0.125 height)
uniform float u_contour_strength;  // [0..1] alpha multiplier for isolines
uniform float u_contour_width;     // line thickness IN SCREEN PIXELS (1.0 = 1px)

void main() {
    float h = texture(texture0, fragTexCoord).r;

    // Contrast curve — amplify deviation from the mid-height (0.5) then clamp.
    float delta = clamp((h - 0.5) * 2.0 * u_contrast, -1.0, 1.0);

    // Tint: black overlay for low heights, white overlay for high heights.
    // Using `step` keeps the two regimes cleanly separated; alpha drives strength.
    vec3 tint_color = vec3(step(0.0, delta));
    float tint_alpha = abs(delta) * u_alpha_max;

    // Topographic isolines, exactamente u_contour_width pixeles de grosor en pantalla.
    // Truco estándar: fract(h * steps) genera un sawtooth; doblamos para obtener
    // distancia a la isolínea más cercana. fwidth(h_scaled) da cuánto cambia
    // h_scaled por pixel de pantalla → permite que el grosor sea constante en
    // pixeles independiente del zoom/escala.
    float h_scaled     = h * u_contour_steps;
    float band         = fract(h_scaled);
    float dist_to_line = min(band, 1.0 - band);
    float pixel_in_h   = fwidth(h_scaled);                  // 1 pixel = pixel_in_h unidades de h_scaled
    float half_thick   = pixel_in_h * u_contour_width * 0.5;
    // smoothstep con un margen de ±0.5 pixel alrededor del grosor objetivo:
    // AA contenido a un pixel, sin blur perceptible. Suaviza los jaggies de
    // los tramos diagonales sin engordar la línea.
    float line         = 1.0 - smoothstep(half_thick * 0.5, half_thick * 1.5, dist_to_line);
    float contour_alpha = line * u_contour_strength;

    // La isolínea siempre oscurece, sin importar el régimen de tinte.
    vec3 final_rgb = mix(tint_color, vec3(0.0), line);
    float final_alpha = max(tint_alpha, contour_alpha);

    // fragColor lets the CPU side multiply a global tint via DrawTexture's tint.
    finalColor = vec4(final_rgb, final_alpha) * fragColor;
}
