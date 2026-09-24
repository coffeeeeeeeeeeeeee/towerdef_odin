#version 330

in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragTexCoord;
in vec4 fragPosLightSpace;

out vec4 finalColor;

// Iluminación: sol direccional (día/noche móvil) + luz de relleno tenue
// (para que las caras en sombra no queden negro puro) + ambient constante,
// más especular suave y sombra proyectada real — ver 3D_RENDER_PLAN.md
// para la decisión original de "simple", y CLAUDE.md para las extensiones.
uniform vec3 sunDir;   // normalizado, apunta DESDE la superficie HACIA el sol
uniform vec3 sunColor;
uniform vec3 fillDir;
uniform vec3 fillColor;
uniform vec3 ambient;

// Sombra proyectada real (shadow mapping) — depth pre-pass desde el sol,
// ver render_shadow_depth_pass en rendering.odin. Solo atenúa el término
// de SOL de la fórmula de luz de abajo, nunca ambient/fill — un fragmento
// en sombra sigue recibiendo luz ambiente, nunca queda negro puro (mismo
// criterio que ya se usó para el keyframe NIGHT del día/noche). PCF manual
// 3x3 — no hay sampler de comparación por hardware en estos bindings.
uniform sampler2D shadowMap;
uniform float shadowDepthBias;  // fijo, ver constants.SHADOW_DEPTH_BIAS
uniform float shadowMinFactor;  // piso — fracción de sol que sobrevive en sombra plena

// ndotl: dot(normal, sunDir) YA clampeado a [0,1] (el mismo sunDiff que
// arma el término difuso) — hace falta para el bias de abajo. Un bias FIJO
// alcanza para una superficie de frente al sol, pero en superficies
// casi de canto (ndotl bajo — copas de árbol, hojas casi paralelas a la
// luz) un texel de la sombra cubre una franja de profundidad mucho más
// ancha en mundo real, y ese mismo bias chico queda corto: el fragmento
// se autosombrea contra su propio triángulo (o el de al lado, casi
// coplanar) en un patrón rayado — "efecto tijera"/peine en el borde de la
// sombra, mucho más notorio con geometría densa y angosta (hojas/fronds
// de los árboles reales) que con los cuerpos simples de antes (torres,
// cajas). El bias efectivo escala con la pendiente (aprox. tan del
// ángulo respecto de la normal, clampeado para no dispararse a nada en
// ángulos casi rasantes) y nunca baja del piso fijo — eso evita reabrir
// peter-panning en las superficies de frente, que ya estaban bien.
float shadow_factor(float ndotl) {
    vec3 proj = fragPosLightSpace.xyz / fragPosLightSpace.w;
    proj = proj * 0.5 + 0.5;  // NDC [-1,1] -> espacio de textura [0,1]
    if (proj.z > 1.0) return 1.0;  // fuera del far plane de la luz — sin dato, full sol

    float slope = clamp(sqrt(max(1.0 - ndotl * ndotl, 0.0)) / max(ndotl, 0.05), 0.0, 8.0);
    float bias = max(shadowDepthBias, shadowDepthBias * slope);

    float lit = 0.0;
    vec2 texel = 1.0 / vec2(textureSize(shadowMap, 0));
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float closest = texture(shadowMap, proj.xy + vec2(x, y) * texel).r;
            lit += (proj.z - bias > closest) ? 0.0 : 1.0;
        }
    }
    lit /= 9.0;
    return mix(shadowMinFactor, 1.0, lit);
}

// Especular suave (Blinn-Phong), solo para superficies duras/mojadas —
// torres (bracket puntual en render_map_objects_3d) y agua (siempre que
// useTerrainMask+isWater estén activos). La cámara es de ángulo fijo
// (CAMERA_PITCH_DEG, nunca rota), así que viewDir es una constante más,
// igual que sunDir/fillDir — no depende de la posición del fragmento.
uniform vec3 viewDir;          // normalizado, apunta DESDE la superficie HACIA la cámara
uniform float specularStrength; // 0 por defecto; solo >0 mientras se dibujan torres
const float SPECULAR_SHININESS = 20.0;   // bajo = brillo ancho/suave, no un glint puntual
const float SPECULAR_STRENGTH_WATER = 0.35;

// Máscaras del terreno (1 texel por tile, sin filtrar — bordes nítidos).
// Solo el material del terreno prende useTerrainMask; las formas inmediatas
// (torres, enemigos, ...) que comparten este shader la dejan en 0 y usan
// directo el color de vértice, sin tocar texture0/texture1.
uniform float useTerrainMask;
uniform sampler2D texture0;   // R: 1 = tile de camino
uniform sampler2D texture1;   // R: 1 = tile de agua
uniform sampler2D texture2;   // R: máscara de agua supersampleada + mipmaps, ver foamMask
uniform vec3 pathColor;
uniform vec3 waterColor;      // tinte plano de agua (constants.COLOR_WATER)
uniform vec3 waterEdgeColor;  // borde/sombra del agua (constants.COLOR_WATER_EDGE)
uniform vec2 mapSize;  // (width, height) del mapa en tiles

// Los 4 overlays de bioma de abajo son adaptaciones de los shaders 2D
// homónimos (assets/{water,dune,grass,rock}.glsl) a la malla continua del
// terreno 3D: en vez de reconstruir world-space desde
// screenPos/camera_offset/zoom, usan directamente `fragTexCoord * mapSize`
// (espacio de grilla, camera-independiente). Mutuamente excluyentes por
// bioma vía sus *_alpha (BIOME_*_STYLES en constants.odin) salvo cáusticas,
// que depende de la máscara de agua en vez del bioma. Los nombres de las
// funciones de ruido llevan prefijo por overlay porque cada shader 2D
// original definía su propio hash/valueNoise con implementación distinta
// (no se pueden compartir bajo el mismo nombre).

// ── Cáusticas de agua (water.glsl, Phase 2 — la Phase 1 de blur+threshold
// existía para simular bordes curvos en una malla de tiles rectos; acá el
// borde del agua ya es geometría real con desnivel diagonal) ───────────────
uniform float causticsTime;

vec4 mod289(vec4 x) {
    return x - floor(x / 289.0) * 289.0;
}
vec4 permute(vec4 x) {
    return mod289((x * 34.0 + 1.0) * x);
}
vec4 snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    vec3 i  = floor(v + dot(v, vec3(C.y)));
    vec3 x0 = v - i + dot(i, vec3(C.x));
    vec3 g  = step(x0.yzx, x0.xyz);
    vec3 l  = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.x;
    vec3 x2 = x0 - i2 + C.y;
    vec3 x3 = x0 - 0.5;
    vec4 p =
      permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0))
                            + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                            + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    vec4 j  = p - 49.0 * floor(p / 49.0);
    vec4 x_ = floor(j / 7.0);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x  = (x_ * 2.0 + 0.5) / 7.0 - 1.0;
    vec4 y  = (y_ * 2.0 + 0.5) / 7.0 - 1.0;
    vec4 h  = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 g0 = vec3(a0.xy, h.x);
    vec3 g1 = vec3(a0.zw, h.y);
    vec3 g2 = vec3(a1.xy, h.z);
    vec3 g3 = vec3(a1.zw, h.w);
    vec4 m  = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    vec4 m2 = m * m;
    vec4 m3 = m2 * m;
    vec4 m4 = m2 * m2;
    vec3 grad =
      -6.0 * m3.x * x0 * dot(x0, g0) + m4.x * g0 +
      -6.0 * m3.y * x1 * dot(x1, g1) + m4.y * g1 +
      -6.0 * m3.z * x2 * dot(x2, g2) + m4.z * g2 +
      -6.0 * m3.w * x3 * dot(x3, g3) + m4.w * g3;
    vec4 px = vec4(dot(x0,g0), dot(x1,g1), dot(x2,g2), dot(x3,g3));
    return 42.0 * vec4(grad, dot(m4, px));
}

float water_caustics(vec3 pos) {
    vec4 n = snoise(pos);
    pos -= 0.07 * n.xyz;
    pos *= 1.62;
    n = snoise(pos);
    pos -= 0.07 * n.xyz;
    n = snoise(pos);
    pos -= 0.07 * n.xyz;
    n = snoise(pos);
    return n.w;
}

// Cobertura de agua suavizada: box blur (radio 2 tiles) sobre la máscara
// binaria + smoothstep en el punto medio — mismo truco que la Phase 1 de
// water.glsl (que ahí redondeaba rects sobre una textura de pantalla; acá
// redondea la máscara de tiles). El borde real de agua en 2D quedaba
// "blobby" porque el blur difumina las esquinas de la grilla en curvas; con
// la máscara cruda (1 texel = 1 tile, filtro POINT) el límite sigue la
// grilla al pixel y se ve en escalera/recto — de ahí el pedido de
// redondearlo "como antes".
float waterCoverage(vec2 uv) {
    const int R = 2;
    float sum = 0.0;
    float total = 0.0;
    for (int x = -R; x <= R; x++) {
        for (int y = -R; y <= R; y++) {
            sum += texture(texture1, uv + vec2(float(x), float(y)) / mapSize).r;
            total += 1.0;
        }
    }
    return sum / total;
}

// worldPos ya está en unidades de tile — en 2D `p = worldPos_px / 32`
// porque 1 tile = 32px; acá 1 unidad de worldPos YA es 1 tile.
vec3 waterCausticsOverlay(vec2 worldPos, vec3 baseColor) {
    vec3 pos = vec3(worldPos.x, causticsTime * 0.75, worldPos.y) * 2.4;
    float w = mix(water_caustics(pos), water_caustics(pos + 1.0), 0.5);
    float intensity = exp(w * 4.0 - 1.0);
    vec3 causticTint = vec3(intensity) * baseColor;
    return mix(baseColor, causticTint, 0.30);
}

// ── Espuma de orilla ─────────────────────────────────────────────────────
// Línea continua alrededor de TODA el agua, no parches sueltos: blur de la
// máscara de agua + contraste (doble smoothstep) para sacar el contorno,
// variando el blur en el tiempo para que la línea "respire" — se contrae y
// vuelve, como las olas — en vez de quedar fija.
//
// El blur NO se arma a mano con un loop de muestreo (con la máscara de 1
// texel/tile de texture1 eso da parches cuadrados del tamaño de un tile,
// no una línea — se probó y se veía exactamente así de mal): texture2 es
// una versión supersampleada de la misma máscara CON MIPMAPS, y cada nivel
// de mipmap YA es un blur de radio distinto (el hardware promedia un área
// más grande en cada nivel siguiente). Animar el nivel de LOD con
// textureLod() da "cambiar el radio del blur" con una sola lectura de
// textura, continua y antialiaseada porque viene de un sampler bilineal,
// no de una grilla de tiles. El umbral de contraste se deja SIEMPRE en
// 0.5: en un borde recto eso cae justo en el límite real sin importar el
// radio (un blur simétrico da 0.5 exacto en el borde), así que el
// movimiento visible de la línea sale de la curvatura real de la costa
// (esquinas, entrantes — sobra en un mapa por tiles), no de desplazar el
// umbral a mano.
float foamHash21(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float foamValueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = foamHash21(i);
    float b = foamHash21(i + vec2(1.0, 0.0));
    float c = foamHash21(i + vec2(0.0, 1.0));
    float d = foamHash21(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// causticsTime avanza a WATER_ANIM_SPEED (0.4) unidades por segundo real —
// 1.0 acá da un ciclo de contracción/vuelta de ~16s reales (2π/(0.4×1.0)),
// bajado desde 2.2 (~7s, se veía demasiado rápido/pulsante) a pedido
// explícito de que el efecto sea sutil.
const float FOAM_CYCLE_SPEED = 1.0;
const float FOAM_MIN_LOD     = 2.5; // blur angosto, línea "recogida" — más lejos del borde
const float FOAM_MAX_LOD     = 5.5; // blur ancho, línea "avanza"
const float FOAM_HALF_WIDTH  = 0.045; // ancho de la línea en espacio de coverage — más angosta que antes (0.06), línea más fina/discreta

float foamMask(vec2 uv, vec2 worldPos) {
    float breathe = 0.5 + 0.5 * sin(causticsTime * FOAM_CYCLE_SPEED);
    float lod     = mix(FOAM_MIN_LOD, FOAM_MAX_LOD, breathe);

    float coverage = textureLod(texture2, uv, lod).r;
    float line = smoothstep(0.5 - FOAM_HALF_WIDTH, 0.5, coverage)
               - smoothstep(0.5, 0.5 + FOAM_HALF_WIDTH, coverage);

    // Variación de INTENSIDAD, no de presencia — nunca corta la línea a
    // cero, solo le da una textura de espuma menos uniforme que un trazo
    // parejo. Rango angostado (0.65-0.85, antes 0.55-1.0) y deriva más
    // lenta (0.08, antes 0.15) — mismo pedido de sutileza: menos contraste
    // entre el punto más y menos intenso, menos movimiento visible del
    // moteado.
    float tex = foamValueNoise(worldPos * 3.0 + causticsTime * 0.08);
    float intensity = mix(0.65, 0.85, smoothstep(0.3, 0.7, tex));

    return line * intensity;
}

// ── Dunas (dune.glsl, bioma DESERT) ─────────────────────────────────────────
uniform float duneSeed;
uniform float duneTime;
uniform float duneAlpha;
uniform float duneDensity;
uniform vec3  duneColor;

float duneHash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

float duneValueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = duneHash21(i);
    float b = duneHash21(i + vec2(1.0, 0.0));
    float c = duneHash21(i + vec2(0.0, 1.0));
    float d = duneHash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Ridged noise: pliega el value noise sobre su punto medio, así los valles
// (donde n≈0.5) se vuelven crestas afiladas en vez de mesetas suaves.
float ridged(vec2 p) {
    float n = duneValueNoise(p);
    return 1.0 - abs(n * 2.0 - 1.0);
}

// 4 octavas de ridged noise — forma grande de la duna, irregular.
float duneShape(vec2 p) {
    float sum = 0.0, amp = 0.55, freq = 1.0;
    for (int i = 0; i < 4; i++) {
        sum += ridged(p * freq) * amp;
        freq *= 2.15;
        amp *= 0.5;
    }
    return sum;
}

vec3 duneOverlay(vec2 worldPos) {
    vec2 p = worldPos * (duneDensity * 0.25) + duneSeed * 0.017;

    // Viento fijo en diagonal — todo el patrón queda perpendicular a esta
    // dirección, como dunas reales moldeadas por un viento dominante.
    vec2 wind_dir = normalize(vec2(0.94, 0.34));
    float along  = dot(p, wind_dir);
    float across = dot(p, vec2(-wind_dir.y, wind_dir.x));

    float shape = duneShape(vec2(along * 0.65, across) * 0.5 + vec2(duneTime * 0.01, 0.0));

    float wave1 = sin(across * 3.4 + shape * 3.0 + duneTime * 0.02);
    float wave2 = sin(across * 6.1 - shape * 2.0 + duneTime * 0.017 + 1.7);
    float lines1 = sign(wave1) * pow(abs(wave1), 0.5) * 0.5 + 0.5;
    float lines2 = sign(wave2) * pow(abs(wave2), 0.6) * 0.5 + 0.5;
    float lines  = mix(lines1, lines2, 0.4);

    float grain = duneValueNoise(p * 12.0);

    float shade = shape * 0.40 + lines * 0.48 + grain * 0.12;
    return duneColor * clamp(0.55 + shade * 0.70, 0.45, 1.30);
}

// ── Pasto (grass.glsl, biomas PLAIN/FOREST) — raymarch de "paja" ───────────
// El shader 2D original ancoraba una cámara fake (ro/rd fijos, mirando
// adelante-y-abajo) a la posición de mundo del fragmento y raymarcheaba un
// campo de blades — no es nuestra Camera3D real, es una textura procedural
// que se ve "adentro" de cada fragmento. Se reusa igual acá; lo único que
// cambia es de dónde sale `gPos` (antes screenPos/camera_offset/zoom, ahora
// world tile-space).
uniform float grassTime;
uniform float grassAlpha;
uniform float grassDensity;
uniform vec3  grassColor;

uint grassPcgHash(uint x) {
    x = x * 747796405u + 2891336453u;
    x = ((x >> ((x >> 28u) + 4u)) ^ x) * 277803737u;
    x = (x >> 22u) ^ x;
    return x;
}

float grassHash21(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    uint  n = q.x * 1664525u + q.y * 1013904223u;
    return float(grassPcgHash(n)) * (1.0 / 4294967295.0);
}

float grassValueNoise(vec2 p) {
    vec2 point = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = grassHash21(point);
    float b = grassHash21(point + vec2(1.0, 0.0));
    float c = grassHash21(point + vec2(0.0, 1.0));
    float d = grassHash21(point + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Ground plane en y=-1; blades: paredes finas en cada entero de x,z (tras
// el ×100 de la llamada). hash21(p.xz) le da a cada blade una altura random.
float grassMap(vec3 p) {
    if (p.y > -0.99) {
        return p.y + 1.0;
    }
    return min(
        p.y + 1.0 + grassHash21(p.xz) * 0.06,
        min(
            min(fract(p.x) / 50.0 + 0.01,  0.01 - fract(p.x) / 50.0 + 0.01),
            min(fract(p.z) / 50.0 + 0.01,  0.01 - fract(p.z) / 50.0 + 0.01)
        )
    );
}

vec4 grassOverlay(vec2 worldPos) {
    // density=1 en 2D → 1 unidad de mundo grass = 128px = 4 tiles (con
    // CELL_SIZE=32); acá worldPos ya está en tiles, así que el factor
    // equivalente es density/4.
    vec2 gPos = worldPos * (grassDensity / 4.0);

    vec3 ro = vec3(gPos.x, 0.25, gPos.y);
    vec3 rd = normalize(vec3(0.0, -0.4, 1.0));

    float t = 0.0;
    vec4  col = vec4(0.0);
    bool  hit = false;

    for (int i = 0; i < 128; i++) {
        vec3 p = ro + rd * t;

        float bladeX = floor(p.x * 100.0);
        float bladeZ = floor(p.z * 100.0);
        float windPhase = grassHash21(vec2(bladeX, bladeZ));
        float wind = sin(grassTime * 1.5 + windPhase * 6.2832) * 0.07
                     * max(0.0, p.y + 1.0);
        vec3 pw = vec3(p.x + wind, p.y, p.z);

        float d = grassMap(vec3(
            pw.x * 50.0,
            pw.y - grassValueNoise(pw.xz / 7.0) * 0.5,
            pw.z * 50.0
        ));

        t += d;

        if (d < 0.01) {
            float lightY = clamp(1.5 + p.y, 0.0, 1.5);
            float rnd    = grassHash21(vec2(bladeX, bladeZ) * 40.0);

            vec3 baseCol  = grassColor * 0.35;
            vec3 tipCol   = grassColor * 1.60 + vec3(0.06, 0.10, 0.0);
            vec3 bladeCol = mix(baseCol, tipCol, lightY * rnd * 0.1 + lightY * 0.4);

            col = vec4(bladeCol, 1.0);
            hit = true;
            break;
        }

        if (t > 10.0) break;
    }

    if (!hit) return vec4(0.0);
    return col;
}

// ── Roca agrietada (rock.glsl, bioma MOUNTAIN) — Voronoi F1/F2 ─────────────
uniform float rockSeed;
uniform float rockAlpha;
uniform float rockDensity;
uniform vec3  rockColor;

vec2 rockHash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

float rockHash1(vec2 p) {
    return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453123);
}

float rockValueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = rockHash1(i);
    float b = rockHash1(i + vec2(1.0, 0.0));
    float c = rockHash1(i + vec2(0.0, 1.0));
    float d = rockHash1(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 rockWarp(vec2 p, float amt) {
    float wx = rockValueNoise(p * 0.5 + 11.3) - 0.5;
    float wy = rockValueNoise(p * 0.5 + 47.9) - 0.5;
    return p + vec2(wx, wy) * amt;
}

// x,y = distancia a la celda más cercana (F1) y a la segunda (F2);
// z = hash de la celda ganadora (id de placa, para variar su tono).
vec3 rockVoronoi(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    float f1 = 8.0, f2 = 8.0;
    vec2 cell = n;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = rockHash2(n + g);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < f1) { f2 = f1; f1 = d; cell = n + g; }
            else if (d < f2) { f2 = d; }
        }
    }
    return vec3(sqrt(f1), sqrt(f2), rockHash1(cell));
}

vec3 rockOverlay(vec2 worldPos) {
    vec2 base = worldPos * (rockDensity * 0.25) + rockSeed * 0.013;

    vec2  pL = rockWarp(base * 0.45, 0.35) + 3.1;
    vec3  vL = rockVoronoi(pL);
    float edgeL  = vL.y - vL.x;
    float crackL = 1.0 - smoothstep(0.0, 0.035, edgeL);

    vec2  pM = rockWarp(base * 1.15, 0.30) + 91.7;
    vec3  vM = rockVoronoi(pM);
    float edgeM  = vM.y - vM.x;
    float crackM = 1.0 - smoothstep(0.0, 0.10, edgeM);

    vec2  pS = rockWarp(base * 2.8, 0.20) + 233.9;
    vec3  vS = rockVoronoi(pS);
    float edgeS  = vS.y - vS.x;
    float crackS = 1.0 - smoothstep(0.0, 0.08, edgeS);

    float crackFine = max(crackM * 0.75, crackS * 0.55);

    float plateShade = 0.75 + vL.z * 0.5;
    float fineShade  = mix(0.92, 1.08, vM.z);
    plateShade *= fineShade;

    float grain = mix(0.9, 1.1, rockHash1(floor(base * 9.0)));

    vec3 rockCol      = rockColor * plateShade * grain;
    vec3 crackColFine = rockColor * 0.35;
    vec3 crackColBig  = rockColor * 0.72;

    vec3 col = mix(rockCol, crackColBig, crackL);
    col      = mix(col, crackColFine, crackFine);
    return col;
}

void main() {
    vec3 base = fragColor.rgb;
    float isPath = 0.0;
    float isWater = 0.0;
    if (useTerrainMask > 0.5) {
        isPath = texture(texture0, fragTexCoord).r;
        base = mix(base, pathColor, isPath);

        // waterCoverage es un blur de 5x5 tiles — redondea la FORMA del
        // borde entre tiles de agua conectados (si no, se ve en escalera
        // sobre la grilla), pero por sí solo no sabe nada de la geometría
        // real: sangra tinte de agua sobre tiles de TIERRA vecinos
        // sin más, algo que con la tierra inclinándose suave hasta el agua
        // quedaba disimulado, pero desde que la orilla tiene un risco real
        // (ver Terrain_Corner_Category/_terrain_add_bank_wall en
        // rendering.odin) se ve como pedacitos de agua traslúcidos
        // flotando sobre tierra ya claramente separada, arriba del risco.
        // tileIsWater (texture1 sin blur, 1 texel/tile, POINT — el valor
        // crudo del PROPIO tile) recorta ambos términos a cero en
        // cualquier fragmento cuyo tile no sea agua, sin tocar la forma
        // redondeada que ve un tile de agua de verdad (ahí tileIsWater=1,
        // no cambia nada).
        float coverage = waterCoverage(fragTexCoord);
        float tileIsWater = texture(texture1, fragTexCoord).r;
        float isWaterRaw = smoothstep(0.38, 0.62, coverage);
        float edgeRaw = smoothstep(0.50, 0.62, coverage);
        isWater = isWaterRaw * tileIsWater;
        float waterEdge = (isWaterRaw - edgeRaw) * tileIsWater;

        if (isWater > 0.001) {
            base = mix(base, waterColor, isWater);
            base = mix(base, waterEdgeColor, waterEdge * 0.5);

            vec2 worldPos = fragTexCoord * mapSize;
            vec3 caustic = waterCausticsOverlay(worldPos, base);
            base = mix(base, caustic, isWater);

            float foam = foamMask(fragTexCoord, worldPos);
            base = mix(base, vec3(0.92, 0.97, 0.98), foam * 0.85);
        }

        float groundMix = (1.0 - isPath) * (1.0 - isWater);

        if (duneAlpha > 0.001) {
            vec2 worldPos = fragTexCoord * mapSize;
            vec3 dune = duneOverlay(worldPos);
            base = mix(base, dune, duneAlpha * groundMix);
        }

        if (rockAlpha > 0.001) {
            vec2 worldPos = fragTexCoord * mapSize;
            vec3 rock = rockOverlay(worldPos);
            base = mix(base, rock, rockAlpha * groundMix);
        }

        if (grassAlpha > 0.001) {
            vec2 worldPos = fragTexCoord * mapSize;
            vec4 grass = grassOverlay(worldPos);
            base = mix(base, grass.rgb, grass.a * grassAlpha * groundMix);
        }
    }

    vec3 n = normalize(fragNormal);
    float sunDiff = max(dot(n, sunDir), 0.0);
    float fillDiff = max(dot(n, fillDir), 0.0);
    float sf = shadow_factor(sunDiff);
    vec3 lit = ambient + sunColor * sunDiff * sf + fillColor * fillDiff;

    // Especular: en terreno solo sobre agua (isWater), en formas inmediatas
    // (torres) solo mientras specularStrength está prendido desde Odin.
    float specMask = (useTerrainMask > 0.5) ? isWater * SPECULAR_STRENGTH_WATER : specularStrength;
    if (specMask > 0.001) {
        vec3 halfVec = normalize(sunDir + viewDir);
        float spec = pow(max(dot(n, halfVec), 0.0), SPECULAR_SHININESS) * specMask;
        lit += vec3(spec);
    }

    // Clamp de seguridad: si las intensidades suman más de 1.0 en algún
    // canal, el color de base se satura a blanco y deja de notarse.
    lit = clamp(lit, 0.0, 1.0);

    finalColor = vec4(base * lit, fragColor.a);
}
