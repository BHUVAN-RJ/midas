#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The first-open black hole (founder, 2026-10-31): a port of the WebGL shader in
// docs/mockups/onboarding-blackhole-v9-2026-10-31.html, numbers in docs/briefs/onboarding-build.md
// section 4. Applied with .layerEffect to the intro's canvas: every pixel near the hole sends a light
// ray past it, bent by its gravity (units of the horizon radius rs). Rays that fall in are black;
// rays that cross the disc pick up the Silk gas; rays that escape read the screen behind, bent.

constant float DISC_IN = 3.0;
constant float DISC_OUT = 7.0;
constant float MARCH_RADIUS = 20.0;
constant float SOURCE_DIST = 6.0;

static float midasHash(float2 cell) {
    return fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
}

static float midasValueNoise(float2 point) {
    float2 cell = floor(point);
    float2 local = fract(point);
    float2 blend = local * local * (3.0 - 2.0 * local);
    float a = midasHash(cell);
    float b = midasHash(cell + float2(1.0, 0.0));
    float c = midasHash(cell + float2(0.0, 1.0));
    float d = midasHash(cell + float2(1.0, 1.0));
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

static float midasTurbulence(float2 point) {
    float total = 0.0;
    float weight = 0.5;
    for (int octave = 0; octave < 4; octave++) {
        total += weight * midasValueNoise(point);
        point = point * 2.03 + float2(1.7, 9.2);
        weight *= 0.5;
    }
    return total;
}

struct MidasHoleInputs {
    float2 hole;
    float scale;
    float charge;
    float time;
    float seed;
    float whirl;
    float2 size;
    half4 paper;
};

// The screen round the hole turns with it as the charge builds: a light whirlpool.
static float2 midasWhirlpool(float2 point, MidasHoleInputs inputs) {
    float2 relative = point - inputs.hole;
    float reach = length(relative);
    float twist = inputs.whirl * inputs.charge * 1.2 * exp(-reach / 120.0);
    float c = cos(twist);
    float s = sin(twist);
    return inputs.hole + float2(c * relative.x - s * relative.y, s * relative.x + c * relative.y);
}

static half3 midasSceneAt(float2 rawPoint, SwiftUI::Layer layer, MidasHoleInputs inputs) {
    float2 point = inputs.scale > 0.05 ? midasWhirlpool(rawPoint, inputs) : rawPoint;
    if (point.x < 0.0 || point.y < 0.0 || point.x > inputs.size.x || point.y > inputs.size.y) {
        return inputs.paper.rgb;
    }
    half4 sampled = layer.sample(point);
    // The canvas paints its own paper; anything see-through falls back to paper
    return mix(inputs.paper.rgb, sampled.rgb, sampled.a);
}

// Silk (founder, round 10): hairline white threads that wind with the spin, nothing else.
static float midasSilk(float radius, float angle, float spin, MidasHoleInputs inputs) {
    float turn = angle + spin;
    // atan jumps at -pi/pi: blend the gas with its copy one turn back so there is no seam
    float wrap = (angle + 3.14159) / 6.28318;
    float2 here = float2(log(radius) * 14.0 + turn * 2.2, turn * 5.2);
    float2 back = float2(log(radius) * 14.0 + (turn - 6.28318) * 2.2, (turn - 6.28318) * 5.2);
    float fine = mix(midasTurbulence(here + inputs.seed), midasTurbulence(back + inputs.seed), wrap);
    float edgeIn = smoothstep(DISC_IN - 0.04, DISC_IN + 0.1, radius);
    float edgeOut = 1.0 - smoothstep(DISC_OUT * 0.9, DISC_OUT, radius);
    return edgeIn * edgeOut * (0.04 + 1.2 * smoothstep(0.5, 0.56, fine));
}

// Hot gas at a point on the disc: light (rgb) and how opaque it is (a).
static float4 midasDiscLight(float3 hit, MidasHoleInputs inputs) {
    float radius = length(hit);
    float angle = atan2(hit.y, hit.x);
    // Keplerian spin: inner gas laps the outer gas
    float spin = inputs.time * (0.6 + 1.6 * inputs.charge) * 9.0 * pow(radius, -1.5) + inputs.seed;
    float density = midasSilk(radius, angle, spin, inputs);
    // Thin-disc temperature: hottest just outside the inner edge
    float temperature = pow(DISC_IN / radius, 0.75) * pow(max(1.0 - sqrt(DISC_IN / radius), 0.0), 0.25);
    float brightness = 3.2 * pow(temperature / 0.49, 2.0);
    float redshift = sqrt(max(1.0 - 1.0 / radius, 0.0));
    float flicker = 0.88 + 0.24 * midasValueNoise(float2(radius * 1.3 + inputs.seed, inputs.time * 2.6));
    float light = brightness * redshift * density * flicker * (0.35 + 0.65 * inputs.charge);
    // White, a touch cool where dim; no colour of its own (DESIGN.md: no gold)
    float3 tint = mix(float3(0.86, 0.88, 0.92), float3(1.0), clamp(light * 0.8, 0.0, 1.0));
    return float4(tint * light, clamp(density * 0.95, 0.0, 0.95));
}

// One ray past the hole. q: the pixel relative to the hole in rs, y up.
static float3 midasTraceRay(float2 q, MidasHoleInputs inputs, thread bool &captured, thread float2 &sourceQ) {
    float3 position = float3(q, -MARCH_RADIUS);
    float3 direction = float3(0.0, 0.0, 1.0);
    float3 angular = cross(position, direction);
    float h2 = dot(angular, angular);
    float3 light = float3(0.0);
    float cover = 0.0;
    captured = false;
    sourceQ = q;
    for (int stepIndex = 0; stepIndex < 220; stepIndex++) {
        float radius = length(position);
        float dt = clamp(0.09 * radius, 0.03, 1.2);
        float3 before = position;
        // Photon bending: a = -3/2 h^2 r / |r|^5
        direction += -1.5 * h2 * position / pow(radius, 5.0) * dt;
        direction = normalize(direction);
        position += direction * dt;
        // The disc faces the eye: it lies in the plane z = 0
        if (before.z * position.z < 0.0) {
            float3 hit = mix(before, position, before.z / (before.z - position.z));
            float hitRadius = length(hit);
            if (hitRadius > DISC_IN - 0.3 && hitRadius < DISC_OUT) {
                float4 gas = midasDiscLight(hit, inputs);
                light += (1.0 - cover) * gas.rgb * gas.a;
                cover += (1.0 - cover) * gas.a;
            }
        }
        if (length(position) < 1.0) {
            captured = true;
            break;
        }
        if (position.z > MARCH_RADIUS && length(position) > MARCH_RADIUS) {
            break;
        }
    }
    if (!captured) {
        if (direction.z > 0.08) {
            // Follow the outgoing line back to the plane the screen sits on
            sourceQ = position.xy + direction.xy * (SOURCE_DIST - position.z) / direction.z;
        } else {
            captured = true;
        }
    }
    return light;
}

[[ stitchable ]] half4 midasBlackHole(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float2 hole,
    float scale,
    float charge,
    float time,
    float seed,
    float whirl,
    float dim,
    float flash,
    float waveRadius,
    float waveAmplitude,
    half4 paper,
    half4 ink
) {
    MidasHoleInputs inputs;
    inputs.hole = hole;
    inputs.scale = scale;
    inputs.charge = charge;
    inputs.time = time;
    inputs.seed = seed;
    inputs.whirl = whirl;
    inputs.size = size;
    inputs.paper = paper;

    float2 offset = position - hole;
    float dist = max(length(offset), 0.0001);
    float2 direction = offset / dist;

    // Shockwave: a travelling ripple that refracts the screen
    float front = dist - waveRadius;
    float bump = exp(-front * front / 900.0);
    float2 rippleShift = -direction * bump * waveAmplitude;

    half3 colour;
    float3 holeLight = float3(0.0);
    float shadow = 0.0;
    if (scale > 0.05) {
        float2 q = offset / scale;
        q.y = -q.y;
        float impact = length(q);
        if (impact < MARCH_RADIUS) {
            bool captured;
            float2 sourceQ;
            holeLight = midasTraceRay(q, inputs, captured, sourceQ);
            if (captured) {
                colour = half3(0.0);
                shadow = 1.0;
            } else {
                float2 sourcePoint = hole + float2(sourceQ.x, -sourceQ.y) * scale;
                colour = midasSceneAt(sourcePoint + rippleShift, layer, inputs);
            }
        } else {
            // Far out the bending is weak: deflection 2 rs / b, seen across the source distance
            float2 bentQ = q - (q / impact) * (2.0 / impact) * SOURCE_DIST;
            float2 sourcePoint = hole + float2(bentQ.x, -bentQ.y) * scale;
            colour = midasSceneAt(sourcePoint + rippleShift, layer, inputs);
        }
    } else {
        colour = midasSceneAt(position + rippleShift, layer, inputs);
    }

    // The hole eats light: the screen darkens round it as it charges
    float dimRadius = mix(120.0, 560.0, charge);
    float dimFalloff = exp(-pow(dist / dimRadius, 2.0));
    float dimAmount = clamp(dim * dimFalloff * (1.0 - shadow), 0.0, 0.985);
    float3 result = mix(float3(colour), float3(0.008), dimAmount);
    result += holeLight;
    result = mix(result, float3(ink.rgb), bump * clamp(waveAmplitude / 34.0, 0.0, 1.0) * 0.18);
    // The burst: a white flash from the centre
    result += float3(1.0) * flash * exp(-dist / 140.0);
    return half4(half3(clamp(result, 0.0, 1.0)), 1.0);
}
