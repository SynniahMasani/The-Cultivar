// ================================================================
// THE CULTIVAR — Breeding Station Script
// Version: 1.0
// Handles: Strain hybridization — combines two parent strains to
//          create a new hybrid seed with grow bonuses.
//
// HOW IT WORKS:
//   Owner touches the station → sees parent selection menus
//   → picks Parent A and Parent B (must be different)
//   → station consumes 1 of each seed from HUD inventory
//   → creates 3 hybrid seeds with name "ParentA x ParentB"
//   → if both parents are exotic: marks hybrid [LEGENDARY]
//   → grants 3 grower XP for each successful breed
//
// HYBRID BONUSES (detected by Plant_Grow_v1.1.lsl):
//   Standard hybrid (contains " x "):
//     Quality baseline = Loud (tier 2), +10% yield, -8% grow time
//   Legendary hybrid (both exotic parents, suffix [LEGENDARY]):
//     Quality baseline = Exotic (tier 3), +20% yield, -15% grow time
//
// SEED INVENTORY:
//   Reads HUD inventory via TC_REQUEST_INVENTORY / TC_INVENTORY_DATA
//   Consumes seeds via TC_CONSUME_ITEM
//   Adds hybrid seeds via TC_ADD_ITEM on harvest result protocol
//
// HUD REGISTRATION:
//   Listens for TC_REGISTER response on channel 0, then stores
//   the owner's HUD private channel for direct communication.
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

// Dialog channels
integer DCHAN_BREED_MAIN   = -202001;
integer DCHAN_PARENT_A     = -202002;
integer DCHAN_PARENT_B     = -202003;
integer DCHAN_BREED_CONFIRM = -202004;

integer g_listenMain;
integer g_listenParentA;
integer g_listenParentB;
integer g_listenConfirm;
integer g_listenRegister;
integer g_listenHUD;

key     g_ownerKey    = NULL_KEY;
string  g_ownerName   = "";
integer g_hudChannel  = 0;
integer g_registered  = FALSE;

// Pending breed selections
string  g_parentAName    = "";
integer g_parentAQuality = 0; // quality tier (0-3)
string  g_parentBName    = "";
integer g_parentBQuality = 0;

// Available seeds from HUD inventory — populated on breed start
// Format: [strainName, qualityTier, ...]  (stride 2)
list    g_availableSeeds;
integer SEED_STRIDE = 2;

// Known exotic strains for quality tier detection
list EXOTIC_STRAINS = ["Runtz", "Biscotti", "Jealousy", "Lemon Cherry Gelato"];
list LOUD_STRAINS   = ["OG Kush", "Wedding Cake", "Zkittlez", "Gelato"];
list MIDS_STRAINS   = ["Blue Dream", "Green Crack", "Gorilla Glue", "Sour Diesel"];

// ----------------------------------------------------------------
// Derive HUD channel from UUID
// ----------------------------------------------------------------
integer deriveHUDChannel(key ownerID)
{
    string h = llGetSubString((string)ownerID, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
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
        "TC_PING|" + (string)llGetKey() + "|breed_station");
    llSetTimerEvent(8.0);
}

// ----------------------------------------------------------------
// Close all open dialog listens
// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenMain)     { llListenRemove(g_listenMain);     g_listenMain    = 0; }
    if (g_listenParentA)  { llListenRemove(g_listenParentA);  g_listenParentA = 0; }
    if (g_listenParentB)  { llListenRemove(g_listenParentB);  g_listenParentB = 0; }
    if (g_listenConfirm)  { llListenRemove(g_listenConfirm);  g_listenConfirm = 0; }
    if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
}

// ----------------------------------------------------------------
// Detect quality tier from strain name
// ----------------------------------------------------------------
integer qualityTierOf(string strain)
{
    if (llListFindList(EXOTIC_STRAINS, [strain]) != -1) return 3;
    if (llListFindList(LOUD_STRAINS,   [strain]) != -1) return 2;
    if (llListFindList(MIDS_STRAINS,   [strain]) != -1) return 1;
    // Hybrid strains — extract from [LEGENDARY] suffix or default to loud
    if (llSubStringIndex(strain, "[LEGENDARY]") != -1) return 3;
    if (llSubStringIndex(strain, " x ") != -1) return 2;
    return 0; // reggie fallback
}

// ----------------------------------------------------------------
// Build available seeds list from raw inventory data
// Only includes seed_raw items (and seed_hybrid)
// ----------------------------------------------------------------
parseSeeds(string rawData)
{
    g_availableSeeds = [];
    if (rawData == "" || rawData == "EMPTY") return;
    list slots = llParseString2List(rawData, ["^"], []);
    integer i;
    for (i = 0; i < llGetListLength(slots); i++)
    {
        list f = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(f) < 5) jump skip_seed;
        string iType = llList2String(f, 0);
        if (iType == "seed_raw" || iType == "seed_hybrid")
        {
            string  strain = llList2String(f, 1);
            integer qty    = (integer)llList2String(f, 3);
            // Need at least 1 to use as parent
            if (qty < 1) jump skip_seed;
            // Skip duplicates
            if (llListFindList(g_availableSeeds, [strain]) == -1)
                g_availableSeeds += [strain, qualityTierOf(strain)];
        }
        @skip_seed;
    }
}

// ----------------------------------------------------------------
// MAIN BREED MENU
// ----------------------------------------------------------------
showBreedMenu()
{
    closeAllListens();
    integer seedCount = llGetListLength(g_availableSeeds) / SEED_STRIDE;
    g_listenMain = llListen(DCHAN_BREED_MAIN, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== BREEDING STATION ===\n" +
        "Available strains: " + (string)seedCount + "\n\n" +
        "Combine two strains to create a hybrid seed.\n" +
        "Exotic x Exotic = Legendary hybrid!\n" +
        "Costs: 1 seed of each parent.",
        ["Breed", "Close"],
        DCHAN_BREED_MAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// PARENT A SELECTION
// ----------------------------------------------------------------
showParentAMenu()
{
    closeAllListens();
    integer count = llGetListLength(g_availableSeeds) / SEED_STRIDE;
    if (count == 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "No seeds in your inventory to breed with.");
        return;
    }

    list   buttons;
    string menuText = "=== SELECT PARENT A ===\nChoose the first strain:\n\n";
    list qualNames = ["Reggie", "Mids", "Loud", "Exotic"];
    integer i;
    for (i = 0; i < count && llGetListLength(buttons) < 9; i++)
    {
        string  strain  = llList2String(g_availableSeeds, i * SEED_STRIDE);
        integer tier    = llList2Integer(g_availableSeeds, i * SEED_STRIDE + 1);
        string  qLabel  = llList2String(qualNames, tier);
        buttons  += [llGetSubString(strain, 0, 11)];
        menuText += "[" + qLabel + "] " + strain + "\n";
    }
    buttons += ["Back"];
    g_listenParentA = llListen(DCHAN_PARENT_A, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_PARENT_A);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// PARENT B SELECTION
// ----------------------------------------------------------------
showParentBMenu()
{
    closeAllListens();
    integer count = llGetListLength(g_availableSeeds) / SEED_STRIDE;

    list   buttons;
    string menuText = "=== SELECT PARENT B ===\nChoose the second strain:\n" +
                      "Parent A: " + g_parentAName + "\n\n";
    list qualNames = ["Reggie", "Mids", "Loud", "Exotic"];
    integer i;
    for (i = 0; i < count && llGetListLength(buttons) < 9; i++)
    {
        string  strain = llList2String(g_availableSeeds, i * SEED_STRIDE);
        integer tier   = llList2Integer(g_availableSeeds, i * SEED_STRIDE + 1);
        if (strain == g_parentAName) jump skip_a; // can't breed with itself
        string qLabel  = llList2String(qualNames, tier);
        buttons  += [llGetSubString(strain, 0, 11)];
        menuText += "[" + qLabel + "] " + strain + "\n";
        @skip_a;
    }
    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "Need at least two different strains to breed.");
        showParentAMenu();
        return;
    }
    buttons += ["Back"];
    g_listenParentB = llListen(DCHAN_PARENT_B, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_PARENT_B);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// BREED CONFIRM
// ----------------------------------------------------------------
showBreedConfirm()
{
    closeAllListens();
    integer isLegendary = (g_parentAQuality == 3 && g_parentBQuality == 3);
    string hybridName   = g_parentAName + " x " + g_parentBName;
    if (isLegendary) hybridName += " [LEGENDARY]";
    string tierHint = "Loud baseline, +10% yield, -8% grow time";
    if (isLegendary) tierHint = "Exotic baseline, +20% yield, -15% grow time — LEGENDARY!";

    g_listenConfirm = llListen(DCHAN_BREED_CONFIRM, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== CONFIRM BREED ===\n" +
        "Parent A: " + g_parentAName + "\n" +
        "Parent B: " + g_parentBName + "\n\n" +
        "Hybrid: " + hybridName + "\n" +
        tierHint + "\n\n" +
        "Costs 1 seed of each parent.\n" +
        "Yields 3 hybrid seeds.",
        ["Breed!", "Cancel"],
        DCHAN_BREED_CONFIRM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Perform the actual breed — consume parents, create hybrid
// ----------------------------------------------------------------
performBreed()
{
    integer isLegendary = (g_parentAQuality == 3 && g_parentBQuality == 3);
    string hybridName   = g_parentAName + " x " + g_parentBName;
    if (isLegendary) hybridName += " [LEGENDARY]";

    // Consume 1 seed of each parent from HUD inventory
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_CONSUME_ITEM|seed_raw|" + g_parentAName + "|1");
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_CONSUME_ITEM|seed_raw|" + g_parentBName + "|1");

    // Add 3 hybrid seeds to HUD inventory
    string hybridQuality = "loud";
    if (isLegendary) hybridQuality = "exotic";
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|seed_hybrid|" + hybridName + "|" +
        hybridQuality + "|3|" + g_ownerName);

    // Grant grower XP for breeding (3 XP)
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_XP_UPDATE|grower|3");

    // Announce result
    string msg = "Bred " + g_parentAName + " x " + g_parentBName +
                 "! You now have 3 hybrid seeds: \"" + hybridName + "\"";
    if (isLegendary)
        msg += "\n✨ LEGENDARY cross! This one has exceptional grow bonuses.";
    llRegionSayTo(g_ownerKey, 0, msg);

    // Play a particle effect to celebrate
    llParticleSystem([
        PSYS_PART_FLAGS,    PSYS_PART_EMISSIVE_MASK | PSYS_PART_INTERP_COLOR_MASK,
        PSYS_SRC_PATTERN,   PSYS_SRC_PATTERN_EXPLODE,
        PSYS_PART_START_COLOR,  <0.5, 1.0, 0.3>,
        PSYS_PART_END_COLOR,    <1.0, 1.0, 0.5>,
        PSYS_PART_START_ALPHA,  0.9,
        PSYS_PART_END_ALPHA,    0.0,
        PSYS_PART_START_SCALE,  <0.05, 0.05, 0.0>,
        PSYS_PART_END_SCALE,    <0.02, 0.02, 0.0>,
        PSYS_PART_MAX_AGE,      2.0,
        PSYS_SRC_BURST_RATE,    0.1,
        PSYS_SRC_BURST_PART_COUNT, 15,
        PSYS_SRC_MAX_AGE,       1.0
    ]);
    llSleep(1.5);
    llParticleSystem([]);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);
        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");
        llSetText("THE CULTIVAR\nBreeding Station\nTouch to breed strains\nOwner: " +
                  g_ownerName, <0.6, 0.9, 0.4>, 1.0);
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    timer()
    {
        closeAllListens();
        llSetTimerEvent(0.0);
        g_parentAName = "";
        g_parentBName = "";
        if (!g_registered)
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't reach your HUD. Make sure your Cultivar HUD is worn.");
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);
        if (toucher != g_ownerKey)
        {
            llRegionSayTo(toucher, 0,
                "This breeding station belongs to " + g_ownerName + ".");
            return;
        }
        pingHUD();
        llLinksetDataWrite("station_intent", "breed");
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- HUD registration ----
        if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;

            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;
            llSetTimerEvent(0.0);

            string intent = llLinksetDataRead("station_intent");
            llLinksetDataDelete("station_intent");
            if (intent == "breed")
            {
                // Keep g_listenRegister open — TC_INVENTORY_DATA arrives on channel 0
                llRegionSayTo(g_ownerKey, g_hudChannel,
                    "TC_REQUEST_RAW_INVENTORY|seed_raw");
                llSetTimerEvent(8.0); // wait for inventory response
            }
            else
            {
                // No pending intent, no further channel-0 messages expected
                if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            }
        }

        // ---- Inventory data response ----
        else if (channel == 0 && cmd == "TC_INVENTORY_DATA")
        {
            llSetTimerEvent(0.0);
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            string rawData = llList2String(parts, 1);
            parseSeeds(rawData);
            if (llGetListLength(g_availableSeeds) < 4) // need at least 2 strains
            {
                llRegionSayTo(g_ownerKey, 0,
                    "You need at least 2 different seed types in your inventory to breed.");
                return;
            }
            showBreedMenu();
        }

        // ---- MAIN BREED MENU ----
        else if (channel == DCHAN_BREED_MAIN && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenMain) { llListenRemove(g_listenMain); g_listenMain = 0; }
            if (msg == "Breed") showParentAMenu();
            // "Close" — do nothing
        }

        // ---- PARENT A SELECTION ----
        else if (channel == DCHAN_PARENT_A && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenParentA) { llListenRemove(g_listenParentA); g_listenParentA = 0; }
            if (msg == "Back") { showBreedMenu(); return; }

            // Resolve truncated name
            integer count = llGetListLength(g_availableSeeds) / SEED_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string strain = llList2String(g_availableSeeds, i * SEED_STRIDE);
                if (llGetSubString(strain, 0, 11) == msg)
                {
                    g_parentAName    = strain;
                    g_parentAQuality = llList2Integer(g_availableSeeds, i * SEED_STRIDE + 1);
                    showParentBMenu();
                    return;
                }
            }
            llRegionSayTo(g_ownerKey, 0, "Strain not found. Try again.");
            showParentAMenu();
        }

        // ---- PARENT B SELECTION ----
        else if (channel == DCHAN_PARENT_B && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenParentB) { llListenRemove(g_listenParentB); g_listenParentB = 0; }
            if (msg == "Back") { showParentAMenu(); return; }

            integer count = llGetListLength(g_availableSeeds) / SEED_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string strain = llList2String(g_availableSeeds, i * SEED_STRIDE);
                if (strain == g_parentAName) jump skip_b;
                if (llGetSubString(strain, 0, 11) == msg)
                {
                    g_parentBName    = strain;
                    g_parentBQuality = llList2Integer(g_availableSeeds, i * SEED_STRIDE + 1);
                    showBreedConfirm();
                    return;
                }
                @skip_b;
            }
            llRegionSayTo(g_ownerKey, 0, "Strain not found. Try again.");
            showParentBMenu();
        }

        // ---- BREED CONFIRM ----
        else if (channel == DCHAN_BREED_CONFIRM && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenConfirm) { llListenRemove(g_listenConfirm); g_listenConfirm = 0; }
            if (msg == "Breed!")
                performBreed();
            // Reset parents either way
            g_parentAName = "";
            g_parentBName = "";
        }
    }
}
