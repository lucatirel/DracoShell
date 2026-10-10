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

float hash11(float p)
{
    return frac(sin(p * 127.1f) * 43758.5453123f);
}

float noise1(float p)
{
    float i = floor(p);
    float f = frac(p);
    f = f * f * (3.0f - 2.0f * f);
    return lerp(hash11(i), hash11(i + 1.0f), f);
}

float flashPulse(float speed, float phase)
{
    float x = saturate(sin(Time * speed + phase));
    return pow(x, 92.0f);
}

float verticalWindow(float y, float a, float b)
{
    return smoothstep(a, a + 0.026f, y) *
           (1.0f - smoothstep(b - 0.026f, b, y));
}

// Continuous jagged bolt: no per-band jumps, so no horizontal tearing.
float boltShape(float2 uv, float seed, float x0, float slope, float thickness)
{
    float y = uv.y;

    float epoch = floor(Time * 4.2f + seed);

    float n1 =
        noise1(y * 24.0f + seed * 17.0f + epoch * 1.37f);

    float n2 =
        noise1(y * 57.0f + seed * 31.0f + epoch * 0.63f);

    float n3 =
        noise1(y * 121.0f + seed * 7.0f + epoch * 0.29f);

    float jag =
        (n1 - 0.5f) * 0.042f +
        (n2 - 0.5f) * 0.016f +
        (n3 - 0.5f) * 0.006f;

    float x = x0 + slope * (y - 0.5f) + jag;
    float d = abs(uv.x - x);

    float core = 1.0f - smoothstep(0.00030f, thickness, d);
    float glow = 1.0f - smoothstep(thickness, thickness * 6.0f, d);

    return core + glow * 0.28f;
}

float4 main(PSInput pin) : SV_TARGET
{
    float2 uv = pin.uv;
    float4 terminal = shaderTexture.Sample(samplerState, uv);

    float luma = dot(terminal.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    float darkMask = 1.0f - smoothstep(0.16f, 0.60f, luma);

    // --------------------------------------------------------
    // RESPONSIVE DRAGON
    // Same visual scale around 16:9, adaptive on resize.
    // --------------------------------------------------------
    float viewportAspect = Resolution.x / max(Resolution.y, 1.0f);
    float refAspect = 16.0f / 9.0f;

    float dragonTop = 0.090f;
    float dragonHeight = 0.820f;

    float dragonWidth = 0.365f * (refAspect / max(viewportAspect, 0.70f));
    dragonWidth = clamp(dragonWidth, 0.245f, 0.500f);

    float dragonRight = 0.985f;
    float dragonLeft = dragonRight - dragonWidth;

    float2 dragonUV;
    dragonUV.x = (uv.x - dragonLeft) / dragonWidth;
    dragonUV.y = (uv.y - dragonTop) / dragonHeight;

    if (dragonUV.x >= 0.0f && dragonUV.x <= 1.0f &&
        dragonUV.y >= 0.0f && dragonUV.y <= 1.0f)
    {
        float4 dragon = image.Sample(samplerState, dragonUV);

        float breathe = 0.82f + 0.10f * sin(Time * 1.12f);

        float3 dragonTint = lerp(
            float3(0.20f, 0.44f, 1.00f),
            float3(0.54f, 0.30f, 1.00f),
            saturate(dragonUV.x * 0.80f)
        );

        terminal.rgb +=
            dragonTint *
            dragon.a *
            0.43f *
            breathe *
            darkMask;

        // Bright electric-blue eye.
        float2 eye = dragonUV - float2(0.84258f, 0.31968f);

        float eyeHalo = exp(-dot(eye, eye) * 300.0f);
        float eyeCore = exp(-dot(eye, eye) * 1750.0f);

        float eyePulse =
            0.72f +
            0.28f * (0.5f + 0.5f * sin(Time * 4.20f));

        terminal.rgb +=
            float3(0.04f, 0.46f, 1.00f) *
            eyeHalo *
            0.28f *
            eyePulse *
            darkMask;

        terminal.rgb +=
            float3(0.56f, 0.94f, 1.00f) *
            eyeCore *
            0.72f *
            eyePulse *
            darkMask;
    }

    // --------------------------------------------------------
    // FAST STORM
    // Continuous bolts, anchored to dragon, multi-colour flashes.
    // --------------------------------------------------------
    float stormLeft = max(0.0f, dragonLeft - dragonWidth * 0.22f);
    float rightMask =
        smoothstep(stormLeft, dragonLeft + dragonWidth * 0.18f, uv.x);

    float x1 = dragonLeft + dragonWidth * 0.64f;
    float x2 = dragonLeft + dragonWidth * 0.84f;
    float x3 = dragonLeft + dragonWidth * 0.46f;
    float x4 = dragonLeft + dragonWidth * 0.73f;

    float f1 = flashPulse(2.10f, 0.35f);
    float f2 = flashPulse(1.58f, 2.20f);
    float f3 = flashPulse(2.80f, 4.10f);
    float f4 = flashPulse(1.95f, 5.55f);

    float main1 =
        boltShape(uv, 1.3f, x1, -0.105f, 0.00195f) *
        verticalWindow(uv.y, 0.08f, 0.74f);

    float main2 =
        boltShape(uv, 5.9f, x2, 0.070f, 0.00182f) *
        verticalWindow(uv.y, 0.18f, 0.67f);

    float main3 =
        boltShape(uv, 9.7f, x3, 0.045f, 0.00170f) *
        verticalWindow(uv.y, 0.14f, 0.54f);

    float main4 =
        boltShape(uv, 13.2f, x4, -0.035f, 0.00162f) *
        verticalWindow(uv.y, 0.30f, 0.82f);

    float branch1 =
        boltShape(uv, 3.7f, x1 + dragonWidth * 0.09f, 0.34f, 0.00128f) *
        verticalWindow(uv.y, 0.27f, 0.43f);

    float branch2 =
        boltShape(uv, 7.2f, x2 - dragonWidth * 0.10f, -0.38f, 0.00120f) *
        verticalWindow(uv.y, 0.41f, 0.58f);

    float branch3 =
        boltShape(uv, 11.4f, x3 + dragonWidth * 0.10f, 0.31f, 0.00116f) *
        verticalWindow(uv.y, 0.20f, 0.34f);

    float branch4 =
        boltShape(uv, 15.8f, x4 - dragonWidth * 0.08f, -0.29f, 0.00112f) *
        verticalWindow(uv.y, 0.50f, 0.66f);

    float cyanLightning =
        (main1 + branch1 * 0.85f) * f1;

    float violetLightning =
        (main2 + branch2 * 0.90f) * f2;

    float blueLightning =
        (main3 + branch3 * 0.82f) * f3;

    float magentaLightning =
        (main4 + branch4 * 0.76f) * f4;

    terminal.rgb +=
        float3(0.08f, 0.68f, 1.00f) *
        cyanLightning *
        0.82f *
        rightMask *
        darkMask;

    terminal.rgb +=
        float3(0.52f, 0.25f, 1.00f) *
        violetLightning *
        0.68f *
        rightMask *
        darkMask;

    terminal.rgb +=
        float3(0.18f, 0.36f, 1.00f) *
        blueLightning *
        0.78f *
        rightMask *
        darkMask;

    terminal.rgb +=
        float3(0.90f, 0.20f, 0.82f) *
        magentaLightning *
        0.54f *
        rightMask *
        darkMask;

    float relief =
        cyanLightning +
        violetLightning +
        blueLightning +
        magentaLightning;

    terminal.rgb +=
        float3(0.45f, 0.70f, 1.00f) *
        relief *
        0.10f *
        rightMask *
        darkMask;

    float globalFlash =
        saturate(max(max(f1, f2), max(f3, f4))) *
        0.018f;

    terminal.rgb +=
        float3(0.06f, 0.15f, 0.40f) *
        globalFlash *
        rightMask *
        darkMask;

    return float4(saturate(terminal.rgb), terminal.a);
}

