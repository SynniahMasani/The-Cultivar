// ================================================================
// THE CULTIVAR — Grow Light Script
// Version: 1.0
//
// A rezzable grow light that detects nearby Cultivar plants
// and broadcasts a speed bonus to their grow scripts.
//
// HOW IT WORKS:
//   Every SCAN_INTERVAL seconds the light runs llSensor to
//   find nearby objects. When it detects a Cultivar plant
//   (by name prefix "TC_Plant" or "TC_Pot"), it broadcasts
//   a LIGHT_BONUS message on GROW_LIGHT_CHAN. Plant grow
//   scripts listen on this channel and reduce their stage
//   duration when they receive the bonus.
//
//   The bonus is applied once per stage — the plant records
//   whether the light bonus has been applied this stage so
//   it doesn't stack. When the plant advances to the next
//   stage it clears the flag, ready for the next bonus.
//
// LIGHT TIERS (set via owner menu):
//   Standard Light  : -15% stage duration
//   LED Panel       : -25% stage duration
//   Full Spectrum   : -35% stage duration  (premium version)
//
// RANGE: 5 meters (covers a standard grow room footprint)
//
// PRIM LINK STRUCTURE:
//   Link 1 (root) : Light body / hood
//   Link 2        : Bulb prim (glows and changes color)
//   Link 3        : Beam prim (cone pointing down, alpha)
//   Link 4        : Status indicator (on/off, tier)
//
// POWER STATES:
//   ON  — scanning, broadcasting bonus, full glow
//   OFF — no scan, no bonus, dim
//   AUTO — on between 6am–10pm (SL server time), off overnight
//           (SL server time via llGetWallclock)
// ================================================================

integer GROW_LIGHT_CHAN  = -999111222; // broadcast channel for plant bonus
integer TC_OBJECT_PING_CHAN = -111222333;

integer DCHAN_OWNER = -130001;
integer g_listenOwner;
integer g_listenRegister;

key     g_ownerKey    = NULL_KEY;
string  g_ownerName   = "";
integer g_hudChannel  = 0;
integer g_registered  = FALSE;

// Power state: "on" | "off" | "auto"
string  g_powerState  = "on";
integer g_lightOn     = TRUE;

// Light tier: 0=standard 1=led 2=full_spectrum
integer g_tier        = 0;
list    TIER_NAMES    = ["Standard",    "LED Panel",  "Full Spectrum"];
list    TIER_BONUS    = [15,            25,           35           ]; // % reduction
list    TIER_COLORS   = [<1.0, 0.95, 0.8>, <0.7, 0.85, 1.0>, <1.0, 0.8, 1.0>];
// Standard = warm white, LED = cool blue-white, Full Spectrum = purple-pink

// Scan interval (seconds)
float   SCAN_INTERVAL = 60.0; // check every minute
float   SCAN_RANGE    = 5.0;  // meters

// How many plants found last scan
integer g_plantsFound = 0;

// ----------------------------------------------------------------
integer deriveHUDChannel(key id)
{
    string h = llGetSubString((string)id, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|grow_light");
    llSetTimerEvent(8.0);
}

// ----------------------------------------------------------------
// Check auto schedule — is the light supposed to be on right now?
// ----------------------------------------------------------------
integer autoShouldBeOn()
{
    float wallClock = llGetWallclock(); // seconds since midnight SLT
    float hour      = wallClock / 3600.0;
    // On between 6:00 and 22:00 SLT
    return (hour >= 6.0 && hour < 22.0);
}

// ----------------------------------------------------------------
// Determine effective on/off state
// ----------------------------------------------------------------
integer isEffectivelyOn()
{
    if (g_powerState == "off")  return FALSE;
    if (g_powerState == "on")   return TRUE;
    if (g_powerState == "auto") return autoShouldBeOn();
    return FALSE;
}

// ----------------------------------------------------------------
// Update all light visuals based on current state
// ----------------------------------------------------------------
updateVisuals()
{
    g_lightOn = isEffectivelyOn();
    vector bulbColor = llList2Vector(TIER_COLORS, g_tier);

    if (g_lightOn)
    {
        // Bulb full glow
        llSetLinkPrimitiveParamsFast(2, [
            PRIM_COLOR, ALL_SIDES, bulbColor, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.35,
            PRIM_POINT_LIGHT, TRUE, bulbColor, 1.0, 6.0, 0.5
        ]);
        // Beam cone (link 3) — semi-transparent downward cone
        llSetLinkPrimitiveParamsFast(3, [
            PRIM_COLOR, ALL_SIDES, bulbColor, 0.12,
            PRIM_GLOW,  ALL_SIDES, 0.05
        ]);
        // Status prim
        string tierName = llList2String(TIER_NAMES, g_tier);
        string autoStr  = (g_powerState == "auto") ? " [AUTO]" : "";
        llSetLinkPrimitiveParamsFast(4, [
            PRIM_COLOR, ALL_SIDES, <0.2, 0.9, 0.2>, 1.0,
            PRIM_TEXT,
                "✓ " + tierName + autoStr + "\n" +
                "-" + (string)llList2Integer(TIER_BONUS, g_tier) + "% grow time\n" +
                (g_plantsFound > 0 ?
                    (string)g_plantsFound + " plant" +
                    (g_plantsFound > 1 ? "s" : "") + " in range" :
                    "No plants in range"),
                <0.2, 0.9, 0.2>, 1.0
        ]);
    }
    else
    {
        // Dim / off
        llSetLinkPrimitiveParamsFast(2, [
            PRIM_COLOR, ALL_SIDES, <0.3, 0.3, 0.3>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.0,
            PRIM_POINT_LIGHT, FALSE, ZERO_VECTOR, 0.0, 0.0, 0.0
        ]);
        llSetLinkPrimitiveParamsFast(3, [
            PRIM_COLOR, ALL_SIDES, <0.3, 0.3, 0.3>, 0.0
        ]);
        string reason = (g_powerState == "off") ? "OFF" :
                        "AUTO — waiting for 6am SLT";
        llSetLinkPrimitiveParamsFast(4, [
            PRIM_COLOR, ALL_SIDES, <0.8, 0.2, 0.2>, 1.0,
            PRIM_TEXT,  reason, <0.8, 0.2, 0.2>, 1.0
        ]);
    }

    // Main hover text
    if (g_lightOn)
        llSetText("THE CULTIVAR\nGrow Light [" +
                  llList2String(TIER_NAMES, g_tier) + "]\n" +
                  "-" + (string)llList2Integer(TIER_BONUS, g_tier) + "% grow time",
                  llList2Vector(TIER_COLORS, g_tier), 1.0);
    else
        llSetText("THE CULTIVAR\nGrow Light [OFF]",
                  <0.5, 0.5, 0.5>, 0.7);
}

// ----------------------------------------------------------------
// Broadcast bonus to all nearby plants
// ----------------------------------------------------------------
broadcastBonus()
{
    if (!g_lightOn) return;
    integer bonus = llList2Integer(TIER_BONUS, g_tier);
    // Plants listening on GROW_LIGHT_CHAN will apply this
    llRegionSay(GROW_LIGHT_CHAN,
        "TC_LIGHT_BONUS|" + (string)bonus + "|" +
        (string)llGetKey() + "|" + (string)llGetOwner());
}

// ----------------------------------------------------------------
// OWNER MENU
// ----------------------------------------------------------------
showOwnerMenu()
{
    if (g_listenOwner) llListenRemove(g_listenOwner);
    g_listenOwner = llListen(DCHAN_OWNER, "", g_ownerKey, "");

    string stateLabel;
    if      (g_powerState == "on")   stateLabel = "State: ON";
    else if (g_powerState == "off")  stateLabel = "State: OFF";
    else                             stateLabel = "State: AUTO";

    llDialog(g_ownerKey,
        "=== GROW LIGHT ===\n" +
        llList2String(TIER_NAMES, g_tier) + "\n" +
        stateLabel + "  •  " +
        (string)g_plantsFound + " plant" +
        (g_plantsFound != 1 ? "s" : "") + " in range",
        ["Turn On", "Turn Off", "Auto Mode",
         "Standard", "LED Panel", "Full Spectrum",
         "Close"],
        DCHAN_OWNER);
    llSetTimerEvent(30.0);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey   = llGetOwner();
        g_ownerName  = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);

        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");

        updateVisuals();
        llSetTimerEvent(SCAN_INTERVAL);
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer change)     { if (change & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        // Registration timeout
        if (!g_registered && g_listenRegister != 0)
        {
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            // Not a critical failure for the light — it works without HUD
        }

        // Auto schedule check
        if (g_powerState == "auto")
        {
            integer shouldBeOn = autoShouldBeOn();
            if (shouldBeOn != g_lightOn)
                updateVisuals();
        }

        // Sensor scan for nearby plants
        if (isEffectivelyOn())
        {
            llSensor("", NULL_KEY, ACTIVE | PASSIVE, SCAN_RANGE,
                     PI); // full sphere scan
        }

        llSetTimerEvent(SCAN_INTERVAL);
    }

    sensor(integer num_detected)
    {
        g_plantsFound = 0;
        integer i;
        for (i = 0; i < num_detected; i++)
        {
            string detName = llDetectedName(i);
            // Match Cultivar plant objects by name prefix
            if (llSubStringIndex(detName, "TC_Plant") == 0 ||
                llSubStringIndex(detName, "TC_Pot")   == 0)
            {
                g_plantsFound++;
            }
        }

        if (g_plantsFound > 0)
        {
            broadcastBonus();
            updateVisuals(); // refresh plant count in status text
        }
    }

    no_sensor()
    {
        if (g_plantsFound != 0)
        {
            g_plantsFound = 0;
            updateVisuals();
        }
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);
        if (toucher != g_ownerKey)
        {
            llRegionSayTo(toucher, 0,
                "This grow light belongs to " + g_ownerName + ".");
            return;
        }
        pingHUD();
        llLinksetDataWrite("light_intent", "owner_menu");
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            llSetTimerEvent(SCAN_INTERVAL);

            string intent = llLinksetDataRead("light_intent");
            llLinksetDataDelete("light_intent");
            if (intent == "owner_menu") showOwnerMenu();
        }

        else if (channel == DCHAN_OWNER && id == g_ownerKey)
        {
            llSetTimerEvent(SCAN_INTERVAL);
            if (g_listenOwner) { llListenRemove(g_listenOwner); g_listenOwner = 0; }

            if (msg == "Turn On")        g_powerState = "on";
            else if (msg == "Turn Off")  g_powerState = "off";
            else if (msg == "Auto Mode") g_powerState = "auto";
            else if (msg == "Standard")      g_tier = 0;
            else if (msg == "LED Panel")     g_tier = 1;
            else if (msg == "Full Spectrum") g_tier = 2;

            updateVisuals();
            llLinksetDataWrite("light_power", g_powerState);
            llLinksetDataWrite("light_tier",  (string)g_tier);
        }
    }
}
