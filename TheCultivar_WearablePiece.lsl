// ================================================================
// THE CULTIVAR  -  Wearable Piece Script
// Version: 1.0
// Lives inside: TC_Pipe, TC_Bong, TC_DabRig (wearable objects)
//
// Unlike the Smokeable temp-attach (which is disposable and tied
// to jar use), these are persistent wearable accessories the
// player keeps in their inventory and attaches manually.
// They don't consume flower directly  -  the player uses their
// HUD smoke menu as usual, and the piece script picks up the
// TC_SMOKED event to play the right visual effects.
//
// PIECE TYPES (set g_pieceType at top of script per object):
//   "pipe"     -  right hand, classic bowl piece
//   "bong"     -  left hand, full glass piece
//   "dab_rig"  -  right hand, concentrate rig
//
// WHAT THIS SCRIPT DOES:
//   1. On attach, registers with the owner's HUD via TC_PING
//   2. Listens on the owner's HUD channel for TC_SMOKED events
//   3. When TC_SMOKED fires, plays piece-appropriate particles
//      and sound effects matching the item quality
//   4. Owner can touch the worn piece to see a mini menu
//      (check strain, toggle effects, detach)
//   5. On TC_SESSION_SYNC, bumps up the effect intensity
//      to "session mode" (more particles, richer glow)
//
// PARTICLE LAYERS:
//   Idle (while attached, between hits) : very faint ambient wisp
//   Hit (on TC_SMOKED or TC_SESSION_SYNC) : full burst, 6 seconds
//   Session mode idle : medium ambient, quality-colored glow ring
//
// PRIM STRUCTURE:
//   Keep to 1 - 3 prims. Link 1 = body, Link 2 = bowl/nail glow,
//   Link 3 = smoke emitter tip (optional, falls back to link 1)
// ================================================================

// !! CHANGE THIS PER OBJECT !!
string  PIECE_TYPE = "pipe"; // "pipe" | "bong" | "dab_rig"

integer TC_OBJECT_PING_CHAN = -111222333;

integer DCHAN_TOUCH = -114001;

integer g_listenRegister;
integer g_listenHUD;
integer g_listenTouch;

key     g_ownerKey    = NULL_KEY;
string  g_ownerName   = "";
integer g_hudChannel  = 0;
integer g_registered  = FALSE;
integer g_attached    = FALSE;

// Current strain loaded (from last TC_SMOKED)
string  g_currentStrain  = "";
string  g_currentQuality = "";

// Session mode
integer g_inSession  = FALSE;

// Effects state
integer g_effectsOn     = TRUE;

// Hit-particle pending state  -  used instead of llSleep() so
// the event queue remains responsive during the hit duration.
integer g_hitInProgress = FALSE;
vector  g_hitCol        = <0.4, 0.4, 0.4>; // saved colour for post-hit glow restore

// Attachment points per piece type
list PIECE_ATTACH_POINTS = ["pipe",   "bong",  "dab_rig"];
list PIECE_ATTACH_IDS    = [ATTACH_RHAND, ATTACH_LHAND, ATTACH_RHAND];

// ----------------------------------------------------------------
integer deriveHUDChannel(key id)
{
    string h = llGetSubString((string)id, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0, 0.85, 0.2>;
    if (quality == "loud")   return <0.2, 0.85, 0.3>;
    if (quality == "exotic") return <0.7, 0.3,  1.0>;
    return <0.6, 0.5, 0.35>;
}

// ----------------------------------------------------------------
// Ping HUD to register
// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|wearable_" + PIECE_TYPE);
    llSetTimerEvent(8.0);
}

// ----------------------------------------------------------------
// Idle ambient  -  very faint, barely noticeable when just worn
// ----------------------------------------------------------------
startIdleParticles()
{
    if (!g_effectsOn || !g_attached) return;
    vector col = <0.5, 0.5, 0.5>;
    if (g_currentQuality != "") col = qualColor(g_currentQuality);
    float alpha = 0.05;
    if (g_inSession) alpha = 0.2;

    llLinkParticleSystem(3, [
        PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                   PSYS_PART_INTERP_SCALE_MASK |
                                   PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     col,
        PSYS_PART_END_COLOR,       <0.9, 0.9, 0.9>,
        PSYS_PART_START_ALPHA,     alpha,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.015, 0.015, 0.0>,
        PSYS_PART_END_SCALE,       <0.006, 0.006, 0.0>,
        PSYS_PART_MAX_AGE,         3.5,
        PSYS_SRC_BURST_RATE,       1.5,
        PSYS_SRC_BURST_PART_COUNT, 1,
        PSYS_SRC_BURST_SPEED_MIN,  0.01,
        PSYS_SRC_BURST_SPEED_MAX,  0.025,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        0.2
    ]);
}

// ----------------------------------------------------------------
// Hit burst  -  fires on TC_SMOKED
// ----------------------------------------------------------------
playHitParticles(string quality)
{
    if (!g_effectsOn) return;
    vector col = qualColor(quality);

    // Dab rig gets a different, denser burst (concentrate is potent)
    integer isDab   = (PIECE_TYPE == "dab_rig");
    float   alpha   = 0.6;
    integer count   = 6;
    float   maxAge  = 4.0;
    float   srcAge  = 1.8;
    if (isDab) { alpha = 0.75; count = 10; maxAge = 5.0; srcAge = 2.5; }

    llLinkParticleSystem(3, [
        PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                   PSYS_PART_INTERP_SCALE_MASK |
                                   PSYS_PART_WIND_MASK |
                                   PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     col,
        PSYS_PART_END_COLOR,       <0.95, 0.95, 0.95>,
        PSYS_PART_START_ALPHA,     alpha,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.04, 0.04, 0.0>,
        PSYS_PART_END_SCALE,       <0.11, 0.11, 0.0>,
        PSYS_PART_MAX_AGE,         maxAge,
        PSYS_SRC_BURST_RATE,       0.07,
        PSYS_SRC_BURST_PART_COUNT, count,
        PSYS_SRC_BURST_SPEED_MIN,  0.025,
        PSYS_SRC_BURST_SPEED_MAX,  0.07,
        PSYS_SRC_MAX_AGE,          srcAge,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        0.3
    ]);

    // Bowl/nail glow (link 2) flares on hit
    float hitGlow = 0.18;
    if (isDab) hitGlow = 0.25;
    llSetLinkPrimitiveParamsFast(2, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_GLOW,  ALL_SIDES, hitGlow
    ]);
    llPlaySound("piece_hit", 0.5);

    // Schedule idle restore via timer instead of blocking with llSleep
    g_hitCol        = col;
    g_hitInProgress = TRUE;
    llSetTimerEvent(srcAge + 1.0);
}

// ----------------------------------------------------------------
// Update bowl/nail link based on current state
// ----------------------------------------------------------------
updateBowlGlow()
{
    if (!g_attached) return;
    vector col = <0.4, 0.4, 0.4>;
    if (g_currentQuality != "") col = qualColor(g_currentQuality);
    float glow = 0.0;
    if (g_currentQuality != "")
    {
        glow = 0.02;
        if (g_inSession) glow = 0.08;
    }

    llSetLinkPrimitiveParamsFast(2, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_GLOW,  ALL_SIDES, glow
    ]);
}

// ----------------------------------------------------------------
// Hover text  -  shown while worn
// ----------------------------------------------------------------
updateHoverText()
{
    if (!g_attached) return;

    string typeLabel;
    if      (PIECE_TYPE == "pipe")    typeLabel = "Pipe ?";
    else if (PIECE_TYPE == "bong")    typeLabel = "Bong ?";
    else if (PIECE_TYPE == "dab_rig") typeLabel = "Dab Rig ?";

    string strainLine = "No strain loaded";
    if (g_currentQuality != "") strainLine = g_currentQuality + " " + g_currentStrain;
    string sessionStr = "";
    if (g_inSession) sessionStr = "  ?  ? Session";
    string textQuality = "reggie";
    if (g_currentQuality != "") textQuality = g_currentQuality;

    llSetText("THE CULTIVAR  -  " + typeLabel + "\n" +
              strainLine + sessionStr,
              qualColor(textQuality), 0.85);
}

// ----------------------------------------------------------------
// Owner touch menu  -  mini controls while wearing
// ----------------------------------------------------------------
showTouchMenu()
{
    if (g_listenTouch) llListenRemove(g_listenTouch);
    g_listenTouch = llListen(DCHAN_TOUCH, "", g_ownerKey, "");

    string effectsLabel = "Effects: OFF";
    if (g_effectsOn) effectsLabel = "Effects: ON";
    string dialogItem = "Nothing loaded";
    if (g_currentQuality != "") dialogItem = g_currentQuality + " " + g_currentStrain;
    string dialogSession = "";
    if (g_inSession) dialogSession = "In session";
    llDialog(g_ownerKey,
        "=== " + llToUpper(PIECE_TYPE) + " ===\n" +
        dialogItem + "\n" +
        dialogSession,
        [effectsLabel, "Clear Strain", "Detach", "Close"],
        DCHAN_TOUCH);
    llSetTimerEvent(20.0);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);

        // Always listen on HUD channel and channel 0 for registration
        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");
        llListen(g_hudChannel, "", NULL_KEY, "");
    }

    on_rez(integer start_param) { llResetScript(); }

    attach(key attachedTo)
    {
        if (attachedTo != NULL_KEY)
        {
            g_attached  = TRUE;
            g_ownerKey  = llGetOwner();
            g_ownerName = llKey2Name(g_ownerKey);
            g_hudChannel = deriveHUDChannel(g_ownerKey);

            // Register with HUD
            if (g_listenRegister) llListenRemove(g_listenRegister);
            g_listenRegister = llListen(0, "", NULL_KEY, "");
            llListen(g_hudChannel, "", NULL_KEY, "");
            pingHUD();

            updateHoverText();
        }
        else
        {
            // Detached  -  clean up
            g_attached   = FALSE;
            g_inSession  = FALSE;
            g_registered = FALSE;
            llParticleSystem([]);
            llLinkParticleSystem(3, []);
            llSetLinkPrimitiveParamsFast(2, [PRIM_GLOW, ALL_SIDES, 0.0]);
            llSetTimerEvent(0.0);
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    timer()
    {
        // ── End of hit burst: restore bowl glow and idle particles ─
        if (g_hitInProgress)
        {
            g_hitInProgress = FALSE;
            llSetTimerEvent(0.0);
            float idleGlow = 0.02;
            if (g_inSession) idleGlow = 0.07;
            llSetLinkPrimitiveParamsFast(2, [
                PRIM_COLOR, ALL_SIDES, g_hitCol, 1.0,
                PRIM_GLOW,  ALL_SIDES, idleGlow
            ]);
            startIdleParticles();
            return;
        }

        // ── Registration timeout or touch menu timeout ────────────
        if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
        if (g_listenTouch)    { llListenRemove(g_listenTouch);    g_listenTouch    = 0; }
        llSetTimerEvent(0.0);
    }

    touch_start(integer nd)
    {
        if (llDetectedKey(0) != g_ownerKey) return;
        if (g_attached) showTouchMenu();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // HUD Registration
        if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            llSetTimerEvent(0.0);
            updateBowlGlow();
            startIdleParticles();
        }

        // HUD channel events  -  same channel the jar uses, so piece reacts too
        else if (channel == g_hudChannel)
        {
            // TC_SMOKED  -  someone smoked (this player, from jar or direct)
            if (cmd == "TC_SMOKED")
            {
                g_currentStrain  = llList2String(parts, 1);
                g_currentQuality = llList2String(parts, 2);
                // React to the smoke event  -  doesn't matter what device they used
                playHitParticles(g_currentQuality);
                updateHoverText();
            }

            // TC_SESSION_SYNC  -  this player joined a session
            else if (cmd == "TC_SESSION_SYNC")
            {
                g_currentStrain  = llList2String(parts, 1);
                g_currentQuality = llList2String(parts, 2);
                g_inSession      = TRUE;
                updateBowlGlow();
                startIdleParticles();
                updateHoverText();
                playHitParticles(g_currentQuality);
            }

            // TC_SESSION_END  -  session over
            else if (cmd == "TC_SESSION_END")
            {
                g_inSession = FALSE;
                updateBowlGlow();
                startIdleParticles();
                updateHoverText();
            }

            // TC_PASS_RECEIVED  -  someone passed to this player
            else if (cmd == "TC_PASS_RECEIVED")
            {
                g_currentStrain  = llList2String(parts, 1);
                g_currentQuality = llList2String(parts, 2);
                playHitParticles(g_currentQuality);
                updateHoverText();
            }
        }

        // TOUCH MENU
        else if (channel == DCHAN_TOUCH && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenTouch) { llListenRemove(g_listenTouch); g_listenTouch = 0; }

            if (msg == "Effects: ON")
            {
                g_effectsOn = FALSE;
                llLinkParticleSystem(3, []);
                llOwnerSay("Effects turned off.");
            }
            else if (msg == "Effects: OFF")
            {
                g_effectsOn = TRUE;
                startIdleParticles();
                llOwnerSay("Effects turned on.");
            }
            else if (msg == "Clear Strain")
            {
                g_currentStrain  = "";
                g_currentQuality = "";
                llLinkParticleSystem(3, []);
                updateBowlGlow();
                updateHoverText();
            }
            else if (msg == "Detach")
            {
                llDetachFromAvatar();
            }
        }
    }
}
