// ================================================================
// THE CULTIVAR — Weed Jar Main Script
// Version: 1.0
// Handles: Strain data storage, fill level tracking and visuals,
//          HUD registration, smoke events, loading from bags/flower,
//          session integration, access control
//
// PRIM LINK STRUCTURE:
//   Link 1 (root)  : Jar body mesh
//   Link 2         : Fill level mesh (scaled by fill %)
//   Link 3         : Lid mesh
//   Link 4         : Particle emitter (idle wisp + smoke on use)
//   Link 5         : Quality glow ring (color changes by tier)
//
// FILL LEVEL STAGES (visual thresholds):
//   100–75% : Full    — packed, visible buds at top
//   74–50%  : Half    — mid level
//   49–25%  : Low     — getting thin
//   24–10%  : Almost  — nearly empty, color shift
//   9–1%    : Last    — just a little left
//   0%      : Empty   — no fill mesh, idle particle gone
//
// CAPACITY: 28g default (one oz). Premium jar = 56g.
//
// ACCESS MODES:
//   0 = Owner only
//   1 = Group (same group as object)
//   2 = Open (anyone can take from it)
//
// STRAIN DATA stored in llLinksetData for persistence:
//   jar_strain, jar_quality, jar_packager, jar_grams, jar_capacity,
//   jar_access, jar_type (standard/premium)
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

// Internal channels between jar scripts
integer JCHAN_MAIN    = 2000;
integer JCHAN_ATTACH  = 2100;

// Dialog channels
integer DCHAN_OWNER   = -88001;
integer DCHAN_LOAD    = -88002;
integer DCHAN_ACCESS  = -88003;
integer DCHAN_VISITOR = -88004;

integer g_listenRegister;
integer g_listenHUD;
integer g_listenOwner;
integer g_listenLoad;
integer g_listenAccess;
integer g_listenVisitor;

// Jar identity
string  g_strain     = "";
string  g_quality    = "";
string  g_packager   = "";
integer g_grams      = 0;
integer g_capacity   = 28;   // standard jar = 28g, premium = 56g
integer g_accessMode = 0;    // 0=owner 1=group 2=open
string  g_jarType    = "standard";

// HUD connection
key     g_ownerKey   = NULL_KEY;
string  g_ownerName  = "";
integer g_hudChannel = 0;
integer g_registered = FALSE;

// Session state
integer g_inSession  = FALSE;
key     g_sessionKey = NULL_KEY;

// Cooldown to prevent spam-clicking
integer g_lastSmoke  = 0;
integer SMOKE_COOLDOWN = 8; // seconds between takes

// ----------------------------------------------------------------
// Persist jar state to linkset data
// ----------------------------------------------------------------
saveState()
{
    llLinksetDataWrite("jar_strain",   g_strain);
    llLinksetDataWrite("jar_quality",  g_quality);
    llLinksetDataWrite("jar_packager", g_packager);
    llLinksetDataWrite("jar_grams",    (string)g_grams);
    llLinksetDataWrite("jar_capacity", (string)g_capacity);
    llLinksetDataWrite("jar_access",   (string)g_accessMode);
    llLinksetDataWrite("jar_type",     g_jarType);
}

// ----------------------------------------------------------------
// Load jar state from linkset data
// ----------------------------------------------------------------
loadState()
{
    string test = llLinksetDataRead("jar_strain");
    if (test != "")
    {
        g_strain     = llLinksetDataRead("jar_strain");
        g_quality    = llLinksetDataRead("jar_quality");
        g_packager   = llLinksetDataRead("jar_packager");
        g_grams      = (integer)llLinksetDataRead("jar_grams");
        g_capacity   = (integer)llLinksetDataRead("jar_capacity");
        g_accessMode = (integer)llLinksetDataRead("jar_access");
        g_jarType    = llLinksetDataRead("jar_type");
    }
    else
    {
        // Fresh jar defaults
        g_capacity = (g_jarType == "premium") ? 56 : 28;
    }
}

// ----------------------------------------------------------------
// Derive HUD channel from owner UUID
// ----------------------------------------------------------------
integer deriveHUDChannel(key ownerID)
{
    string hexSub = llGetSubString((string)ownerID, 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}

// ----------------------------------------------------------------
// Ping HUD for registration
// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|weed_jar");
    llSetTimerEvent(8.0);
}

// ----------------------------------------------------------------
// Fill percentage as float 0.0–1.0
// ----------------------------------------------------------------
float fillPct()
{
    if (g_capacity <= 0) return 0.0;
    return (float)g_grams / (float)g_capacity;
}

// ----------------------------------------------------------------
// Update all visual elements based on current state
// ----------------------------------------------------------------
updateVisuals()
{
    float pct = fillPct();

    // --- Fill level mesh (link 2) ---
    // Scale the Z axis of the fill mesh proportionally
    // Base full height ~0.08 (adjust to match your mesh)
    float fillHeight = 0.08 * pct;
    if (fillHeight < 0.001) fillHeight = 0.001; // never fully invisible
    llSetLinkPrimitiveParamsFast(2, [
        PRIM_SIZE, <0.065, 0.065, fillHeight>,
        PRIM_COLOR, ALL_SIDES, qualityColor(), 1.0
    ]);

    // --- Quality glow ring (link 5) ---
    float glowVal = 0.0;
    if (g_grams > 0) glowVal = 0.06 + (pct * 0.04); // subtle, brighter when full
    llSetLinkPrimitiveParamsFast(5, [
        PRIM_COLOR, ALL_SIDES, qualityColor(), 1.0,
        PRIM_GLOW,  ALL_SIDES, glowVal
    ]);

    // --- Idle particle wisp (link 4) ---
    if (g_grams > 0)
        startIdleParticles();
    else
        llLinkParticleSystem(4, []); // clear particles when empty

    // --- Hover text ---
    updateHoverText();
}

// ----------------------------------------------------------------
// Quality tier color vector
// ----------------------------------------------------------------
vector qualityColor()
{
    if (g_quality == "mids")   return <1.0, 0.85, 0.2>;  // amber
    if (g_quality == "loud")   return <0.2, 0.85, 0.3>;  // green
    if (g_quality == "exotic") return <0.7, 0.3,  1.0>;  // purple
    return <0.55, 0.45, 0.3>; // reggie — earthy brown
}

// ----------------------------------------------------------------
// Idle ambient wisp particles — subtle, quality-tinted
// ----------------------------------------------------------------
startIdleParticles()
{
    vector col = qualityColor();
    llLinkParticleSystem(4, [
        PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                   PSYS_PART_INTERP_SCALE_MASK |
                                   PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     col,
        PSYS_PART_END_COLOR,       <1.0, 1.0, 1.0>,
        PSYS_PART_START_ALPHA,     0.25,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.015, 0.015, 0.0>,
        PSYS_PART_END_SCALE,       <0.005, 0.005, 0.0>,
        PSYS_PART_MAX_AGE,         3.0,
        PSYS_SRC_BURST_RATE,       1.2,
        PSYS_SRC_BURST_PART_COUNT, 1,
        PSYS_SRC_BURST_SPEED_MIN,  0.01,
        PSYS_SRC_BURST_SPEED_MAX,  0.03,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        0.3
    ]);
}

// ----------------------------------------------------------------
// Burst smoke particles when someone takes a hit
// ----------------------------------------------------------------
burstSmokeParticles()
{
    vector col = qualityColor();
    llLinkParticleSystem(4, [
        PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                   PSYS_PART_INTERP_SCALE_MASK |
                                   PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     col,
        PSYS_PART_END_COLOR,       <0.9, 0.9, 0.9>,
        PSYS_PART_START_ALPHA,     0.7,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.06, 0.06, 0.0>,
        PSYS_PART_END_SCALE,       <0.12, 0.12, 0.0>,
        PSYS_PART_MAX_AGE,         4.0,
        PSYS_SRC_BURST_RATE,       0.05,
        PSYS_SRC_BURST_PART_COUNT, 6,
        PSYS_SRC_BURST_SPEED_MIN,  0.03,
        PSYS_SRC_BURST_SPEED_MAX,  0.08,
        PSYS_SRC_MAX_AGE,          1.5,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        0.4
    ]);
    // Return to idle after burst
    llSleep(2.0);
    if (g_grams > 0) startIdleParticles();
    else llLinkParticleSystem(4, []);
}

// ----------------------------------------------------------------
// Update hover text
// ----------------------------------------------------------------
updateHoverText()
{
    if (g_grams == 0)
    {
        llSetText("THE CULTIVAR\nWeed Jar [Empty]\nTouch to load",
                  <0.5, 0.5, 0.5>, 0.8);
        return;
    }

    float  pct      = fillPct();
    string fillStr;
    if      (pct >= 0.75) fillStr = "████████ Full";
    else if (pct >= 0.50) fillStr = "██████░░ Half";
    else if (pct >= 0.25) fillStr = "████░░░░ Low";
    else if (pct >= 0.10) fillStr = "██░░░░░░ Almost Gone";
    else                  fillStr = "░░░░░░░░ Last Bit";

    list   accessLabels = ["Owner Only", "Group", "Open"];
    string accessStr    = llList2String(accessLabels, g_accessMode);

    string qualLabel;
    if      (g_quality == "reggie") qualLabel = "Reggie";
    else if (g_quality == "mids")   qualLabel = "Mids ★";
    else if (g_quality == "loud")   qualLabel = "Loud ★★";
    else if (g_quality == "exotic") qualLabel = "Exotic ✨";
    else qualLabel = g_quality;

    llSetText(
        "THE CULTIVAR\n" +
        g_strain + "  [" + qualLabel + "]\n" +
        fillStr + "  " + (string)g_grams + "g\n" +
        "Packed by " + g_packager + "  •  " + accessStr,
        qualityColor(), 1.0);
}

// ----------------------------------------------------------------
// Check if a visitor has access to take from the jar
// ----------------------------------------------------------------
integer hasAccess(key who)
{
    if (who == g_ownerKey)  return TRUE;  // owner always has access
    if (g_accessMode == 2)  return TRUE;  // open
    if (g_accessMode == 1)
        return llSameGroup(who);          // group check
    return FALSE;
}

// ----------------------------------------------------------------
// Consume 1g from the jar and trigger smoke event
// ----------------------------------------------------------------
doSmoke(key smoker)
{
    integer now = llGetUnixTime();
    if (now - g_lastSmoke < SMOKE_COOLDOWN)
    {
        integer wait = SMOKE_COOLDOWN - (now - g_lastSmoke);
        llRegionSayTo(smoker, 0,
            "Easy there — wait " + (string)wait + " more seconds.");
        return;
    }

    if (g_grams <= 0)
    {
        llRegionSayTo(smoker, 0, "The jar is empty.");
        return;
    }

    g_grams--;
    g_lastSmoke = now;
    saveState();

    // Tell smoker's HUD about the smoke event
    integer smokerHUDChan = deriveHUDChannel(smoker);
    llRegionSayTo(smoker, smokerHUDChan,
        "TC_SMOKED|" + g_strain + "|" + g_quality);

    // Tell attach script to auto-attach a smokeable to their hand
    llMessageLinked(LINK_SET, JCHAN_ATTACH,
        "ATTACH|" + (string)smoker + "|" + g_strain + "|" + g_quality, NULL_KEY);

    // Burst particles and play sound
    burstSmokeParticles();
    llPlaySound("jar_open", 0.5);

    // Feedback
    if (smoker == g_ownerKey)
        llOwnerSay("You reached in for some " + g_quality + " " + g_strain +
                   ". " + (string)g_grams + "g left.");
    else
        llRegionSayTo(smoker, 0,
            "You grabbed some " + g_quality + " " + g_strain + " from the jar.");

    // Low jar warning to owner
    if (g_grams == 5)
        llRegionSayTo(g_ownerKey, 0,
            "⚠ Your " + g_strain + " jar is getting low — only 5g left.");
    else if (g_grams == 0)
        llRegionSayTo(g_ownerKey, 0,
            "Your " + g_strain + " jar is empty.");

    updateVisuals();
}

// ----------------------------------------------------------------
// Load flower into the jar from a bag or raw flower
// strain/quality/grams/packager come from the HUD inventory
// ----------------------------------------------------------------
loadJar(string strain, string quality, integer grams, string packager)
{
    integer space = g_capacity - g_grams;
    if (space <= 0)
    {
        llRegionSayTo(g_ownerKey, 0, "The jar is full (" +
                      (string)g_capacity + "g capacity).");
        return;
    }

    // Can only hold one strain at a time — mixing not allowed
    if (g_grams > 0 && g_strain != strain)
    {
        llRegionSayTo(g_ownerKey, 0,
            "The jar already has " + g_strain + " in it. Empty it first.");
        return;
    }

    integer toLoad = grams;
    if (toLoad > space) toLoad = space;

    g_strain   = strain;
    g_quality  = quality;
    g_packager = packager;
    g_grams   += toLoad;
    saveState();
    updateVisuals();

    llOwnerSay("✓ Loaded " + (string)toLoad + "g of " +
               quality + " " + strain + " into the jar.");

    if (toLoad < grams)
        llOwnerSay("Jar is now full. " + (string)(grams - toLoad) +
                   "g of flower was left over.");
}

// ----------------------------------------------------------------
// Empty the jar back to owner's HUD inventory
// ----------------------------------------------------------------
emptyJar()
{
    if (g_grams == 0)
    {
        llOwnerSay("The jar is already empty.");
        return;
    }

    // Return remaining flower to HUD inventory
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|flower_raw|" + g_strain + "|" +
        g_quality + "|" + (string)g_grams + "|" + g_packager);

    llOwnerSay("Emptied " + (string)g_grams + "g of " +
               g_strain + " back to your inventory.");

    g_grams    = 0;
    g_strain   = "";
    g_quality  = "";
    g_packager = "";
    saveState();
    updateVisuals();
}

// ----------------------------------------------------------------
// OWNER MENU
// ----------------------------------------------------------------
showOwnerMenu()
{
    if (g_listenOwner) llListenRemove(g_listenOwner);
    g_listenOwner = llListen(DCHAN_OWNER, "", g_ownerKey, "");

    string statusLine;
    if (g_grams > 0)
        statusLine = g_strain + " [" + g_quality + "]  " +
                     (string)g_grams + "g / " + (string)g_capacity + "g";
    else
        statusLine = "Empty";

    list accessLabels = ["Owner Only", "Group Access", "Open Access"];

    list buttons;
    if (g_grams > 0)
        buttons = ["Take A Hit", "Load More", "Empty Jar",
                   "Access Mode", "Jar Info", "Close"];
    else
        buttons = ["Load Flower", "Access Mode", "Jar Info", "Close"];

    llDialog(g_ownerKey,
        "=== YOUR JAR ===\n" + statusLine,
        buttons, DCHAN_OWNER);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// VISITOR MENU — for non-owners with access
// ----------------------------------------------------------------
showVisitorMenu(key visitor)
{
    if (g_listenVisitor) llListenRemove(g_listenVisitor);
    g_listenVisitor = llListen(DCHAN_VISITOR, "", visitor, "");

    llDialog(visitor,
        "=== JAR (" + g_ownerName + "'s) ===\n" +
        g_strain + " [" + g_quality + "]\n" +
        (string)g_grams + "g remaining",
        ["Take A Hit", "No Thanks"], DCHAN_VISITOR);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// LOAD FLOWER MENU — choose from available flower in HUD
// ----------------------------------------------------------------
showLoadMenu(string invData)
{
    // Parse flower slots from inventory data
    list slots = llParseString2List(invData, ["^"], []);
    if (llGetListLength(slots) == 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "No flower in your inventory to load. Harvest a plant first.");
        return;
    }

    list qualNames = ["reggie","mids","loud","exotic"];
    list qualLabels = ["[R]","[M]","[L]","[E]"];
    list buttons;
    string menuText = "=== LOAD JAR ===\nChoose flower to load:\n\n";

    integer i;
    for (i = 0; i < llGetListLength(slots) && i < 9; i++)
    {
        list fields = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(fields) < 5) jump skip_slot;

        string strain  = llList2String(fields, 1);
        string quality = llList2String(fields, 2);
        string qty     = llList2String(fields, 3);
        integer qIdx   = llListFindList(qualNames, [quality]);
        string  qLabel = llList2String(qualLabels, qIdx);

        buttons += [llGetSubString(strain, 0, 10)];
        menuText += qLabel + " " + strain + " — " + qty + "g\n";
        @skip_slot;
    }
    buttons += ["Cancel"];

    if (g_listenLoad) llListenRemove(g_listenLoad);
    g_listenLoad = llListen(DCHAN_LOAD, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_LOAD);
    llSetTimerEvent(30.0);

    // Store slots for reference when player picks one
    llLinksetDataWrite("jar_temp_inv", invData);
}

// ----------------------------------------------------------------
// ACCESS MODE MENU
// ----------------------------------------------------------------
showAccessMenu()
{
    if (g_listenAccess) llListenRemove(g_listenAccess);
    g_listenAccess = llListen(DCHAN_ACCESS, "", g_ownerKey, "");

    list modes = ["Owner Only", "Group", "Open", "Back"];
    llDialog(g_ownerKey,
        "=== ACCESS MODE ===\nWho can take from this jar?\n\n" +
        "Owner Only — just you\n" +
        "Group — your SL group members\n" +
        "Open — anyone on your land",
        modes, DCHAN_ACCESS);
    llSetTimerEvent(30.0);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);

        loadState();
        updateVisuals();

        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");
        llListen(g_hudChannel, "", NULL_KEY, "");
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            // New owner — clear personal data, keep jar type
            llLinksetDataDeleteFound("jar_", "");
            llResetScript();
        }
    }

    timer()
    {
        // Dialog timeout cleanup
        if (g_listenOwner)   { llListenRemove(g_listenOwner);   g_listenOwner   = 0; }
        if (g_listenLoad)    { llListenRemove(g_listenLoad);     g_listenLoad    = 0; }
        if (g_listenAccess)  { llListenRemove(g_listenAccess);   g_listenAccess  = 0; }
        if (g_listenVisitor) { llListenRemove(g_listenVisitor);  g_listenVisitor = 0; }
        llSetTimerEvent(0.0);

        if (!g_registered)
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't reach your HUD. Make sure your Cultivar HUD is worn.");
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);

        if (toucher == g_ownerKey)
        {
            pingHUD();
            // Show menu after HUD responds — handled in listen()
            // Store intent so listen knows what to do after registration
            llLinksetDataWrite("jar_pending_action", "owner_menu");
        }
        else if (hasAccess(toucher))
        {
            // Non-owner with access — direct smoke interaction
            if (g_grams > 0)
                showVisitorMenu(toucher);
            else
                llRegionSayTo(toucher, 0,
                    "The jar is empty. Ask " + g_ownerName + " to restock.");
        }
        else
        {
            // No access
            string accessMsg = "This jar is ";
            if (g_accessMode == 0)
                accessMsg += "private (owner only).";
            else if (g_accessMode == 1)
                accessMsg += "for group members only.";
            llRegionSayTo(toucher, 0, accessMsg);
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // HUD registration response
        if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;

            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            llSetTimerEvent(0.0);

            // Act on pending action
            string pending = llLinksetDataRead("jar_pending_action");
            llLinksetDataDelete("jar_pending_action");

            if (pending == "owner_menu")
                showOwnerMenu();
            else if (pending == "load_flower")
            {
                // Request flower inventory
                llRegionSayTo(g_ownerKey, g_hudChannel,
                    "TC_INVENTORY_REQUEST|flower_raw|" + (string)llGetKey());
            }
        }

        // HUD sends back flower inventory for load menu
        else if (channel == g_hudChannel && cmd == "TC_INVENTORY_DATA")
        {
            showLoadMenu(llList2String(parts, 1));
        }

        // OWNER MENU response
        else if (channel == DCHAN_OWNER)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);
            if (g_listenOwner) { llListenRemove(g_listenOwner); g_listenOwner = 0; }

            if (msg == "Take A Hit")
                doSmoke(g_ownerKey);

            else if (msg == "Load Flower" || msg == "Load More")
            {
                llLinksetDataWrite("jar_pending_action", "load_flower");
                pingHUD();
            }

            else if (msg == "Empty Jar")
                emptyJar();

            else if (msg == "Access Mode")
                showAccessMenu();

            else if (msg == "Jar Info")
            {
                llRegionSayTo(g_ownerKey, 0,
                    "=== JAR INFO ===\n" +
                    "Type: " + g_jarType + "\n" +
                    "Capacity: " + (string)g_capacity + "g\n" +
                    "Contents: " + (string)g_grams + "g\n" +
                    (g_grams > 0 ?
                        "Strain: " + g_strain + " [" + g_quality + "]\n" +
                        "Packed by: " + g_packager : "Empty"));
            }
        }

        // LOAD FLOWER response — player picked a strain
        else if (channel == DCHAN_LOAD)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);
            if (g_listenLoad) { llListenRemove(g_listenLoad); g_listenLoad = 0; }

            if (msg == "Cancel") return;

            // Match button label to inventory slot
            string tempInv = llLinksetDataRead("jar_temp_inv");
            llLinksetDataDelete("jar_temp_inv");
            list slots = llParseString2List(tempInv, ["^"], []);

            integer i;
            for (i = 0; i < llGetListLength(slots); i++)
            {
                list fields = llParseString2List(llList2String(slots, i), ["~"], []);
                if (llGetListLength(fields) < 5) jump skip_match;

                string strain = llList2String(fields, 1);
                if (llGetSubString(strain, 0, 10) == msg)
                {
                    string  quality  = llList2String(fields, 2);
                    integer qty      = (integer)llList2String(fields, 3);
                    string  packager = llList2String(fields, 4);

                    // How much to load — all available or up to capacity
                    integer space   = g_capacity - g_grams;
                    integer toLoad  = qty;
                    if (toLoad > space) toLoad = space;

                    // Remove from HUD inventory
                    llRegionSayTo(g_ownerKey, g_hudChannel,
                        "TC_REMOVE_ITEM|flower_raw|" + strain + "|" +
                        quality + "|" + (string)toLoad + "|" + packager);

                    // Load immediately — TC_REMOVE_OK confirms but we trust it
                    // A more robust version would wait for TC_REMOVE_OK
                    loadJar(strain, quality, toLoad, packager);
                    return;
                }
                @skip_match;
            }
            llRegionSayTo(g_ownerKey, 0, "Couldn't find that strain. Try again.");
        }

        // ACCESS MODE response
        else if (channel == DCHAN_ACCESS)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);
            if (g_listenAccess) { llListenRemove(g_listenAccess); g_listenAccess = 0; }

            if (msg == "Back")    { showOwnerMenu(); return; }
            if (msg == "Owner Only") g_accessMode = 0;
            if (msg == "Group")      g_accessMode = 1;
            if (msg == "Open")       g_accessMode = 2;

            list accessLabels = ["Owner Only", "Group", "Open"];
            llOwnerSay("Jar access set to: " +
                       llList2String(accessLabels, g_accessMode));
            saveState();
            updateVisuals();
        }

        // VISITOR MENU response
        else if (channel == DCHAN_VISITOR)
        {
            llSetTimerEvent(0.0);
            if (g_listenVisitor) { llListenRemove(g_listenVisitor); g_listenVisitor = 0; }

            if (msg == "Take A Hit")
                doSmoke(id);
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != JCHAN_MAIN) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Session object telling jar to go into session mode
        if (cmd == "SESSION_ACTIVE")
        {
            g_inSession  = TRUE;
            g_sessionKey = id;
            // Update hover text to show session mode
            updateHoverText();
        }
        else if (cmd == "SESSION_END")
        {
            g_inSession  = FALSE;
            g_sessionKey = NULL_KEY;
            updateHoverText();
        }
    }
}
