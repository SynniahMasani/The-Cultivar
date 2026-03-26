// ================================================================
// THE CULTIVAR  -  Plant Grow Script
// Version: 1.2
// Handles: Growth timer, stage progression, strain data,
//          yield and quality calculation, visual stage updates,
//          grow-light bonus (GROW_LIGHT_CHAN listener),
//          icon-based status indicator prim
//
// GROWTH STAGES:
//   0 = Empty pot (no seed planted)
//   1 = Seedling
//   2 = Vegetative
//   3 = Flowering
//   4 = Harvest Ready
//
// PRIM LINK STRUCTURE (your mesh):
//   Link 1 (root)    : Pot body
//   Link 5           : Seedling mesh
//   Link 4           : Vegetative mesh
//   Link 3           : Flowering mesh
//   Link 2           : Harvest-ready mesh
//   Link 6           : Harvest glow / sparkle emitter (optional, unused here)
//   Link 7           : Status indicator (transparent icon prim)
//                      Textures in root inventory:
//                        icon_water      f23ddfdc-776f-c296-d1bc-c7b1a0d9bb2a
//                        icon_fertilizer b150f9a0-953b-fb2c-c640-4dbf7b17f3b6
//                        icon_ready      d131fff9-e2d3-176f-c0e2-d31bdabf0767
//
// ================================================================
// Link numbers resolved at runtime via llGetLinkName
integer g_linkSeedling  = -1;  // Cannabis_Plant_1
integer g_linkVeg       = -1;  // Cannabis_Plant_2
integer g_linkFlower    = -1;  // Cannabis_Plant_3
integer g_linkHarvest   = -1;  // Cannabis_Plant_4
integer g_linkIndicator = -1;  // Indicator (optional, absent on premium pot)
// ---- Indicator iStates ----
integer STATE_NONE  = 0;
integer STATE_WATER = 1;
integer STATE_FERT  = 2;
integer STATE_READY = 3;
// ---- Icon texture UUIDs (also add these textures to the root prim's inventory) ----
string TEX_ICON_WATER = "f23ddfdc-776f-c296-d1bc-c7b1a0d9bb2a"; // icon_water
string TEX_ICON_FERT  = "b150f9a0-953b-fb2c-c640-4dbf7b17f3b6"; // icon_fertilizer
string TEX_ICON_READY = "d131fff9-e2d3-176f-c0e2-d31bdabf0767"; // icon_ready
// Internal channels (match across all plant scripts)
integer PCHAN_GROW    = 1000; // Grow <-> Interaction
integer PCHAN_PERSIST = 1100; // Grow <-> Persistence
// --- Strain Data Table ---
// Format per entry: strainName|qualityTier|baseYieldMin|baseYieldMax|flavorText
// qualityTier: 0=reggie 1=mids 2=loud 3=exotic
list STRAIN_DATA = [
    "Schwag",          0, 4,  8,  "Barely worth the effort.",
    "Zone Weed",       0, 3,  7,  "Comes through when you need it.",
    "Brown Frown",     0, 3,  6,  "It'll do.",
    "Blue Dream",      1, 8,  14, "Smooth and easy.",
    "Green Crack",     2, 14, 20, "Gets things moving fast.",
    "Gorilla Glue",    1, 8,  14, "Heavy and sticky.",
    "Sour Diesel",     1, 9,  16, "Fuel for the soul.",
    "OG Kush",         1, 9,  15, "The classic. Solid mids.",
    "Wedding Cake",    2, 15, 22, "Sweet and earthy.",
    "Zkittlez",        2, 14, 21, "Fruit forward and smooth.",
    "Gelato",          2, 15, 22, "Dessert in a blunt.",
    "Runtz",           3, 20, 28, "The one people talk about.",
    "Biscotti",        3, 21, 29, "Rich and complex.",
    "Jealousy",        3, 20, 28, "Hard to grow. Worth it.",
    "Lemon Cherry Gelato", 3, 22, 30, "Rare. Grows itself proud."
];
integer STRAIN_STRIDE = 5;
// --- Grow Time Table (seconds per full cycle by quality tier) ---
list GROW_TIMES = [2700, 7200, 14400, 28800];
// --- Current Plant State ---
string  g_strainName      = "";
integer g_qualityTier     = 0;   // 0=reggie 1=mids 2=loud 3=exotic
integer g_isHybrid        = FALSE; // TRUE if strain contains " x " (bred hybrid)
integer g_isLegendary     = FALSE; // TRUE if hybrid and suffix "[LEGENDARY]" present
integer g_stage           = 0;   // 0-4
integer g_stageStartTime  = 0;   // llGetUnixTime() when current stage began
integer g_stageDuration   = 0;   // seconds this stage should last
integer g_isWatered       = FALSE;
integer g_fertApplied     = FALSE;
integer g_fertTier        = 0;   // 0=basic 1=premium 2=exotic fert
string  g_potType         = "basic"; // "basic" or "premium"
integer g_potUsesLeft     = 5;   // basic = 5, premium = -1 (unlimited)
string  g_ownerName       = "";
key     g_ownerKey        = NULL_KEY;
integer g_hudChannel      = 0;
// Timer tick rate
float TIMER_INTERVAL = 30.0;
integer HOVER_FADE_SECS = 60;
// Grow light broadcast channel
integer GROW_LIGHT_CHAN = -999111222;
// Whether the light bonus has been applied this stage
integer g_lightBonusApplied = FALSE;
// ----------------------------------------------------------------
// Resolve functional prim link numbers by name at runtime.
// Works for both TC_Basic Pot and TC_Premium Pot without changes.
// ----------------------------------------------------------------
resolveLinks()
{
    g_linkSeedling  = -1;
    g_linkVeg       = -1;
    g_linkFlower    = -1;
    g_linkHarvest   = -1;
    g_linkIndicator = -1;
    integer total = llGetNumberOfPrims();
    integer i;
    for (i = 1; i <= total; i++)
    {
        string n = llGetLinkName(i);
        if      (n == "Cannabis_Plant_1") g_linkSeedling  = i;
        else if (n == "Cannabis_Plant_2") g_linkVeg       = i;
        else if (n == "Cannabis_Plant_3") g_linkFlower    = i;
        else if (n == "Cannabis_Plant_4") g_linkHarvest   = i;
        else if (n == "Indicator")        g_linkIndicator = i;
    }
}

// ----------------------------------------------------------------
// Look up strain data by name, return as list or empty list
// ----------------------------------------------------------------
list getStrainData(string strainName)
{
    integer len = llGetListLength(STRAIN_DATA);
    integer i;
    for (i = 0; i < len; i += STRAIN_STRIDE)
    {
        if (llList2String(STRAIN_DATA, i) == strainName)
            return llList2List(STRAIN_DATA, i, i + STRAIN_STRIDE - 1);
    }
    return [];
}
// ----------------------------------------------------------------
// Derive pot type from object name  -  always authoritative.
// "TC_Basic Pot" → "basic",  anything else → "premium".
// This overrides any value saved in llLinksetData, preventing
// corrupted or mismatched state from persisting.
// ----------------------------------------------------------------
string derivePotType()
{
    if (llSubStringIndex(llGetObjectName(), "Basic") != -1) return "basic";
    return "premium";
}
// ----------------------------------------------------------------
// Derive private HUD channel from owner UUID (matches HUD_Comms)
// ----------------------------------------------------------------
integer deriveHUDChannel(key ownerID)
{
    string hexSub = llGetSubString((string)ownerID, 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}
// ----------------------------------------------------------------
// Calculate stage duration accounting for pot bonus
// ----------------------------------------------------------------
integer calcStageDuration()
{
    integer fullCycle = llList2Integer(GROW_TIMES, g_qualityTier);
    integer stageDur  = fullCycle / 4; // 4 equal stages
    if (g_potType == "premium")
        stageDur = (integer)((float)stageDur * 0.95); // 5% faster
    if (g_isLegendary)
        stageDur = (integer)((float)stageDur * 0.85); // legendary hybrid: -15% time
    else if (g_isHybrid)
        stageDur = (integer)((float)stageDur * 0.92); // standard hybrid: -8% time
    return stageDur;
}
// ----------------------------------------------------------------
// Show or hide the status indicator icon prim.
// Pass STATE_NONE to hide it completely.
// ----------------------------------------------------------------
setIndicator(integer iState)
{
    if (g_linkIndicator == -1) return; // no indicator prim (e.g. premium pot)
    if (iState == STATE_NONE)
    {
        llSetLinkAlpha(g_linkIndicator, 0.0, ALL_SIDES);
        llSetLinkPrimitiveParamsFast(g_linkIndicator,
            [PRIM_TEXT,  "", ZERO_VECTOR, 0.0,
             PRIM_OMEGA, ZERO_VECTOR, 0.0, 0.0]);
        llLinkParticleSystem(g_linkIndicator, []);
        return;
    }
    // STATE_READY  -  harvest-ready spinning icon
    llSetLinkPrimitiveParamsFast(g_linkIndicator, [
        PRIM_TEXTURE, ALL_SIDES, TEX_ICON_READY, <1.0, 1.0, 0.0>, ZERO_VECTOR, 0.0,
        PRIM_TEXT,    "Ready to harvest!", <0.3, 0.8, 1.0>, 1.0,
        PRIM_OMEGA,   <0.0, 0.0, 1.0>, 0.25, 1.0
    ]);
    llSetLinkAlpha(g_linkIndicator, 1.0, ALL_SIDES);
    llLinkParticleSystem(g_linkIndicator, []);
}
// ----------------------------------------------------------------
// Rotate the indicator to face the owner's camera.
// Call from timer() while the indicator is visible.
// Requires the owner to have granted PERMISSION_TRACK_CAMERA.
// ----------------------------------------------------------------
updateIndicatorFacing()
{
    if (g_linkIndicator == -1) return;
    vector toCamera = llVecNorm(llGetCameraPos() - llGetPos());
    if (toCamera == ZERO_VECTOR) return;
    llSetLinkPrimitiveParamsFast(g_linkIndicator,
        [PRIM_ROTATION, llRotBetween(<1.0, 0.0, 0.0>, toCamera)]);
}
// ----------------------------------------------------------------
// Update plant visuals for current stage
// ----------------------------------------------------------------
updateVisuals()
{
    // Hide all plant meshes
    llSetLinkAlpha(g_linkSeedling, 0.0, ALL_SIDES);
    llSetLinkAlpha(g_linkVeg,      0.0, ALL_SIDES);
    llSetLinkAlpha(g_linkFlower,   0.0, ALL_SIDES);
    llSetLinkAlpha(g_linkHarvest,  0.0, ALL_SIDES);
    // Stop particles and clear PRIM_TEXT on all plant meshes
    llLinkParticleSystem(g_linkSeedling, []);
    llLinkParticleSystem(g_linkVeg,      []);
    llLinkParticleSystem(g_linkFlower,   []);
    llLinkParticleSystem(g_linkHarvest,  []);
    llSetLinkPrimitiveParamsFast(g_linkSeedling, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
    llSetLinkPrimitiveParamsFast(g_linkVeg,      [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
    llSetLinkPrimitiveParamsFast(g_linkFlower,   [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
    llSetLinkPrimitiveParamsFast(g_linkHarvest,  [PRIM_GLOW, ALL_SIDES, 0.0]);
    // Force-clear any stale PRIM_TEXT on indicator (survives script resets and old script versions)
    if (g_linkIndicator != -1)
        llSetLinkPrimitiveParamsFast(g_linkIndicator, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
    // Show the correct mesh for this stage
    if (g_stage == 1)
    {
        llSetLinkAlpha(g_linkSeedling, 1.0, ALL_SIDES);
    }
    else if (g_stage == 2)
    {
        llSetLinkAlpha(g_linkVeg, 1.0, ALL_SIDES);
    }
    else if (g_stage == 3)
    {
        llSetLinkAlpha(g_linkFlower, 1.0, ALL_SIDES);
    }
    else if (g_stage == 4)
    {
        llSetLinkAlpha(g_linkHarvest, 1.0, ALL_SIDES);
        llSetLinkPrimitiveParamsFast(g_linkHarvest,
            [PRIM_GLOW, ALL_SIDES, 0.05]);
        llLinkParticleSystem(g_linkHarvest, [
            PSYS_PART_FLAGS,        PSYS_PART_INTERP_COLOR_MASK |
                                    PSYS_PART_INTERP_SCALE_MASK |
                                    PSYS_PART_EMISSIVE_MASK,
            PSYS_SRC_PATTERN,       PSYS_SRC_PATTERN_ANGLE_CONE,
            PSYS_PART_START_COLOR,  <1.0, 1.0, 0.5>,
            PSYS_PART_END_COLOR,    <0.5, 1.0, 0.5>,
            PSYS_PART_START_ALPHA,  0.8,
            PSYS_PART_END_ALPHA,    0.0,
            PSYS_PART_START_SCALE,  <0.03, 0.03, 0.0>,
            PSYS_PART_END_SCALE,    <0.01, 0.01, 0.0>,
            PSYS_PART_MAX_AGE,      2.0,
            PSYS_SRC_BURST_RATE,    0.1,
            PSYS_SRC_BURST_PART_COUNT, 3,
            PSYS_SRC_BURST_SPEED_MIN,  0.02,
            PSYS_SRC_BURST_SPEED_MAX,  0.08,
            PSYS_SRC_ANGLE_BEGIN,   0.0,
            PSYS_SRC_ANGLE_END,     PI
        ]);
        llPlaySound("harvest_ready", 0.5);
    }
    // Water thirst: blue particles on the active plant mesh (no indicator prim needed)
    if (g_stage > 0 && g_stage < 4 && !g_isWatered)
    {
        integer activeMesh = g_linkSeedling;
        if (g_stage == 2) activeMesh = g_linkVeg;
        if (g_stage == 3) activeMesh = g_linkFlower;
        llLinkParticleSystem(activeMesh, [
            PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                       PSYS_PART_INTERP_SCALE_MASK |
                                       PSYS_PART_EMISSIVE_MASK,
            PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
            PSYS_PART_START_COLOR,     <0.2, 0.6, 1.0>,
            PSYS_PART_END_COLOR,       <0.0, 0.3, 0.9>,
            PSYS_PART_START_ALPHA,     0.9,
            PSYS_PART_END_ALPHA,       0.0,
            PSYS_PART_START_SCALE,     <0.05, 0.05, 0.0>,
            PSYS_PART_END_SCALE,       <0.02, 0.02, 0.0>,
            PSYS_PART_MAX_AGE,         2.0,
            PSYS_SRC_BURST_RATE,       0.5,
            PSYS_SRC_BURST_PART_COUNT, 3,
            PSYS_SRC_BURST_SPEED_MIN,  0.02,
            PSYS_SRC_BURST_SPEED_MAX,  0.1,
            PSYS_SRC_ACCEL,            <0.0, 0.0, 0.08>
        ]);
    }
    // Fertilizer reminder: text on veg mesh when watered but not yet fertilized
    // Clears automatically when fertilized (g_fertApplied=TRUE) or stage advances
    if (g_stage == 2 && g_isWatered && !g_fertApplied)
    {
        llSetLinkPrimitiveParamsFast(g_linkVeg,
            [PRIM_TEXT, "!! Fertilize !!", <1.0, 0.85, 0.0>, 1.0]);
    }
    // Status indicator icon prim  -  only for harvest-ready state
    if (g_stage == 4)
        setIndicator(STATE_READY);
    else
        setIndicator(STATE_NONE);
    // Hover text
    string hoverText = g_strainName + "\n";
    list stageNames  = ["Empty", "Seedling", "Vegetative", "Flowering", "Ready to Harvest!"];
    hoverText += llList2String(stageNames, g_stage) + "\n";
    if (g_stage > 0 && g_stage < 4)
    {
        integer elapsed  = llGetUnixTime() - g_stageStartTime;
        integer remain   = g_stageDuration - elapsed;
        if (remain < 0) remain = 0;
        integer mins     = remain / 60;
        integer hrs      = mins / 60;
        mins             = mins % 60;
        string timeStr;
        if (hrs > 0) timeStr = (string)hrs + "h " + (string)mins + "m";
        else         timeStr = (string)mins + "m";
        hoverText += "Next stage: " + timeStr + "\n";
        if (!g_isWatered)
            hoverText += "* Needs water!\n";
        else if (g_stage == 2 && !g_fertApplied)
            hoverText += "* Fertilize!\n";
        if (g_fertApplied) hoverText += "* Fertilized\n";
    }
    else if (g_stage == 4)
    {
        hoverText += "* Click to harvest!\n";
    }
    hoverText += "[" + g_potType + " pot";
    if (g_potType == "basic") hoverText += " | " + (string)g_potUsesLeft + " uses left";
    hoverText += "]";
    llSetText(hoverText, <0.6, 1.0, 0.6>, 1.0);
}
// ----------------------------------------------------------------
// Advance to the next growth stage
// ----------------------------------------------------------------
advanceStage()
{
    g_stage++;
    g_stageStartTime = llGetUnixTime();
    g_stageDuration  = calcStageDuration();
    g_isWatered = FALSE;
    g_lightBonusApplied = FALSE;
    string stageName;
    list stageNames = ["", "Seedling", "Vegetative", "Flowering", "Ready to Harvest"];
    stageName = llList2String(stageNames, g_stage);
    if (g_stage == 4)
    {
        llSetTimerEvent(HOVER_FADE_SECS);
        updateVisuals();
        llMessageLinked(LINK_SET, PCHAN_GROW, "STAGE_READY|4", NULL_KEY);
        llRegionSayTo(g_ownerKey, 0,
            "Your " + g_strainName + " is ready to harvest!");
        if (g_hudChannel != 0)
            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_NOTIFY|harvest_ready|" +
                g_strainName + " is ready to harvest!");
    }
    else
    {
        updateVisuals();
        llMessageLinked(LINK_SET, PCHAN_GROW,
            "STAGE_CHANGED|" + (string)g_stage, NULL_KEY);
        llRegionSayTo(g_ownerKey, 0,
            "Your " + g_strainName + " has entered the " + stageName + " stage.");
        // Notify owner when fertilizer window opens (veg stage, one IM per cycle)
        if (g_stage == 2)
            llInstantMessage(g_ownerKey,
                g_strainName + " is in the vegetative stage. Now's the time to fertilize!");
    }
    llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
}
// ----------------------------------------------------------------
// Calculate final yield at harvest
// ----------------------------------------------------------------
integer calculateYield()
{
    list   data    = getStrainData(g_strainName);
    if (llGetListLength(data) == 0) return 5;
    integer yieldMin = llList2Integer(data, 2);
    integer yieldMax = llList2Integer(data, 3);
    integer base     = yieldMin + (integer)(llFrand((float)(yieldMax - yieldMin)));
    float multiplier = 1.0;
    if (g_fertApplied)
    {
        if (g_fertTier == 0) multiplier += 0.10;
        if (g_fertTier == 1) multiplier += 0.25;
        if (g_fertTier == 2) multiplier += 0.50;
    }
    if (g_potType == "premium") multiplier += 0.05;
    if (g_isLegendary)      multiplier += 0.20;
    else if (g_isHybrid)    multiplier += 0.10;
    return (integer)((float)base * multiplier);
}
// ----------------------------------------------------------------
string qualityName(integer tier)
{
    list names = ["reggie", "mids", "loud", "exotic"];
    return llList2String(names, tier);
}
// ----------------------------------------------------------------
integer calculateQuality()
{
    integer finalTier = g_qualityTier;
    if (g_fertApplied && g_fertTier >= 1)
    {
        finalTier++;
        if (finalTier > 3) finalTier = 3;
    }
    return finalTier;
}
// ----------------------------------------------------------------
doHarvest()
{
    if (g_stage != 4)
    {
        llRegionSayTo(g_ownerKey, 0, "This plant isn't ready to harvest yet.");
        return;
    }
    integer finalYield   = calculateYield();
    integer finalQuality = calculateQuality();
    string  qualName     = qualityName(finalQuality);
    string harvestMsg = "TC_HARVEST_RESULT|" + g_strainName + "|" +
                        qualName + "|" + (string)finalYield;
    llRegionSayTo(g_ownerKey, g_hudChannel, harvestMsg);
    llRegionSayTo(g_ownerKey, 0,
        "Harvested " + (string)finalYield + "g of " +
        qualName + " " + g_strainName + "!");
    if (g_potType == "basic")
    {
        g_potUsesLeft--;
        if (g_potUsesLeft <= 0)
        {
            llSetLinkPrimitiveParamsFast(1,
                [PRIM_COLOR, ALL_SIDES, <0.4, 0.3, 0.2>, 1.0]);
            llPlaySound("pot_crack", 0.7);
            llRegionSayTo(g_ownerKey, 0,
                "Your basic pot has cracked from use. Time for a new one.");
            llMessageLinked(LINK_SET, PCHAN_GROW, "POT_SPENT", NULL_KEY);
        }
    }
    resetPlant();
}
// ----------------------------------------------------------------
resetPlant()
{
    g_strainName     = "";
    g_stage          = 0;
    g_stageStartTime = 0;
    g_stageDuration  = 0;
    g_isWatered      = FALSE;
    g_fertApplied    = FALSE;
    g_fertTier       = 0;
    g_isHybrid       = FALSE;
    g_isLegendary    = FALSE;
    llSetTimerEvent(HOVER_FADE_SECS);
    updateVisuals();
    llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
    llMessageLinked(LINK_SET, PCHAN_GROW, "PLANT_RESET", NULL_KEY);
}
// ================================================================
default
{
    state_entry()
    {
        resolveLinks();
        g_ownerKey  = llGetOwner();
        g_ownerName = llGetDisplayName(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);
        g_potType    = derivePotType();
        llListen(GROW_LIGHT_CHAN, "", NULL_KEY, "");
        llMessageLinked(LINK_SET, PCHAN_PERSIST, "LOAD_STATE", NULL_KEY);
        llSetTimerEvent(HOVER_FADE_SECS);
    }
    on_rez(integer start_param)
    {
        resolveLinks();
        g_ownerKey   = llGetOwner();
        g_ownerName  = llGetDisplayName(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);
        g_potType    = derivePotType();
        llMessageLinked(LINK_SET, PCHAN_PERSIST, "LOAD_STATE", NULL_KEY);
    }
    timer()
    {
        // Idle fade for empty pot (stage 0) or harvest-ready (stage 4)
        if (g_stage == 0)
        {
            llSetText(g_strainName + "\nEmpty", <0.6, 1.0, 0.6>, 0.0);
            llSetTimerEvent(0.0);
            return;
        }
        if (g_stage == 4)
        {
            string hoverText = g_strainName + "\nReady to Harvest!\n* Click to harvest!\n[" +
                g_potType + " pot";
            if (g_potType == "basic") hoverText += " | " + (string)g_potUsesLeft + " uses left";
            hoverText += "]";
            llSetText(hoverText, <0.6, 1.0, 0.6>, 0.0);
            llSetTimerEvent(0.0);
            return;
        }
        integer now     = llGetUnixTime();
        integer elapsed = now - g_stageStartTime;
        if (elapsed >= g_stageDuration)
        {
            if (g_isWatered || g_stage == 1)
            {
                advanceStage();
            }
            else
            {
                integer overdueBy = elapsed - g_stageDuration;
                // Fire once when the plant first goes overdue (within one extra tick)
                if (overdueBy < (integer)(TIMER_INTERVAL * 1.5))
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "Your " + g_strainName +
                        " needs water before it can progress!");
                    llInstantMessage(g_ownerKey,
                        g_strainName + " needs water again!");
                }
            }
        }
        updateVisuals();
        if (g_stage > 0 && g_stage < 4)
            updateIndicatorFacing();
    }
    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != PCHAN_GROW) return;
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);
        if (cmd == "PLANT_SEED")
        {
            g_strainName  = llList2String(parts, 1);
            // g_potType and g_potUsesLeft stay as set by STATE_LOADED  -  authoritative
            g_isHybrid    = (llSubStringIndex(g_strainName, " x ") != -1);
            g_isLegendary = g_isHybrid &&
                            (llSubStringIndex(g_strainName, "[LEGENDARY]") != -1);
            if (g_isLegendary)
                g_qualityTier = 3;
            else if (g_isHybrid)
                g_qualityTier = 2;
            else
            {
                list data = getStrainData(g_strainName);
                if (llGetListLength(data) == 0)
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "Unknown strain: " + g_strainName + ". Check seed name.");
                    return;
                }
                g_qualityTier = llList2Integer(data, 1);
            }
            g_stage          = 1;
            g_stageStartTime = llGetUnixTime();
            g_stageDuration  = calcStageDuration();
            g_isWatered      = FALSE;
            g_fertApplied    = FALSE;
            g_fertTier       = 0;
            llSetTimerEvent(TIMER_INTERVAL);
            updateVisuals();
            llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
            string flavorMsg;
            if (g_isLegendary)
                flavorMsg = "A legendary cross. This one's special.";
            else if (g_isHybrid)
                flavorMsg = "A bred hybrid. Grows faster, yields bigger.";
            else
            {
                list flavorData = getStrainData(g_strainName);
                flavorMsg = llList2String(flavorData, 4);
            }
            llRegionSayTo(g_ownerKey, 0,
                "Planted " + g_strainName + ". \"" + flavorMsg + "\"");
        }
        else if (cmd == "WATER_APPLIED")
        {
            if (g_stage == 0 || g_stage == 4)
            {
                llRegionSayTo(g_ownerKey, 0, "Nothing to water right now.");
                return;
            }
            g_isWatered = TRUE;
            updateVisuals();
            llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
            llRegionSayTo(g_ownerKey, 0,
                "Watered your " + g_strainName + ".");
            if (g_stage == 2 && !g_fertApplied)
                llRegionSayTo(g_ownerKey, 0,
                    g_strainName + " is in the vegetative stage  -  fertilize now for a bigger yield!");
        }
        else if (cmd == "FERT_APPLIED")
        {
            if (g_stage != 2)
            {
                llRegionSayTo(g_ownerKey, 0,
                    "Fertilizer can only be applied during the vegetative stage.");
                return;
            }
            if (g_fertApplied)
            {
                llRegionSayTo(g_ownerKey, 0,
                    "Already fertilized this grow. One application per cycle.");
                return;
            }
            g_fertApplied = TRUE;
            g_fertTier    = (integer)llList2String(parts, 1);
            if (g_fertTier >= 1)
            {
                integer elapsed  = llGetUnixTime() - g_stageStartTime;
                integer remain   = g_stageDuration - elapsed;
                integer reduction = (integer)((float)remain * 0.15);
                g_stageDuration -= reduction;
            }
            updateVisuals();
            llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
            list fertNames = ["Basic", "Premium", "Exotic"];
            llRegionSayTo(g_ownerKey, 0,
                llList2String(fertNames, g_fertTier) +
                " fertilizer applied to " + g_strainName + ".");
        }
        else if (cmd == "DO_HARVEST")
        {
            doHarvest();
        }
        else if (cmd == "STATE_LOADED")
        {
            g_strainName     = llList2String(parts, 1);
            g_qualityTier    = (integer)llList2String(parts, 2);
            g_stage          = (integer)llList2String(parts, 3);
            g_stageStartTime = (integer)llList2String(parts, 4);
            g_stageDuration  = (integer)llList2String(parts, 5);
            g_isWatered      = (integer)llList2String(parts, 6);
            g_fertApplied    = (integer)llList2String(parts, 7);
            g_fertTier       = (integer)llList2String(parts, 8);
            // g_potType is set from object name (derivePotType) — do not load from save
            g_potUsesLeft = (integer)llList2String(parts, 10);
            // parts[11] = potSpent flag (absent in old saves, defaults to 0/FALSE)
            integer savedPotSpent = (integer)llList2String(parts, 11);
            // Migrate from old buggy saves: potUsesLeft=0 but never explicitly spent
            // (old code had no potSpent flag  -  treat missing flag as "not spent")
            if (g_potType == "basic" && g_potUsesLeft <= 0 && !savedPotSpent)
                g_potUsesLeft = 5;
            if (g_potType == "basic" && g_potUsesLeft > 5) g_potUsesLeft = 5;
            if (g_stage > 0 && g_stage < 4)
                llSetTimerEvent(TIMER_INTERVAL);
            updateVisuals();
        }
        else if (cmd == "SET_POT")
        {
            g_potType     = llList2String(parts, 1);
            g_potUsesLeft = (integer)llList2String(parts, 2);
            updateVisuals();
            llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
        }
        else if (cmd == "REQUEST_STATUS")
        {
            integer potSpent = (g_potType == "basic" && g_potUsesLeft <= 0);
            string status =
                "STATUS|"         + g_strainName           + "|" +
                (string)g_qualityTier                       + "|" +
                (string)g_stage                             + "|" +
                (string)g_stageStartTime                    + "|" +
                (string)g_stageDuration                     + "|" +
                (string)g_isWatered                         + "|" +
                (string)g_fertApplied                       + "|" +
                (string)g_fertTier                          + "|" +
                g_potType                                   + "|" +
                (string)g_potUsesLeft                       + "|" +
                (string)potSpent;
            llMessageLinked(LINK_SET, PCHAN_GROW, status, NULL_KEY);
        }
    }
    listen(integer channel, string name, key id, string msg)
    {
        if (channel != GROW_LIGHT_CHAN) return;
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);
        if (cmd == "TC_LIGHT_BONUS")
        {
            if (g_stage == 0 || g_stage == 4) return;
            if (g_lightBonusApplied) return;
            key lightOwner = (key)llList2String(parts, 3);
            if (lightOwner != g_ownerKey) return;
            integer bonusPct = (integer)llList2String(parts, 1);
            if (bonusPct <= 0 || bonusPct > 50) return;
            integer elapsed   = llGetUnixTime() - g_stageStartTime;
            integer remaining = g_stageDuration - elapsed;
            if (remaining <= 0) return;
            integer reduction =
                (integer)((float)remaining * ((float)bonusPct / 100.0));
            g_stageDuration  -= reduction;
            g_lightBonusApplied = TRUE;
            llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
            updateVisuals();
            // Brief glow (on flowering mesh as a hint)
            llSetLinkPrimitiveParamsFast(g_linkFlower,
                [PRIM_GLOW, ALL_SIDES, 0.12]);
        }
    }
}
