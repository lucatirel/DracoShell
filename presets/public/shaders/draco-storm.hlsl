// DRACO Noir: one cached atlas, no live fractal construction or blur.
// Atlas 3072 x 640: dragon [0..639], 12 storm masks in four RGB tiles
// [640..1663], contour routes [1664..2303], illustrated fire [2304..3071].
struct PSInput { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
Texture2D shaderTexture : register(t0);
Texture2D image : register(t1);
SamplerState samplerState : register(s0);
cbuffer PixelShaderSettings : register(b0)
{
    float Time;
    float Scale;
    float2 Resolution;
    float4 Background;
};

// BEGIN DRACO TIMING (also exercised by the Windows regression checks)
float hash11(float p)
{
    p = frac(p * 0.1031f);
    p *= p + 33.33f;
    return frac(p * (p + p));
}

float pulse(float t, float start, float peak, float end)
{
    return smoothstep(start, peak, t) * (1.0f - smoothstep(peak, end, t));
}

float cycleTime(float time, float duration)
{
    // Terminal's timer can be signed (older renderer casts performance ticks to int).
    // frac maps negative times into a running cycle too; clamping freezes everything.
    return frac(time / duration) * duration;
}

float stormStart(float epoch)
{
    return epoch == 0.0f ? 0.18f : 0.55f + hash11(epoch + 4.0f) * 1.20f;
}

float stormPeriod()
{
    return 3.6f;
}

float stormFlash(float t, float start)
{
    return max(max(pulse(t, start, start + 0.025f, start + 0.19f),
        0.50f * pulse(t, start + 0.25f, start + 0.27f, start + 0.40f)),
        0.32f * pulse(t, start + 0.70f, start + 0.73f, start + 0.90f));
}

float eyeEmission(float time)
{
    float eyeTime = cycleTime(time + 1.15f, 4.8f);
    return smoothstep(0.30f, 1.15f, eyeTime) *
        (1.0f - smoothstep(2.35f, 3.40f, eyeTime));
}
float stormPattern(float strikeIndex, float lane)
{
    // Each block visits all twelve primary shapes before repeating. Independent
    // lane offsets, companions and mirroring further vary the resulting storm.
    float block = floor(strikeIndex / 12.0f);
    float offset = floor(hash11(block + lane * 31.0f + 57.0f) * 12.0f);
    float slot = strikeIndex - block * 12.0f;
    float selection = slot * 5.0f + offset;
    return selection - floor(selection / 12.0f) * 12.0f;
}

float dischargePhase(float time)
{
    return cycleTime(time + 0.30f, 1.9f);
}

float dischargePower(float phase)
{
    return pulse(phase, 0.10f, 0.20f, 0.65f);
}
float mouthDischargeMask(float x, float y)
{
    return x > 0.75f && y > 0.365f && y < 0.665f ? 0.0f : 1.0f;
}

float typingSignal(float red, float green, float blue)
{
    return red > 2.5f/255.0f && red < 7.5f/255.0f &&
        green > 53.5f/255.0f && green < 58.5f/255.0f &&
        ((blue > 19.5f/255.0f && blue < 24.5f/255.0f) ||
         (blue > 79.5f/255.0f && blue < 99.5f/255.0f)) ? 1.0f : 0.0f;
}
float flameSignal(float red, float green, float blue)
{
    return red > 2.5f/255.0f && red < 7.5f/255.0f &&
        ((green > 5.5f/255.0f && green < 10.5f/255.0f) ||
         (green > 53.5f/255.0f && green < 58.5f/255.0f)) &&
        blue > 79.5f/255.0f && blue < 99.5f/255.0f ? 1.0f : 0.0f;
}
// END DRACO TIMING

// BEGIN DRACO LAYOUT (square in pixels, responsive to tall half-screen panes)
float dragonWidth(float aspect)
{
    float portraitBoost = 1.0f - smoothstep(0.95f, 1.45f, aspect);
    float widthLimit = 0.46f + 0.16f * portraitBoost;
    return min(widthLimit, 0.86f / max(aspect, 0.1f));
}
// END DRACO LAYOUT

float3 stormTint(float variant)
{
    // Keep the hot core chromatic too: a large white contribution washed colors out.
    return variant == 0.0f ? float3(0.06f, 0.72f, 1.00f) :
        (variant == 1.0f ? float3(0.64f, 0.16f, 1.00f) : float3(1.00f, 0.10f, 0.48f));
}

float3 stormLayer(float2 localUV, float variant, float strikeIndex, float lane)
{
    if (any(localUV < 0.0f) || any(localUV > 1.0f)) return float3(0.0f, 0.0f, 0.0f);
    float seed = hash11(strikeIndex + lane * 71.0f + 103.0f);
    if (seed > 0.5f) localUV.x = 1.0f - localUV.x;
    float pattern = stormPattern(strikeIndex, lane);
    float tile = floor(pattern / 3.0f);
    float channel = pattern - tile * 3.0f;
    float2 atlasUV = float2((640.5f + tile * 256.0f + localUV.x * 255.0f) / 3072.0f,
                           (0.5f + localUV.y * 639.0f) / 640.0f);
    float3 patterns = image.SampleLevel(samplerState, atlasUV, 0.0f).rgb;
    float bolt = channel == 0.0f ? patterns.r : (channel == 1.0f ? patterns.g : patterns.b);
    float companion = channel == 0.0f ? patterns.g : (channel == 1.0f ? patterns.b : patterns.r);
    float nextVariant = variant == 2.0f ? 0.0f : variant + 1.0f;
    return stormTint(variant) * (bolt + 0.30f * bolt * bolt * bolt) +
        stormTint(nextVariant) * companion * (0.25f + seed * 0.30f);
}

float3 contourDischarge(float2 dragonUV, float time)
{
    if (mouthDischargeMask(dragonUV.x, dragonUV.y) < 0.5f)
        return float3(0.0f, 0.0f, 0.0f);
    float phase = dischargePhase(time);
    float power = dischargePower(phase);
    if (power < 0.001f) return float3(0.0f, 0.0f, 0.0f);
    float epoch = floor((time + 0.30f) / 1.9f);
    float route = floor(hash11(epoch + 211.0f) * 3.0f);
    float2 atlasUV = float2((1664.5f + dragonUV.x * 639.0f) / 3072.0f,
                           (0.5f + dragonUV.y * 639.0f) / 640.0f);
    float4 paths = image.SampleLevel(samplerState, atlasUV, 0.0f);
    // Terminal loads custom images as WIC PBGRA. Decode this data tile back
    // to independent RGB routes; alpha >= 64/255 prevents an unstable division.
    paths.rgb /= max(paths.a, 64.0f / 255.0f);
    float progress = saturate((paths.a * 255.0f - 64.0f) / 191.0f);
    float filament = route == 0.0f ? paths.r : (route == 1.0f ? paths.g : paths.b);
    float travel = saturate((phase - 0.10f) / 0.55f);
    if (hash11(epoch + 73.0f) > 0.5f) travel = 1.0f - travel;
    float front = 1.0f - smoothstep(0.10f, 0.27f, abs(progress - travel));
    // Elongated discharges crawl along actual crest/jaw/coil curves. A dim tail
    // makes each path read as a connected filament, rather than scattered dots.
    float strength = filament * power * (0.12f + 0.88f * front);
    return float3(0.10f, 0.62f, 1.00f) * strength * 0.75f;
}

float3 paneStorm(float2 uv, float aspect, float strikeIndex, float variant)
{
    float3 result = float3(0.0f, 0.0f, 0.0f);
    // Three independently moving lanes span the PANE, never the dragon bounds.
    // Rotate in pixel space: branching remains undistorted after any resize.
    [unroll] for (int lane = 0; lane < 3; lane++)
    {
        float seed = hash11(strikeIndex + (float)lane * 47.0f + 301.0f);
        // Keep the outer spines inside the pane even when masks are mirrored.
        // Wide random offsets could clip an entire outer lane on signed clocks.
        float centerX = lane == 0 ? 0.14f + seed * 0.06f :
            (lane == 1 ? 0.46f + seed * 0.08f : 0.88f + seed * 0.04f);
        float centerY = 0.48f + (hash11(strikeIndex + (float)lane * 79.0f) - 0.5f) * 0.08f;
        float height = 0.84f + seed * 0.10f;
        float angle = (hash11(strikeIndex + (float)lane * 101.0f + 59.0f) - 0.5f) * 0.65f;
        float sine, cosine;
        sincos(angle, sine, cosine);
        float2 delta = (uv - float2(centerX, centerY)) * float2(aspect, 1.0f);
        float2 rotated = float2(delta.x * cosine - delta.y * sine,
            delta.x * sine + delta.y * cosine);
        float2 local = rotated / float2(height * 0.40f, height) + 0.5f;
        float tint = variant + (float)lane;
        tint -= floor(tint / 3.0f) * 3.0f;
        result += stormLayer(local, tint, strikeIndex, 10.0f + (float)lane);
    }
    return result * 0.80f;
}

// Three cached samples only inside the active breath. Two advected phases
// crossfade before their reset, carrying filaments outwards without a UV jump.
float4 fireSample(float2 q)
{
    q = saturate(q); // Never bleed into the adjacent contour tile.
    return image.SampleLevel(samplerState, float2(
        (2304.5f + q.x * 767.0f) / 3072.0f,
        (0.5f + q.y * 639.0f) / 640.0f), 0.0f);
}
float3 redFlame(float2 p, float age, float time)
{
    float front = 0.035f + 0.965f * smoothstep(0.0f, 0.34f, age);
    p.x /= front;
    p.y /= pow(front, 0.85f);
    if (p.x < -0.015f || p.x > 1.0f || p.y < -0.50f || p.y > 0.65f)
        return float3(0,0,0);
    // Shut off emission first; the last hot packet travels towards the tips.
    float emittedAge = age - saturate(p.x) * 0.27f;
    float power = smoothstep(0.0f, 0.12f, age) *
        (1.0f - smoothstep(0.56f, 0.72f, emittedAge));
    if (power < 0.001f) return float3(0,0,0);
    float flow = cycleTime(time, 16.0f);
    float flutter = smoothstep(0.02f, 0.22f, p.x);
    float tip = smoothstep(0.35f, 0.95f, p.x);
    float2 q = float2(0.074f + p.x * 0.87f, 0.425f + p.y * (0.87f / 1.10f));
    q.y += (sin(p.x * 16.0f - flow * 18.849556f) * 0.024f +
        sin(p.x * 29.0f - flow * 31.415927f + p.y * 13.0f) * 0.015f * tip) * flutter;
    q.x += sin(p.x * 23.0f + p.y * 17.0f - flow * 25.132741f) * 0.018f * flutter;
    float4 outline = fireSample(q);
    float phase = frac(flow * 1.5f);
    float phaseB = frac(phase + 0.5f);
    float travel = 0.22f * flutter;
    float2 qA = q - float2((phase - 0.5f) * travel,
        sin(p.x * 11.0f - flow * 18.849556f) * 0.012f * flutter);
    float2 qB = q - float2((phaseB - 0.5f) * travel,
        sin(p.x * 11.0f - flow * 18.849556f + 3.141593f) * 0.012f * flutter);
    float blend = abs(phase * 2.0f - 1.0f);
    float3 advected = lerp(fireSample(qA).rgb, fireSample(qB).rgb, blend);
    // Keep the accepted illustrated silhouette; flowing detail supplies most
    // of the visible color. Premultiplied RGB already contains texture alpha.
    float3 fire = lerp(outline.rgb, advected, 0.72f) * smoothstep(0.01f, 0.12f, outline.a);
    float tearing = 1.0f - tip * 0.38f * smoothstep(0.25f, 0.85f,
        sin(p.x * 46.0f - flow * 37.699112f + p.y * 39.0f));
    return fire * power * tearing;
}

float4 main(PSInput pin) : SV_TARGET
{
    float2 uv = pin.uv;
    float4 terminal = shaderTexture.Sample(samplerState, uv);
    // Hide our explicit control background; retain ordinary foreground pixels.
    // This checks a fixed output color, never characters or an input buffer.
    if (max(typingSignal(terminal.r, terminal.g, terminal.b),
        flameSignal(terminal.r, terminal.g, terminal.b)) > 0.5f)
        terminal.rgb = float3(5.0f, 8.0f, 22.0f) / 255.0f;
    float aspect = Resolution.x / max(Resolution.y, 1.0f);
    float drawWidth = dragonWidth(aspect);
    float drawHeight = drawWidth * aspect;
    // Reserve the right-hand quarter for the dragon's breath at every pane ratio.
    float2 origin = float2(0.76f - drawWidth, 0.5f - drawHeight * 0.5f);
    float3 difference = abs(terminal.rgb - Background.rgb);
    float backgroundMask = 1.0f - smoothstep(0.004f, 0.055f,
        max(difference.r, max(difference.g, difference.b)));
    if (backgroundMask < 0.001f) return terminal;

    float2 dragonUV = (uv - origin) / float2(drawWidth, drawHeight);

    // Three pane-wide lanes, independently positioned from the dragon layout.
    float clock = Time / stormPeriod();
    float epoch = floor(clock);
    float t = cycleTime(Time, stormPeriod());
    float start = stormStart(epoch);
    float flash = stormFlash(t, start);
    float variant = floor(hash11(epoch + 19.0f) * 3.0f);
    float3 tint = stormTint(variant);
    float burst = t < start + 0.24f ? 0.0f : (t < start + 0.65f ? 1.0f : 2.0f);
    float strikeIndex = epoch * 3.0f + burst;
    float3 greenBolt = float3(0.0f, 0.0f, 0.0f);
    // One global control sample, at a known output-cell background corner.
    // DECCARA makes that cell opaque without replacing its character. Default
    // backgrounds (including Background) may be transparent/premultiplied zero.
    // Load is exact: no filtering with neighboring text. Font glyphs have a
    // bearing at this top-left corner; use the second pixel too for edge strokes.
    float4 controlA = shaderTexture.Load(int3(0, 0, 0));
    float4 controlB = shaderTexture.Load(int3(1, 0, 0));
    float typing = max(typingSignal(controlA.r, controlA.g, controlA.b),
        typingSignal(controlB.r, controlB.g, controlB.b));
    float fireA = flameSignal(controlA.r, controlA.g, controlA.b);
    float fireB = flameSignal(controlB.r, controlB.g, controlB.b);
    float firePower = 0.0f;
    float3 flameColor = float3(0,0,0);
    if (max(fireA, fireB) > 0.5f)
    {
        float blue = fireA > 0.5f ? controlA.b : controlB.b;
        float age = (blue * 255.0f - 80.0f + 0.5f) / 20.0f;
        firePower = smoothstep(0.0f, 0.12f, age) * (1.0f - smoothstep(0.56f, 0.72f, age));
        float2 mouth = origin + float2(drawWidth * 0.94f, drawHeight * 0.45f);
        float length = min(drawWidth * 0.85f, 0.94f - mouth.x);
        float2 flameUV = (uv - mouth) / float2(length, length * aspect);
        flameColor = redFlame(flameUV, age, Time);
    }
    if (typing > 0.5f)
    {
        // Anonymous activity bit from the fixed control cell; never inspect characters,
        // caret changes, history, clipboard or input-buffer contents.
        float index = floor(Time / 0.22f);
        float3 cached = paneStorm(uv, aspect, index, 0.0f);
        float intensity = max(cached.r, max(cached.g, cached.b));
        // One bright, steady flash per queued press. The bridge provides the
        // on/off envelope, rather than an unrelated periodic shader oscillator.
        greenBolt = float3(0.08f, 1.00f, 0.18f) * intensity * 1.15f;
    }
    float3 rear = float3(0.0f, 0.0f, 0.0f);
    if (flash > 0.001f)
    {
        rear = paneStorm(uv, aspect, strikeIndex, variant);
    }

    if (all(dragonUV >= 0.0f) && all(dragonUV <= 1.0f))
    {
        float2 atlasUV = float2((0.5f + dragonUV.x * 639.0f) / 3072.0f,
                               (0.5f + dragonUV.y * 639.0f) / 640.0f);
        float4 dragon = image.SampleLevel(samplerState, atlasUV, 0.0f);
        // Shield the upper snout/fangs with the opaque artwork.
        terminal.rgb += flameColor * (1.0f - dragon.a) * backgroundMask;
        // Extract the eye from the artwork itself, so it follows its new shape/position.
        float eyeMask = smoothstep(0.08f, 0.35f, dragon.r - max(dragon.g, dragon.b));
        float contour = smoothstep(0.035f, 0.40f, max(dragon.g, dragon.b * 0.70f));
        float eyePulse = eyeEmission(Time);
        float3 body = dragon.rgb * (1.0f - eyeMask) * 0.36f;
        float3 eye = float3(1.00f, 0.035f, 0.055f) * eyeMask * eyePulse;
        terminal.rgb += (body + eye) * dragon.a * backgroundMask;
        if (firePower > 0.001f)
        {
            float heat = 1.0f - smoothstep(0.06f, 0.30f,
                length((dragonUV - float2(0.94f, 0.45f)) * float2(1.0f, 1.2f)));
            terminal.rgb += float3(1.0f, 0.18f, 0.025f) * heat * contour *
                firePower * 0.30f * dragon.a * (1.0f - eyeMask) * backgroundMask;
        }
        terminal.rgb += greenBolt * (1.0f - dragon.a * 0.90f) *
            (1.0f - eyeMask) * backgroundMask;

        if (flash > 0.001f)
        {
            // Transparent gaps reveal the storm; solid body shields most of it.
            terminal.rgb += rear * flash * (1.0f - dragon.a * 0.88f) *
                (1.0f - eyeMask) * backgroundMask;
            // Illuminate ALL blue contour strokes, including crest, jaw and lower coil.
            // A broad light front sweeps across them; no two narrow vertical slices.
            float arrival = saturate((t - start) / 0.24f);
            float front = 1.0f - smoothstep(0.06f, 0.32f,
                abs(dragonUV.y * 0.72f + dragonUV.x * 0.28f - arrival));
            float reflection = contour * flash * (0.42f + 0.58f * front);
            terminal.rgb += (tint * reflection * 0.52f) *
                dragon.a * (1.0f - eyeMask) * backgroundMask;
        }
        if (flash <= 0.001f && dragon.a > 0.01f && eyeMask < 0.99f)
        {
            terminal.rgb += contourDischarge(dragonUV, Time) *
                dragon.a * (1.0f - eyeMask) * backgroundMask;
        }
        return float4(saturate(terminal.rgb), terminal.a);
    }

    if (flash > 0.001f)
    {
        terminal.rgb += rear * flash * backgroundMask;
    }
    terminal.rgb += (flameColor + greenBolt) * backgroundMask;
    return float4(saturate(terminal.rgb), terminal.a);
}


