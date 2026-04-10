// ================================================================
// THE CULTIVAR  -  Session Object Effects Script
// Version: 1.1
// Handles: All visual and audio effects for the session object.
//          Kept separate from core so effects bugs never affect
//          session logic, participant tracking, or passing.
//
// PRIM LINK STRUCTURE (session object):
//   Link 1 (root)  : Session object body (ashtray/centerpiece mesh)
//   Link 2         : Ambient smoke emitter (rises from center)
//   Link 3         : Glow ring / quality indicator
//   Link 4         : Pass effect emitter (brief beam on pass)
//   Link 5         : "Hot" ember glow (subtle, pulses)
//
// EFFECTS:
//   Idle ambient     -  continuous cloud/swirl smoke, quality-tinted
//   Pass effect      -  brief directional particle beam toward recipient
//   Session end      -  fade out particles gracefully
//   Pulse            -  ember link slowly pulses with llSetLinkColor
// ================================================================

integer SCHAN_CORE    = 3000;
integer SCHAN_EFFECTS = 3100;

// Current quality for color decisions
string  g_quality  = "reggie";
string  g_itemType = "joint";
integer g_active   = FALSE;

// Pulse state
float   g_pulseVal = 0.0;
integer g_pulseDir = 1; // 1 = brightening, -1 = dimming
float   PULSE_STEP = 0.05;
float   PULSE_MIN  = 0.02;
float   PULSE_MAX  = 0.18;

// Pass effect cleanup  -  unix time when link 4 particles can be cleared.
// PSYS_SRC_MAX_AGE stops the source automatically; this clears the
// particle system definition so it doesn't fire again on region-crossing.
integer g_passCleanupAt = 0;

// ----------------------------------------------------------------
// Quality start color (primary / glow ring / ember)
// ----------------------------------------------------------------
vector qualColor(string quality)
{
    if (quality == "mids")   return <0.22, 0.68, 0.24>;
    if (quality == "loud")   return <1.00, 0.12, 0.10>;
    if (quality == "exotic") return <1.00, 0.08, 0.80>;
    return <0.38, 0.28, 0.16>;
}

// ----------------------------------------------------------------
// Quality end color - used for particle interpolation.
// ----------------------------------------------------------------
vector qualColorEnd(string quality)
{
    if (quality == "mids")   return <0.60, 0.95, 0.62>;
    if (quality == "loud")   return <1.00, 0.52, 0.16>;
    if (quality == "exotic") return <0.10, 0.85, 1.00>;
    return <0.48, 0.46, 0.42>;
}

// ----------------------------------------------------------------
// Ambient rising smoke  -  the session centerpiece effect
// Accepts item-type tuning so blunts/spliffs can feel denser.
// ----------------------------------------------------------------
startAmbientSmoke()
{
    vector startCol = qualColor(g_quality);
    vector endCol   = qualColorEnd(g_quality);

    float startScale = 0.05;
    float endScale   = 0.18;
    integer burstCount = 4;
    float burstRate = 0.18;
    float startAlpha = 0.50;
    float maxAge = 7.0;
    float accelZ = 0.018;
    float angleEnd = 0.24;
    vector omega = <0.0, 0.0, 0.25>;

    if (g_itemType == "blunt")
    {
        startScale = 0.07;
        endScale   = 0.24;
        burstCount = 6;
        burstRate  = 0.15;
        startAlpha = 0.60;
        maxAge     = 8.5;
        accelZ     = 0.024;
        angleEnd   = 0.28;
        omega      = <0.0, 0.0, 0.40>;
    }
    else if (g_itemType == "spliff")
    {
        startScale = 0.06;
        endScale   = 0.20;
        burstCount = 5;
        burstRate  = 0.16;
        startAlpha = 0.55;
        maxAge     = 7.8;
        accelZ     = 0.021;
        angleEnd   = 0.26;
        omega      = <0.0, 0.0, 0.32>;
    }

    if (g_quality == "loud")
    {
        burstCount += 1;
        endScale   *= 1.08;
        maxAge     += 0.5;
        startAlpha += 0.05;
    }
    else if (g_quality == "exotic")
    {
        burstCount += 2;
        endScale   *= 1.15;
        maxAge     += 1.0;
        startAlpha += 0.10;
        omega       = <0.0, 0.0, 0.55>;
    }
    if (startAlpha > 0.90) startAlpha = 0.90;

    llLinkParticleSystem(2, [
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_WIND_MASK |
            PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,           PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,      startCol,
        PSYS_PART_END_COLOR,        endCol,
        PSYS_PART_START_ALPHA,      startAlpha,
        PSYS_PART_END_ALPHA,        0.0,
        PSYS_PART_START_SCALE,      <startScale, startScale, 0.0>,
        PSYS_PART_END_SCALE,        <endScale, endScale, 0.0>,
        PSYS_PART_MAX_AGE,          maxAge,
        PSYS_SRC_BURST_RATE,        burstRate,
        PSYS_SRC_BURST_PART_COUNT,  burstCount,
        PSYS_SRC_BURST_SPEED_MIN,   0.02,
        PSYS_SRC_BURST_SPEED_MAX,   0.07,
        PSYS_SRC_ACCEL,             <0.0, 0.0, accelZ>,
        PSYS_SRC_OMEGA,             omega,
        PSYS_SRC_ANGLE_BEGIN,       0.0,
        PSYS_SRC_ANGLE_END,         angleEnd
    ]);
}

// ----------------------------------------------------------------
// Stop ambient smoke
// ----------------------------------------------------------------
stopAmbientSmoke()
{
    llLinkParticleSystem(2, []);
}

// ----------------------------------------------------------------
// Glow ring setup  -  quality color, active session pulse
// ----------------------------------------------------------------
updateGlowRing()
{
    vector col = qualColor(g_quality);
    float  glow = g_active * 0.08;
    llSetLinkPrimitiveParamsFast(3, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_GLOW,  ALL_SIDES, glow
    ]);
}

// ----------------------------------------------------------------
// Pass effect  -  directional particle beam from passer to receiver
// Emitted from link 4, aimed toward receiver's position
// ----------------------------------------------------------------
playPassEffect(key fromKey, key toKey)
{
    list   fromInfo = llGetObjectDetails(fromKey, [OBJECT_POS]);
    list   toInfo   = llGetObjectDetails(toKey,   [OBJECT_POS]);

    if (llGetListLength(fromInfo) == 0 || llGetListLength(toInfo) == 0) return;

    vector fromPos = llList2Vector(fromInfo, 0);
    vector toPos   = llList2Vector(toInfo,   0);

    float  dist = llVecMag(toPos - fromPos);
    vector col = qualColor(g_quality);

    llLinkParticleSystem(4, [
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_EMISSIVE_MASK |
            PSYS_PART_TARGET_POS_MASK,
        PSYS_SRC_PATTERN,           PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_SRC_TARGET_KEY,        toKey,
        PSYS_PART_START_COLOR,      col,
        PSYS_PART_END_COLOR,        qualColorEnd(g_quality),
        PSYS_PART_START_ALPHA,      0.8,
        PSYS_PART_END_ALPHA,        0.0,
        PSYS_PART_START_SCALE,      <0.03, 0.03, 0.0>,
        PSYS_PART_END_SCALE,        <0.01, 0.01, 0.0>,
        PSYS_PART_MAX_AGE,          2.5,
        PSYS_SRC_BURST_RATE,        0.02,
        PSYS_SRC_BURST_PART_COUNT,  8,
        PSYS_SRC_BURST_SPEED_MIN,   dist * 0.3,
        PSYS_SRC_BURST_SPEED_MAX,   dist * 0.5,
        PSYS_SRC_MAX_AGE,           1.5,
        PSYS_SRC_ANGLE_BEGIN,       0.0,
        PSYS_SRC_ANGLE_END,         0.1
    ]);

    g_passCleanupAt = llGetUnixTime() + 2;
}

// ----------------------------------------------------------------
// Ember pulse tick  -  called by timer
// Slowly oscillates glow on link 5
// ----------------------------------------------------------------
pulseTick()
{
    if (g_passCleanupAt > 0 && llGetUnixTime() >= g_passCleanupAt)
    {
        g_passCleanupAt = 0;
        llLinkParticleSystem(4, []);
    }

    g_pulseVal += (float)g_pulseDir * PULSE_STEP;

    if (g_pulseVal >= PULSE_MAX)
    {
        g_pulseVal = PULSE_MAX;
        g_pulseDir = -1;
    }
    else if (g_pulseVal <= PULSE_MIN)
    {
        g_pulseVal = PULSE_MIN;
        g_pulseDir = 1;
    }

    vector emberCol = qualColor(g_quality) * 0.8;
    llSetLinkPrimitiveParamsFast(5, [
        PRIM_COLOR, ALL_SIDES, emberCol, 1.0,
        PRIM_GLOW,  ALL_SIDES, g_pulseVal
    ]);
}

// ----------------------------------------------------------------
// Session start  -  fire up all effects
// ----------------------------------------------------------------
onSessionStart(string quality, string itemType)
{
    g_quality = quality;
    if (itemType != "") g_itemType = itemType;
    g_active  = TRUE;
    g_pulseVal = PULSE_MIN;

    startAmbientSmoke();
    updateGlowRing();
    llSetTimerEvent(0.15);
}

// ----------------------------------------------------------------
// Session end  -  graceful fade
// ----------------------------------------------------------------
onSessionEnd()
{
    g_active = FALSE;
    llSetTimerEvent(0.0);
    stopAmbientSmoke();
    llLinkParticleSystem(4, []);

    llSetLinkPrimitiveParamsFast(3, [PRIM_GLOW, ALL_SIDES, 0.0]);
    llSetLinkPrimitiveParamsFast(5, [PRIM_GLOW, ALL_SIDES, 0.0]);
}

// ================================================================
default
{
    state_entry()
    {
        llSetLinkPrimitiveParamsFast(3, [PRIM_GLOW, ALL_SIDES, 0.0]);
        llSetLinkPrimitiveParamsFast(5, [PRIM_GLOW, ALL_SIDES, 0.0]);
    }

    timer()
    {
        if (g_active) pulseTick();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != SCHAN_EFFECTS) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (cmd == "SESSION_START")
        {
            // SESSION_START|quality|itemType
            onSessionStart(llList2String(parts, 1), llList2String(parts, 2));
        }

        else if (cmd == "SESSION_END")
        {
            onSessionEnd();
        }

        else if (cmd == "PASS_EFFECT")
        {
            key fromKey = (key)llList2String(parts, 1);
            key toKey   = (key)llList2String(parts, 2);
            playPassEffect(fromKey, toKey);
        }

        else if (cmd == "QUALITY")
        {
            // QUALITY|quality|itemType(optional)
            g_quality = llList2String(parts, 1);
            string newType = llList2String(parts, 2);
            if (newType != "") g_itemType = newType;
            if (g_active)
            {
                startAmbientSmoke();
                updateGlowRing();
            }
        }
    }
}
