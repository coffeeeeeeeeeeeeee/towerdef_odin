#version 330

// Shimmer sutil para la grilla del editor (render_grid_lines_3d) — un
// ruido de brillo de alta frecuencia espacial, con deriva lenta en el
// tiempo. El value noise (interpolación bilineal + smoothstep entre
// esquinas de una grilla de hashes) ya es "suave" por construcción, a
// diferencia de un hash crudo por fragmento (que se vería como estática
// de TV) — es lo que lo hace ver como un shimmer vivo en vez de ruido
// duro, sin necesitar un paso de blur aparte.
in vec3 fragWorldPos;
in vec4 fragColor;
in float fragLineT;

uniform float gridNoiseTime;

out vec4 finalColor;

float gridHash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float gridValueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = gridHash21(i);
    float b = gridHash21(i + vec2(1.0, 0.0));
    float c = gridHash21(i + vec2(0.0, 1.0));
    float d = gridHash21(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
    // Frecuencia alta (×60 sobre posición de mundo) para que la
    // variación se note a lo largo del trazo de la línea, no solo tile a
    // tile; la deriva en el tiempo es lenta (×3 sobre gridNoiseTime, que
    // ya viene acumulado despacio desde Odin) para que se sienta vivo sin
    // titilar de golpe.
    float n = gridValueNoise(fragWorldPos.xz * 60.0 + vec2(gridNoiseTime * 3.0, 0.0));

    // El ruido mueve OPACIDAD, no brillo: multiplicar el RGB (como hacía
    // antes) sobre una línea opaca no aclara ni oscurece con matices, va
    // derecho a gris/negro — se veía como puntitos negros salpicados en
    // vez de un shimmer. Bajando el alfa en cambio se genera un hueco: se
    // ve el terreno de abajo, no un punto oscuro pintado encima.
    float opacity = mix(0.5, 1.0, n);

    // Desvanecido TANGENCIAL: a lo largo de CADA segmento de grilla en
    // particular (su propio centro vs. sus propias dos puntas), no
    // respecto del mapa entero — fragLineT es 0/1 en las puntas del
    // segmento y 0.5 en el medio (ver grid_line.vs). d: 0 en el centro del
    // segmento, 1 en cualquiera de las dos puntas. El 60% central del
    // segmento queda a opacidad plena; el 40% de cada punta se desvanece.
    float d = abs(fragLineT - 0.5) * 2.0;
    float tangent_fade = 1.0 - smoothstep(0.6, 1.0, d);
    opacity *= tangent_fade;

    finalColor = vec4(fragColor.rgb, fragColor.a * opacity);
}
