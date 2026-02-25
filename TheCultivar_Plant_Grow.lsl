// ================================================================
// THE CULTIVAR — Plant Grow Script
// Version: 1.0
// Handles: Growth timer, stage progression, strain data,
//          yield and quality calculation, visual stage updates
//
// GROWTH STAGES:
//   0 = Empty pot (no seed planted)
//   1 = Seedling
//   2 = Vegetative
//   3 = Flowering
//   4 = Harvest Ready
//
// PRIM LINK STRUCTURE (adjust link numbers to match your mesh):
//   Link 1 (root)    : Pot body
//   Link 2           : Plant stage mesh (swapped at each stage)
//   Link 3           : Harvest glow / sparkle emitter
//   Link 4           : Water indicator light (green = watered, red = needs water)
//   Link 5           : Fertilizer indicator light (yellow = applied)
//
// GROW TIMES BY QUALITY TIER (in seconds):
//   Reggie  :  2,700  (45 minutes)
//   Mids    :  7,200  (2 hours)
//   Loud    : 14,400  (4 hours)
//   Exotic  : 28,800  (8 hours)
//
// Each stage is 1/4 of total grow time.
// Fertilizer applied during veg stage reduces remaining time by 15%
// and bumps quality one tier.
// Premium pot gives 5% speed bonus passively.
// ================================================================

// Internal channels (match across all plant scripts)
integer PCHAN_GROW    = 1000; // Grow <-> Interaction
integer PCHAN_PERSIST = 1100; // Grow <-> Persistence

// --- Strain Data Table ---
// Format per entry: strainName|qualityTier|baseYieldMin|baseYieldMax|flavorText
// qualityTier: 0=reggie 1=mids 2=loud 3=exotic
list STRAIN_DATA = [
    // REGGIE TIER
    "Schwag",          0, 4,  8,  "Barely worth the effort.",
    "Ditch Weed",      0, 3,  7,  "Old reliable. Sort of.",
    "Brown Frown",     0, 3,  6,  "It'll do.",
    // MIDS TIER
    "Blue Dream",      1, 8,  14, "Smooth and easy.",
    "Green Crack",     1, 9,  15, "Gets things moving.",
    "Gorilla Glue",    1, 8,  14, "Heavy and sticky.",
    "Sour Diesel",     1, 9,  16, "Fuel for the soul.",
    // LOUD TIER
    "OG Kush",         2, 14, 20, "The classic. No notes.",
    "Wedding Cake",    2, 15, 22, "Sweet and earthy.",
    "Zkittlez",        2, 14, 21, "Fruit forward and smooth.",
    "Gelato",          2, 15, 22, "Dessert in a blunt.",
    // EXOTIC TIER
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

// Timer tick rate — check every 30 seconds to balance responsiveness vs lag
float TIMER_INTERVAL = 30.0;

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
    return stageDur;
}

// ----------------------------------------------------------------
// Update plant visuals for current stage
// Called whenever stage changes
// ----------------------------------------------------------------
updateVisuals()
{
    // Swap plant mesh texture/visibility per stage
    // Stage 0: pot only, no plant visible
    // Stage 1: tiny sprout
    // Stage 2: medium veg plant
    // Stage 3: full flowering plant
    // Stage 4: harvest ready — add sparkle glow

    // Hide/show plant link based on stage
    if (g_stage == 0)
    {
        llSetLinkPrimitiveParamsFast(2, [PRIM_SIZE, <0.001, 0.001, 0.001>]);
        llSetLinkPrimitiveParamsFast(3, [PRIM_PARTICLE_SYSTEM, []]);
    }
    else if (g_stage == 1)
    {
        // Seedling — small
        llSetLinkPrimitiveParamsFast(2, [PRIM_SIZE, <0.1, 0.1, 0.15>]);
        llSetLinkAlpha(2, 1.0, ALL_SIDES);
    }
    else if (g_stage == 2)
    {
        // Veg — medium
        llSetLinkPrimitiveParamsFast(2, [PRIM_SIZE, <0.2, 0.2, 0.3>]);
    }
    else if (g_stage == 3)
    {
        // Flowering — full size
        llSetLinkPrimitiveParamsFast(2, [PRIM_SIZE, <0.3, 0.3, 0.45>]);
    }
    else if (g_stage == 4)
    {
        // Harvest ready — full size + sparkle particles + glow
        llSetLinkPrimitiveParamsFast(2, [PRIM_SIZE, <0.3, 0.3, 0.5>,
                                         PRIM_GLOW, ALL_SIDES, 0.05]);
        // Sparkle particle system on link 3
        llLinkParticleSystem(3, [
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
        llPlaySound("harvest_ready", 0.5); // sound asset name
    }

    // Water indicator — link 4
    vector waterColor = <0.2, 0.8, 0.2>; // green = watered
    if (!g_isWatered && g_stage > 0 && g_stage < 4)
        waterColor = <0.8, 0.2, 0.2>; // red = needs water
    llSetLinkPrimitiveParamsFast(4, [PRIM_COLOR, ALL_SIDES, waterColor, 1.0,
                                     PRIM_GLOW,  ALL_SIDES, 0.1]);

    // Fertilizer indicator — link 5
    float fertGlow = 0.0;
    if (g_fertApplied) fertGlow = 0.15;
    llSetLinkPrimitiveParamsFast(5, [PRIM_COLOR, ALL_SIDES, <1.0, 0.9, 0.1>, 1.0,
                                     PRIM_GLOW,  ALL_SIDES, fertGlow]);

    // Update hover text
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
        if (!g_isWatered) hoverText += "⚠ Needs water!\n";
        if (g_fertApplied) hoverText += "✓ Fertilized\n";
    }
    else if (g_stage == 4)
    {
        hoverText += "✨ Click to harvest! ✨\n";
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

    // Water resets each stage — must water again for the next one
    g_isWatered = FALSE;

    string stageName;
    list stageNames = ["", "Seedling", "Vegetative", "Flowering", "Ready to Harvest"];
    stageName = llList2String(stageNames, g_stage);

    if (g_stage == 4)
    {
        // Done — stop timer, update visuals, notify
        llSetTimerEvent(0.0);
        updateVisuals();
        // Notify interaction script to show harvest option
        llMessageLinked(LINK_SET, PCHAN_GROW, "STAGE_READY|4", NULL_KEY);
        llRegionSayTo(g_ownerKey, 0,
            "🌿 Your " + g_strainName + " is ready to harvest!");
    }
    else
    {
        updateVisuals();
        llMessageLinked(LINK_SET, PCHAN_GROW, "STAGE_CHANGED|" + (string)g_stage, NULL_KEY);
        llRegionSayTo(g_ownerKey, 0,
            "Your " + g_strainName + " has entered the " + stageName + " stage.");
    }

    // Save new state
    llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
}

// ----------------------------------------------------------------
// Calculate final yield at harvest
// Base yield from strain data, modified by:
//   - Water compliance (each stage watered = +10% to base)
//   - Fertilizer tier (basic=+10%, premium=+25%, exotic=+50%)
//   - Pot type (premium = +5%)
// ----------------------------------------------------------------
integer calculateYield()
{
    list   data    = getStrainData(g_strainName);
    if (llGetListLength(data) == 0) return 5; // safe fallback

    integer yieldMin = llList2Integer(data, 2);
    integer yieldMax = llList2Integer(data, 3);
    integer base     = yieldMin + (integer)(llFrand((float)(yieldMax - yieldMin)));

    float multiplier = 1.0;

    // Fertilizer bonus
    if (g_fertApplied)
    {
        if (g_fertTier == 0) multiplier += 0.10; // basic
        if (g_fertTier == 1) multiplier += 0.25; // premium
        if (g_fertTier == 2) multiplier += 0.50; // exotic
    }

    // Pot bonus
    if (g_potType == "premium") multiplier += 0.05;

    return (integer)((float)base * multiplier);
}

// ----------------------------------------------------------------
// Calculate final quality tier at harvest
// Fertilizer can push quality up one tier
// ----------------------------------------------------------------
integer calculateQuality()
{
    integer finalTier = g_qualityTier;
    if (g_fertApplied && g_fertTier >= 1)
    {
        finalTier++;
        if (finalTier > 3) finalTier = 3; // cap at exotic
    }
    return finalTier;
}

// ----------------------------------------------------------------
// Return quality tier name as string
// ----------------------------------------------------------------
string qualityName(integer tier)
{
    list names = ["reggie", "mids", "loud", "exotic"];
    return llList2String(names, tier);
}

// ----------------------------------------------------------------
// Perform harvest — calculate results, send to HUD, reset plant
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

    // Send harvest result to owner's HUD on their private channel
    string harvestMsg = "TC_HARVEST_RESULT|" + g_strainName + "|" +
                        qualName + "|" + (string)finalYield;
    llRegionSayTo(g_ownerKey, g_hudChannel, harvestMsg);

    llRegionSayTo(g_ownerKey, 0,
        "🌿 Harvested " + (string)finalYield + "g of " +
        qualName + " " + g_strainName + "!");

    // Decrement pot uses if basic
    if (g_potType == "basic")
    {
        g_potUsesLeft--;
        if (g_potUsesLeft <= 0)
        {
            // Pot is spent — visual break effect, notify
            llSetLinkPrimitiveParamsFast(1, [PRIM_COLOR, ALL_SIDES, <0.4, 0.3, 0.2>, 1.0]);
            llPlaySound("pot_crack", 0.7);
            llRegionSayTo(g_ownerKey, 0,
                "Your basic pot has cracked from use. Time for a new one.");
            // Tell interaction script pot is spent
            llMessageLinked(LINK_SET, PCHAN_GROW, "POT_SPENT", NULL_KEY);
        }
    }

    // Reset plant state to empty
    resetPlant();
}

// ----------------------------------------------------------------
// Reset after harvest (or if pot is replaced)
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
    llSetTimerEvent(0.0);
    updateVisuals();
    llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
    llMessageLinked(LINK_SET, PCHAN_GROW, "PLANT_RESET", NULL_KEY);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);

        // Request saved state from persistence script on startup
        llMessageLinked(LINK_SET, PCHAN_PERSIST, "LOAD_STATE", NULL_KEY);
    }

    on_rez(integer start_param)
    {
        g_ownerKey   = llGetOwner();
        g_ownerName  = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);
        llMessageLinked(LINK_SET, PCHAN_PERSIST, "LOAD_STATE", NULL_KEY);
    }

    timer()
    {
        if (g_stage == 0 || g_stage == 4) return;

        integer now     = llGetUnixTime();
        integer elapsed = now - g_stageStartTime;

        // Check if current stage is complete
        if (elapsed >= g_stageDuration)
        {
            // Stage is done — but only advance if watered
            if (g_isWatered || g_stage == 1) // seedling doesn't need water to sprout
            {
                advanceStage();
            }
            else
            {
                // Overdue and not watered — yield penalty accrues silently
                // Plant just waits. No death, just diminishing returns if ignored too long.
                // Notify once when first overdue
                integer overdueBy = elapsed - g_stageDuration;
                if (overdueBy < (integer)(TIMER_INTERVAL * 1.5))
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "⚠ Your " + g_strainName +
                        " needs water before it can progress!");
                }
            }
        }

        // Refresh hover text with updated time remaining
        updateVisuals();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != PCHAN_GROW) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Interaction script tells grow to plant a seed
        if (cmd == "PLANT_SEED")
        {
            // PLANT_SEED|strainName|potType|potUsesLeft
            g_strainName  = llList2String(parts, 1);
            g_potType     = llList2String(parts, 2);
            g_potUsesLeft = (integer)llList2String(parts, 3);

            // Look up quality tier from strain data
            list data = getStrainData(g_strainName);
            if (llGetListLength(data) == 0)
            {
                llRegionSayTo(g_ownerKey, 0,
                    "Unknown strain: " + g_strainName + ". Check seed name.");
                return;
            }
            g_qualityTier    = llList2Integer(data, 1);
            g_stage          = 1; // seedling
            g_stageStartTime = llGetUnixTime();
            g_stageDuration  = calcStageDuration();
            g_isWatered      = FALSE;
            g_fertApplied    = FALSE;
            g_fertTier       = 0;

            llSetTimerEvent(TIMER_INTERVAL);
            updateVisuals();
            llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);

            list flavorData = getStrainData(g_strainName);
            string flavor   = llList2String(flavorData, 4);
            llRegionSayTo(g_ownerKey, 0,
                "🌱 Planted " + g_strainName + ". \"" + flavor + "\"");
        }

        // Player watered the plant
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
            llRegionSayTo(g_ownerKey, 0, "✓ Watered your " + g_strainName + ".");
        }

        // Player applied fertilizer
        else if (cmd == "FERT_APPLIED")
        {
            // FERT_APPLIED|fertTier (0=basic 1=premium 2=exotic)
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

            // Premium and exotic fert also reduce remaining time by 15%
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
                "✓ " + llList2String(fertNames, g_fertTier) +
                " fertilizer applied to " + g_strainName + ".");
        }

        // Interaction script requests harvest
        else if (cmd == "DO_HARVEST")
        {
            doHarvest();
        }

        // Persistence script loaded saved state back into us after sim restart
        else if (cmd == "STATE_LOADED")
        {
            // STATE_LOADED|strainName|qualityTier|stage|stageStartTime|stageDuration
            //             |isWatered|fertApplied|fertTier|potType|potUsesLeft
            g_strainName     = llList2String(parts, 1);
            g_qualityTier    = (integer)llList2String(parts, 2);
            g_stage          = (integer)llList2String(parts, 3);
            g_stageStartTime = (integer)llList2String(parts, 4);
            g_stageDuration  = (integer)llList2String(parts, 5);
            g_isWatered      = (integer)llList2String(parts, 6);
            g_fertApplied    = (integer)llList2String(parts, 7);
            g_fertTier       = (integer)llList2String(parts, 8);
            g_potType        = llList2String(parts, 9);
            g_potUsesLeft    = (integer)llList2String(parts, 10);

            if (g_stage > 0 && g_stage < 4)
                llSetTimerEvent(TIMER_INTERVAL);

            updateVisuals();
        }

        // Interaction script tells grow which pot is in use (on first rez or pot swap)
        else if (cmd == "SET_POT")
        {
            // SET_POT|potType|potUsesLeft
            g_potType     = llList2String(parts, 1);
            g_potUsesLeft = (integer)llList2String(parts, 2);
            updateVisuals();
            llMessageLinked(LINK_SET, PCHAN_PERSIST, "SAVE_STATE", NULL_KEY);
        }

        // Broadcast current state to interaction script (for menu display)
        else if (cmd == "REQUEST_STATUS")
        {
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
                (string)g_potUsesLeft;
            llMessageLinked(LINK_SET, PCHAN_GROW, status, NULL_KEY);
        }
    }
}
