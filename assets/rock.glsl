#version 330

// Rock overlay shader — placas de roca agrietadas sobre el bioma MOUNTAIN.
// Mismo patrón que dune.glsl: cubre todo el mapa, 100% procedural, sin
// depender del heightmap ni de una capa pintada — u_seed es lo único que
// ata el patrón a "este mapa específico".
//
// Técnica: Voronoi F1/F2 (distancia al punto-semilla más cercano y al
// segundo más cercano de una grilla de celdas jitereadas). F2-F1 da las
// líneas de grieta entre placas (≈0 = borde de celda = grieta); F1 por sí
// solo separa "placas" y se usa para variar el tono de cada una. Referencia:
// iquilezles.org/articles/voronoilines — implementación estándar de F1/F2.
//
// Irregularidad: UN solo Voronoi da celdas todas del mismo tamaño (se lee
// "de grilla"). Para mezclar figuras grandes y chicas se corren TRES
// Voronoi a escalas distintas (grande/media/chica, cada uno con su propio
// offset de semilla) y se combinan por máximo — las grietas grandes
// dominan la forma, las chicas subdividen algunas placas grandes en
// pedazos más finos, nunca todas por igual. Antes de cada muestreo además
// se distorsiona la coordenada con ruido de baja frecuencia (domain warp)
// para que los bordes de celda no salgan rectos.

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform vec2  u_resolution;
uniform vec2  u_camera_offset;  // origen del mapa en px de pantalla (coords Raylib, y-down)
uniform float u_zoom;
uniform float u_time;
uniform float u_seed;           // m.seed del mapa — varía el mosaico entre mapas
uniform float u_alpha;          // opacidad del overlay (tuning por bioma)
uniform float u_density;        // escala de las placas (tuning por bioma)
uniform vec4  u_rock_color;

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

float hash1(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453123);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash1(i);
    float b = hash1(i + vec2(1.0, 0.0));
    float c = hash1(i + vec2(0.0, 1.0));
    float d = hash1(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Distorsiona la coordenada con ruido de baja frecuencia — bordes de celda
// ondulados en vez de rectos.
vec2 warp(vec2 p, float amt) {
    float wx = valueNoise(p * 0.5 + 11.3) - 0.5;
    float wy = valueNoise(p * 0.5 + 47.9) - 0.5;
    return p + vec2(wx, wy) * amt;
}

// x,y = distancia a la celda más cercana (F1) y a la segunda más cercana
// (F2); z = hash de la celda ganadora (id de placa, para variar su tono).
vec3 voronoi(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    float f1 = 8.0, f2 = 8.0;
    vec2 cell = n;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash2(n + g);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < f1) { f2 = f1; f1 = d; cell = n + g; }
            else if (d < f2) { f2 = d; }
        }
    }
    return vec3(sqrt(f1), sqrt(f2), hash1(cell));
}

void main() {
    vec2 screenPos = vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y);  // flip y (coords Raylib)
    vec2 worldPos  = (screenPos - u_camera_offset) / u_zoom;
    vec2 base      = worldPos * (u_density / 128.0) + u_seed * 0.013;

    // Escala GRANDE — define las placas principales. Línea fina (banda de
    // smoothstep angosta) y sutil (se mezcla con menos fuerza más abajo, en
    // vez de con el mismo negro que las grietas chicas).
    vec2  pL = warp(base * 0.45, 0.35) + 3.1;
    vec3  vL = voronoi(pL);
    float edgeL  = vL.y - vL.x;
    float crackL = 1.0 - smoothstep(0.0, 0.035, edgeL);

    // Escala MEDIA — subdivide algunas placas grandes.
    vec2  pM = warp(base * 1.15, 0.30) + 91.7;
    vec3  vM = voronoi(pM);
    float edgeM  = vM.y - vM.x;
    float crackM = 1.0 - smoothstep(0.0, 0.10, edgeM);

    // Escala CHICA — astillas finas encima de todo.
    vec2  pS = warp(base * 2.8, 0.20) + 233.9;
    vec3  vS = voronoi(pS);
    float edgeS  = vS.y - vS.x;
    float crackS = 1.0 - smoothstep(0.0, 0.08, edgeS);

    // Grietas chicas/medias: contraste fuerte (líneas marcadas). Grieta
    // grande: se resuelve aparte, más abajo, con menos contraste.
    float crackFine = max(crackM * 0.75, crackS * 0.55);

    // Tono por placa: domina la celda grande (regiones de color amplias),
    // con variación fina mezclada encima para que no se vea plano.
    float plateShade = 0.75 + vL.z * 0.5;          // ~0.75..1.25, celda grande
    float fineShade   = mix(0.92, 1.08, vM.z);      // variación chica encima
    plateShade *= fineShade;

    // Grano fino, estático (sin u_time — el ruido de roca no tiene que titilar).
    float grain = mix(0.9, 1.1, hash1(floor(base * 9.0)));

    vec3 rockCol      = u_rock_color.rgb * plateShade * grain;
    vec3 crackColFine = u_rock_color.rgb * 0.35; // grietas chicas/medias: oscuras, marcadas
    vec3 crackColBig  = u_rock_color.rgb * 0.72; // grieta grande: sutil, casi el mismo tono

    // Grieta grande primero (sutil, línea fina), grietas finas encima
    // (más oscuras) — así ninguna tapa a la otra donde coinciden.
    vec3 col = mix(rockCol, crackColBig, crackL);
    col      = mix(col, crackColFine, crackFine);

    finalColor = vec4(col, u_alpha) * fragColor;
}
