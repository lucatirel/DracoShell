// DRACO v3 - compile-safe Windows Terminal shader
// Uses the official Windows Terminal pixel-shader interface:
// t0 = terminal texture, t1 = DRACO image.

Texture2D shaderTexture : register(t0);
Texture2D image         : register(t1);
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float Time;
    float Scale;
    float2 Resolution;
    float4 Background;
};

float segDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001));
    return length(pa - ba * h);
}

float lightning(float2 uv, float2 a, float2 b, float2 c, float width)
{
    float d1 = segDist(uv, a, b);
    float d2 = segDist(uv, b, c);
    float d = min(d1, d2);

    float core = 1.0 - smoothstep(width * 0.25, width, d);
    float glow = 1.0 - smoothstep(width, width * 5.0, d);
    return core + glow * 0.25;
}

float flashPulse(float speed, float phase)
{
    float s = 0.5 + 0.5 * sin(Time * speed + phase);
    return pow(saturate(s), 36.0);
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 terminal = shaderTexture.Sample(samplerState, tex);

    // Keep the text-heavy left side nearly untouched.
    float fxMask = smoothstep(0.42, 0.58, tex.x);

    float luma = dot(terminal.rgb, float3(0.2126, 0.7152, 0.0722));
    float darkMask = 1.0 - smoothstep(0.20, 0.68, luma);

    // -----------------------------------------------------------------
    // Responsive DRACO image:
    // preserve image ratio and anchor to the right, even in half-screen.
    // Asset ratio = 192 / 187.
    // -----------------------------------------------------------------
    float viewportAspect = Resolution.x / max(Resolution.y, 1.0);
    float assetAspect = 192.0 / 187.0;

    float wantedHeight = 0.84;
    float widthFromHeight = wantedHeight * assetAspect / max(viewportAspect, 0.1);

    float drawWidth = min(widthFromHeight, 0.49);
    float drawHeight = drawWidth * viewportAspect / assetAspect;

    float2 drawSize = float2(drawWidth, drawHeight);
    float2 origin = float2(0.985 - drawWidth, 0.5 - drawHeight * 0.5);

    float2 duv = (tex - origin) / drawSize;
    float inside =
        step(0.0, duv.x) * step(duv.x, 1.0) *
        step(0.0, duv.y) * step(duv.y, 1.0);

    float4 dragon = image.Sample(samplerState, saturate(duv));
    float dragonLuma = dot(dragon.rgb, float3(0.2126, 0.7152, 0.0722));

    // Suppress the dark star-field from the source crop.
    float dragonMask = inside * smoothstep(0.16, 0.40, dragonLuma);

    // -----------------------------------------------------------------
    // REAL LIGHTNING: background only.
    // Deliberately sparse, smooth, and mostly behind the dragon.
    // -----------------------------------------------------------------
    float f1 = flashPulse(1.30, 0.30);
    float f2 = flashPulse(0.92, 2.40);
    float f3 = flashPulse(1.58, 4.20);

    float bolt1 = lightning(
        tex,
        float2(0.57, 0.05),
        float2(0.64, 0.33),
        float2(0.59, 0.69),
        0.0017
    );

    float bolt2 = lightning(
        tex,
        float2(0.78, 0.00),
        float2(0.73, 0.27),
        float2(0.82, 0.58),
        0.0015
    );

    float bolt3 = lightning(
        tex,
        float2(0.94, 0.14),
        float2(0.88, 0.41),
        float2(0.92, 0.86),
        0.0014
    );

    float behindDragon = 1.0 - dragonMask * 0.90;
    float sky = fxMask * darkMask * behindDragon;

    terminal.rgb += float3(0.08, 0.62, 1.00) * bolt1 * f1 * 0.72 * sky;
    terminal.rgb += float3(0.53, 0.24, 1.00) * bolt2 * f2 * 0.60 * sky;
    terminal.rgb += float3(0.16, 0.37, 1.00) * bolt3 * f3 * 0.64 * sky;

    // -----------------------------------------------------------------
    // DRAGON BODY:
    // use the canonical MSI-derived crop as a watermark.
    // -----------------------------------------------------------------
    float breathe = 0.92 + 0.05 * sin(Time * 0.72);

    float3 steel = lerp(
        float3(0.10, 0.24, 0.52),
        float3(0.38, 0.43, 0.72),
        smoothstep(0.24, 0.72, dragonLuma)
    );

    terminal.rgb += steel * dragonMask * 0.44 * breathe * darkMask * fxMask;

    // -----------------------------------------------------------------
    // COLOURED REFLECTIONS ON THE DRAGON:
    // broad animated light sweeps, not fake lightning.
    // -----------------------------------------------------------------
    float cyanWave = 0.5 + 0.5 * sin(Time * 1.05 + duv.y * 6.0);
    float violetWave = 0.5 + 0.5 * sin(Time * 0.78 - duv.y * 5.0 + 2.1);

    float detail = smoothstep(0.28, 0.72, dragonLuma);
    float edgeBias = saturate(abs(duv.x - 0.5) * 1.35 + 0.15);

    float cyanReflection =
        smoothstep(0.68, 0.96, cyanWave) *
        detail * edgeBias * dragonMask;

    float violetReflection =
        smoothstep(0.72, 0.98, violetWave) *
        detail * edgeBias * dragonMask;

    terminal.rgb +=
        float3(0.04, 0.61, 1.00) *
        cyanReflection *
        0.24 *
        darkMask *
        fxMask;

    terminal.rgb +=
        float3(0.58, 0.22, 1.00) *
        violetReflection *
        0.18 *
        darkMask *
        fxMask;

    // Electric-blue eye; coordinates refer to the canonical crop.
    float2 eyeDelta = duv - float2(0.77, 0.31);
    float eyeDist2 = dot(eyeDelta, eyeDelta);

    float eyeHalo = 1.0 - smoothstep(0.0005, 0.0100, eyeDist2);
    float eyeCore = 1.0 - smoothstep(0.0000, 0.0012, eyeDist2);
    float eyePulse = 0.78 + 0.22 * (0.5 + 0.5 * sin(Time * 3.0));

    terminal.rgb +=
        float3(0.02, 0.48, 1.00) *
        eyeHalo * eyePulse * inside * 0.28 * darkMask * fxMask;

    terminal.rgb +=
        float3(0.70, 0.95, 1.00) *
        eyeCore * eyePulse * inside * 0.78 * darkMask * fxMask;

    return float4(saturate(terminal.rgb), terminal.a);
}

