#version 330

// Dune overlay shader — ondulaciones de arena + grano fino sobre todo el
// terreno del bioma DESERT. No depende del heightmap (el heightmap es
// desnivel del terreno, no tiene relación real con dónde hay arena) ni de
// una capa pintada a mano: cubre el mapa entero, y lo único que varía la
// forma de las dunas de un mapa a otro es u_seed (derivado de m.seed, así
// que sigue siendo "parte del mapa" sin acoplarse a otro sistema).
//
// Ondulación: ridged noise (1 - abs(n*2-1), técnica clásica de Musgrave para
// terreno — convierte colinas suaves en crestas afiladas e irregulares) para
// la forma grande de la duna, más líneas de estría finas ancladas al viento
// cuya fase se curva con esa misma forma grande (las estrías "trepan" las
// crestas en vez de ser rectas), en vez de un sin() plano de baja variación.

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform vec2  u_resolution;
uniform vec2  u_camera_offset;  // origen del mapa en px de pantalla (coords Raylib, y-down)
uniform float u_zoom;
uniform float u_time;
uniform float u_seed;           // m.seed del mapa — varía el patrón entre mapas
uniform float u_alpha;          // opacidad del overlay (tuning por bioma)
uniform float u_density;        // escala del ruido (tuning por bioma)
uniform vec4  u_dune_color;

float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Ridged noise: pliega el value noise sobre su punto medio, así los valles
// (donde n≈0.5) se vuelven crestas afiladas en vez de mesetas suaves.
float ridged(vec2 p) {
    float n = valueNoise(p);
    return 1.0 - abs(n * 2.0 - 1.0);
}

// 4 octavas de ridged noise — forma grande de la duna, irregular (no un
// patrón periódico perfecto como un sin() puro).
float duneShape(vec2 p) {
    float sum = 0.0, amp = 0.55, freq = 1.0;
    for (int i = 0; i < 4; i++) {
        sum += ridged(p * freq) * amp;
        freq *= 2.15;
        amp *= 0.5;
    }
    return sum; // ~0..1, picos afilados
}

void main() {
    vec2  screenPos = vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y);  // flip y (coords Raylib)
    vec2  worldPos  = (screenPos - u_camera_offset) / u_zoom;
    vec2  p         = worldPos * (u_density / 128.0) + u_seed * 0.017;

    // Viento fijo en diagonal — todo el patrón (crestas grandes y estrías)
    // queda perpendicular a esta dirección, como dunas reales moldeadas por
    // un viento dominante.
    vec2  wind_dir = normalize(vec2(0.94, 0.34));
    float along    = dot(p, wind_dir);
    float across   = dot(p, vec2(-wind_dir.y, wind_dir.x));

    // Forma grande de la duna: estirada a lo largo del viento (dunas
    // alargadas, no manchas redondas) y con deriva lenta en el tiempo.
    float shape = duneShape(vec2(along * 0.65, across) * 0.5 + vec2(u_time * 0.01, 0.0));

    // Estrías de viento, perpendiculares al viento, en DOS frecuencias
    // superpuestas (como los campos de dunas reales, que tienen ondulación
    // primaria + una secundaria más fina montada encima) — la fase de ambas
    // se corre con `shape` para que sigan la ondulación grande (trepan las
    // crestas) en vez de ser paralelas perfectas, y se afilan con
    // sign()*pow() en vez de quedar como una sinusoide suave, para que se
    // lean como surcos, no como una onda.
    float wave1 = sin(across * 3.4 + shape * 3.0 + u_time * 0.02);
    float wave2 = sin(across * 6.1 - shape * 2.0 + u_time * 0.017 + 1.7);
    float lines1 = sign(wave1) * pow(abs(wave1), 0.5) * 0.5 + 0.5;
    float lines2 = sign(wave2) * pow(abs(wave2), 0.6) * 0.5 + 0.5;
    float lines  = mix(lines1, lines2, 0.4);

    // Grano fino, estático (sin u_time — el shimmer de grano animado se ve
    // ruidoso/distrae en vez de leerse como textura).
    float grain = valueNoise(p * 12.0);

    float shade = shape * 0.40 + lines * 0.48 + grain * 0.12;
    vec3  col   = u_dune_color.rgb * clamp(0.55 + shade * 0.70, 0.45, 1.30);

    finalColor = vec4(col, u_alpha) * fragColor;
}
