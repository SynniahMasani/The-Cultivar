// ================================================================
// THE CULTIVAR — Session Object Effects Script
// Version: 1.0
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
//   Idle ambient    — soft rising smoke column, quality-tinted
//   Pass effect     — brief directional particle beam toward recipient
//   Session end     — fade out particles gracefully
//   Pulse           — ember link slowly pulses with llSetLinkColor
// ================================================================

integer SCHAN_CORE    = 3000;
integer SCHAN_EFFECTS = 3100;

// Current quality for color decisions
string  g_quality  = "reggie";
integer g_active   = FALSE;

// Pulse state
float   g_pulseVal = 0.0;
integer g_pulseDir = 1; // 1 = brightening, -1 = dimming
float   PULSE_STEP = 0.05;
float   PULSE_MIN  = 0.02;
float   PULSE_MAX  = 0.18;

// ----------------------------------------------------------------
// Quality color
// ----------------------------------------------------------------
vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0, 0.85, 0.2>;
    if (quality == "loud")   return <0.2, 0.85, 0.3>;
    if (quality == "exotic") return <0.7, 0.3,  1.0>;
    return <0.7, 0.6, 0.45>; // reggie
}

// ----------------------------------------------------------------
// Ambient rising smoke — the session centerpiece effect
// ----------------------------------------------------------------
startAmbientSmoke()
{
    vector col = qualColor(g_quality);
    llLinkParticleSystem(2, [
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_WIND_MASK |
            PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,           PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,      col,
        PSYS_PART_END_COLOR,        <0.9, 0.9, 0.9>,
        PSYS_PART_START_ALPHA,      0.45,
        PSYS_PART_END_ALPHA,        0.0,
        PSYS_PART_START_SCALE,      <0.04, 0.04, 0.0>,
        PSYS_PART_END_SCALE,        <0.12, 0.12, 0.0>,
        PSYS_PART_MAX_AGE,          6.0,
        PSYS_SRC_BURST_RATE,        0.25,
        PSYS_SRC_BURST_PART_COUNT,  3,
        PSYS_SRC_BURST_SPEED_MIN,   0.02,
        PSYS_SRC_BURST_SPEED_MAX,   0.06,
        PSYS_SRC_ACCEL,             <0.0, 0.0, 0.015>, // gentle upward drift
        PSYS_SRC_ANGLE_BEGIN,       0.0,
        PSYS_SRC_ANGLE_END,         0.2
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
// Glow ring setup — quality color, active session pulse
// ----------------------------------------------------------------
updateGlowRing()
{
    vector col = qualColor(g_quality);
    float  glow = g_active ? 0.08 : 0.0;
    llSetLinkPrimitiveParamsFast(3, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_GLOW,  ALL_SIDES, glow
    ]);
}

// ----------------------------------------------------------------
// Pass effect — directional particle beam from passer to receiver
// Emitted from link 4, aimed toward receiver's position
// ----------------------------------------------------------------
playPassEffect(key fromKey, key toKey)
{
    // Get positions
    list   fromInfo = llGetObjectDetails(fromKey, [OBJECT_POS]);
    list   toInfo   = llGetObjectDetails(toKey,   [OBJECT_POS]);

    if (llGetListLength(fromInfo) == 0 || llGetListLength(toInfo) == 0) return;

    vector fromPos = llList2Vector(fromInfo, 0);
    vector toPos   = llList2Vector(toInfo,   0);

    // Calculate direction and distance
    vector dir  = llVecNorm(toPos - fromPos);
    float  dist = llVecMag(toPos - fromPos);

    vector col = qualColor(g_quality);

    // Brief directional burst from link 4
    llLinkParticleSystem(4, [
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_EMISSIVE_MASK |
            PSYS_PART_TARGET_POS_MASK,
        PSYS_SRC_PATTERN,           PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_SRC_TARGET_KEY,        toKey,
        PSYS_PART_START_COLOR,      col,
        PSYS_PART_END_COLOR,        <1.0, 1.0, 1.0>,
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

    // Play pass sound
    llPlaySound("pass_whoosh", 0.6);

    // Clear after burst
    llSleep(2.0);
    llLinkParticleSystem(4, []);
}

// ----------------------------------------------------------------
// Ember pulse tick — called by timer
// Slowly oscillates glow on link 5
// ----------------------------------------------------------------
pulseTick()
{
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
// Session start — fire up all effects
// ----------------------------------------------------------------
onSessionStart(string quality)
{
    g_quality = quality;
    g_active  = TRUE;
    g_pulseVal = PULSE_MIN;

    startAmbientSmoke();
    updateGlowRing();
    llSetTimerEvent(0.15); // fast pulse tick
    llPlaySound("session_start", 0.6);
}

// ----------------------------------------------------------------
// Session end — graceful fade
// ----------------------------------------------------------------
onSessionEnd()
{
    g_active = FALSE;
    llSetTimerEvent(0.0);
    stopAmbientSmoke();
    llLinkParticleSystem(4, []);

    // Fade out glow ring
    llSetLinkPrimitiveParamsFast(3, [PRIM_GLOW, ALL_SIDES, 0.0]);
    llSetLinkPrimitiveParamsFast(5, [PRIM_GLOW, ALL_SIDES, 0.0]);
    llPlaySound("session_end", 0.4);
}

// ================================================================
default
{
    state_entry()
    {
        // Start dim until session activates
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
            // SESSION_START|quality
            onSessionStart(llList2String(parts, 1));
        }

        else if (cmd == "SESSION_END")
        {
            onSessionEnd();
        }

        else if (cmd == "PASS_EFFECT")
        {
            // PASS_EFFECT|fromKey|toKey
            key fromKey = (key)llList2String(parts, 1);
            key toKey   = (key)llList2String(parts, 2);
            playPassEffect(fromKey, toKey);
        }

        else if (cmd == "QUALITY")
        {
            // Quality update (in case it changes mid-session — future feature)
            g_quality = llList2String(parts, 1);
            if (g_active)
            {
                startAmbientSmoke();
                updateGlowRing();
            }
        }
    }
}
