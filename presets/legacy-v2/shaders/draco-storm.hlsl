struct PSInput
{
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

Texture2D shaderTexture : register(t0);
Texture2D image         : register(t1);
SamplerState samplerState : register(s0);

cbuffer PixelShaderSettings : register(b0)
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
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001f));
    return length(pa - ba * h);
}

float flash(float speed, float phase)
{
    float s = 0.5f + 0.5f * sin(Time * speed + phase);
    return smoothstep(0.90f, 1.0f, s);
}

float bolt(float2 uv, float2 p0, float2 p1, float2 p2, float2 p3, float width)
{
    float d = min(
        min(segDist(uv, p0, p1), segDist(uv, p1, p2)),
        segDist(uv, p2, p3)
    );

    float core = 1.0f - smoothstep(width * 0.30f, width, d);
    float glow = 1.0f - smoothstep(width, width * 5.0f, d);

    return core + glow * 0.28f;
}

float4 main(PSInput pin) : SV_TARGET
{
    float2 uv = pin.uv;
    float4 terminal = shaderTexture.Sample(samplerState, uv);

    // Keep the left side almost cost-free and visually clean.
    if (uv.x < 0.42f)
        return terminal;

    float luma = dot(terminal.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    float darkMask = 1.0f - smoothstep(0.20f, 0.72f, luma);

    // --------------------------------------------------------
    // RESPONSIVE DRAGON
    // --------------------------------------------------------
    float aspect = Resolution.x / max(Resolution.y, 1.0f);
    float refAspect = 16.0f / 9.0f;

    float dragonTop = 0.070f;
    float dragonHeight = 0.860f;
    float dragonWidth = 0.345f * (refAspect / max(aspect, 0.75f));
    dragonWidth = clamp(dragonWidth, 0.24f, 0.47f);

    float dragonRight = 0.985f;
    float dragonLeft = dragonRight - dragonWidth;

    float2 dragonUV;
    dragonUV.x = (uv.x - dragonLeft) / dragonWidth;
    dragonUV.y = (uv.y - dragonTop) / dragonHeight;

    if (dragonUV.x >= 0.0f && dragonUV.x <= 1.0f &&
        dragonUV.y >= 0.0f && dragonUV.y <= 1.0f)
    {
        float4 dragon = image.Sample(samplerState, dragonUV);

        // Static body tint with very subtle breathing.
        float breathe = 0.92f + 0.05f * sin(Time * 0.85f);

        float3 bodyTint = lerp(
            float3(0.16f, 0.32f, 0.72f),
            float3(0.35f, 0.20f, 0.78f),
            saturate(dragonUV.x)
        );

        terminal.rgb +=
            bodyTint *
            dragon.a *
            0.34f *
            breathe *
            darkMask;

        // ----------------------------------------------------
        // COLOURED REFLECTIONS ON THE DRAGON
        // These replace the old "fake lightning" look.
        // ----------------------------------------------------
        float cyanBand =
            1.0f - smoothstep(
                0.030f,
                0.145f,
                abs(dragonUV.x - (0.18f + dragonUV.y * 0.48f))
            );

        float violetBand =
            1.0f - smoothstep(
                0.025f,
                0.125f,
                abs(dragonUV.x - (0.80f - dragonUV.y * 0.38f))
            );

        float reflectionPulse =
            0.78f + 0.22f * (0.5f + 0.5f * sin(Time * 1.65f));

        terminal.rgb +=
            float3(0.05f, 0.56f, 1.00f) *
            cyanBand *
            dragon.a *
            0.20f *
            reflectionPulse *
            darkMask;

        terminal.rgb +=
            float3(0.55f, 0.20f, 1.00f) *
            violetBand *
            dragon.a *
            0.16f *
            darkMask;

        // Electric-blue eye.
        float2 eye = dragonUV - float2(0.84258f, 0.31968f);
        float eyeD = dot(eye, eye);

        float eyeHalo = saturate(1.0f - eyeD * 280.0f);
        float eyeCore = saturate(1.0f - eyeD * 2200.0f);
        float eyePulse = 0.78f + 0.22f * (0.5f + 0.5f * sin(Time * 3.20f));

        terminal.rgb +=
            float3(0.04f, 0.48f, 1.00f) *
            eyeHalo *
            0.30f *
            eyePulse *
            darkMask;

        terminal.rgb +=
            float3(0.72f, 0.95f, 1.00f) *
            eyeCore *
            0.82f *
            eyePulse *
            darkMask;
    }

    // --------------------------------------------------------
    // TRUE BACKGROUND LIGHTNING
    // Behind the dragon, not stuck to its scales.
    // --------------------------------------------------------
    float skyMask = smoothstep(0.48f, 0.63f, uv.x);

    float f1 = flash(1.10f, 0.20f);
    float f2 = flash(0.74f, 2.40f);
    float f3 = flash(1.46f, 4.70f);

    float b1 = bolt(
        uv,
        float2(0.60f, 0.05f),
        float2(0.69f, 0.26f),
        float2(0.63f, 0.47f),
        float2(0.72f, 0.74f),
        0.0022f
    );

    float b2 = bolt(
        uv,
        float2(0.83f, 0.00f),
        float2(0.76f, 0.19f),
        float2(0.86f, 0.42f),
        float2(0.80f, 0.67f),
        0.0019f
    );

    float b3 = bolt(
        uv,
        float2(0.94f, 0.14f),
        float2(0.88f, 0.32f),
        float2(0.96f, 0.52f),
        float2(0.90f, 0.88f),
        0.0017f
    );

    float cyanLightning = b1 * f1;
    float violetLightning = b2 * f2;
    float blueLightning = b3 * f3;

    terminal.rgb +=
        float3(0.08f, 0.62f, 1.00f) *
        cyanLightning *
        0.58f *
        skyMask *
        darkMask;

    terminal.rgb +=
        float3(0.52f, 0.22f, 1.00f) *
        violetLightning *
        0.50f *
        skyMask *
        darkMask;

    terminal.rgb +=
        float3(0.20f, 0.34f, 1.00f) *
        blueLightning *
        0.54f *
        skyMask *
        darkMask;

    // very subtle atmospheric flash
    float atmosphere = max(f1, max(f2, f3));
    terminal.rgb +=
        float3(0.04f, 0.08f, 0.20f) *
        atmosphere *
        0.025f *
        skyMask *
        darkMask;

    return float4(saturate(terminal.rgb), terminal.a);
}

