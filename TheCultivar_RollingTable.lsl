// ================================================================
// THE CULTIVAR — Rolling Table Main Script
// Version: 1.0
// Handles: Crafting joints, blunts, and spliffs from flower_raw.
//          Uses the same TC_PING/REGISTER flow as all other tables.
//
// CRAFTING RATIOS:
//   Joint   : 1g flower → 1 joint    (single, clean, classic)
//   Blunt   : 2g flower → 1 blunt    (thicker, longer burn)
//   Spliff   : 1g flower → 1 spliff  (mixed, light touch)
//
// BATCH CRAFTING:
//   Players can craft 1, 3, 5, or fill — "fill" crafts as many
//   as their flower stock allows (up to 20 at once).
//
// OUTPUT:
//   Items are added to HUD inventory as itemType=joint/blunt/spliff
//   with the same strain, quality, and packager as the source flower.
//   The player's name is stamped as packager on crafted items.
//
// PRIM LINK STRUCTURE:
//   Link 1 (root) : Table body
//   Link 2        : Rolling surface / mat prim (color by quality tier)
//   Link 3        : Particle emitter (rolling cloud of resin wisps)
//   Link 4        : Completed item display prim (shows after craft)
//
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

integer DCHAN_TYPE    = -112001;
integer DCHAN_STRAIN  = -112002;
integer DCHAN_BATCH   = -112003;
integer DCHAN_CONFIRM = -112004;

integer g_listenRegister;
integer g_listenHUD;       // opened on g_hudChannel after TC_REGISTER
integer g_listenType;
integer g_listenStrain;
integer g_listenBatch;
integer g_listenConfirm;

key     g_ownerKey    = NULL_KEY;
string  g_ownerName   = "";
string  g_brandName   = "";   // brand name received from HUD (used as packager)
integer g_hudChannel  = 0;
integer g_registered  = FALSE;
integer g_busy        = FALSE;
integer g_craftDisplayActive = FALSE; // TRUE while post-craft visuals are showing

// Available flower from HUD — parsed on each session
// Stride 4: [strain, quality, qty, packager]
list    g_availableFlower;
integer FLOWER_STRIDE = 4;

// Transaction state
string  g_selectedType     = "";  // joint | blunt | spliff
string  g_selectedStrain   = "";
string  g_selectedQuality  = "";
string  g_selectedPackager = "";
integer g_selectedFlowerQty = 0;
integer g_batchCount       = 0;
integer g_costPerItem      = 0;
integer g_totalCost        = 0;

// Craft cost per item in grams
list ITEM_TYPES  = ["Joint",  "Blunt", "Spliff"];
list ITEM_COSTS  = [1,        2,       1      ];
list ITEM_IDS    = ["joint",  "blunt", "spliff"];

// ----------------------------------------------------------------
// Derive HUD channel from UUID
// ----------------------------------------------------------------
integer deriveHUDChannel(key id)
{
    string h = llGetSubString((string)id, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

// ----------------------------------------------------------------
// Ping HUD
// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|rolling_table");
    llSetTimerEvent(10.0);
}

// ----------------------------------------------------------------
// Parse flower inventory data from HUD
// ----------------------------------------------------------------
parseFlowerInventory(string rawData)
{
    g_availableFlower = [];
    if (rawData == "") return;
    list slots = llParseString2List(rawData, ["^"], []);
    integer i;
    for (i = 0; i < llGetListLength(slots); i++)
    {
        list fields = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(fields) == 5 &&
            llList2String(fields, 0) == "flower_raw")
        {
            g_availableFlower += [
                llList2String(fields, 1),
                llList2String(fields, 2),
                llList2String(fields, 3),
                llList2String(fields, 4)
            ];
        }
    }
}

// ----------------------------------------------------------------
// Close all dialog listens
// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenType)    { llListenRemove(g_listenType);    g_listenType    = 0; }
    if (g_listenStrain)  { llListenRemove(g_listenStrain);  g_listenStrain  = 0; }
    if (g_listenBatch)   { llListenRemove(g_listenBatch);   g_listenBatch   = 0; }
    if (g_listenConfirm) { llListenRemove(g_listenConfirm); g_listenConfirm = 0; }
}

// ----------------------------------------------------------------
// STEP 1: Pick item type
// ----------------------------------------------------------------
showTypeMenu()
{
    closeAllListens();
    g_listenType = llListen(DCHAN_TYPE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== ROLLING TABLE ===\nWhat are you rolling?\n\n" +
        "Joint   — 1g each, clean burn\n" +
        "Blunt   — 2g each, slow and thick\n" +
        "Spliff   — 1g each, light mix",
        ["Joint", "Blunt", "Spliff", "Cancel"], DCHAN_TYPE);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 2: Pick strain
// ----------------------------------------------------------------
showStrainMenu()
{
    closeAllListens();
    if (llGetListLength(g_availableFlower) == 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "No flower to roll with. Harvest a plant first.");
        g_busy = FALSE;
        return;
    }

    list qualNames  = ["reggie","mids","loud","exotic"];
    list qualLabels = ["[R]","[M]","[L]","[E]"];
    list buttons;
    string menuText = "=== SELECT FLOWER ===\n" +
                      "Rolling: " + g_selectedType + "\n\n";

    integer i;
    for (i = 0; i < llGetListLength(g_availableFlower) && i < FLOWER_STRIDE * 9;
         i += FLOWER_STRIDE)
    {
        string  strain  = llList2String(g_availableFlower, i);
        string  quality = llList2String(g_availableFlower, i + 1);
        string  qty     = llList2String(g_availableFlower, i + 2);
        integer qIdx    = llListFindList(qualNames, [quality]);
        string  qLabel  = llList2String(qualLabels, qIdx);

        buttons   += [llGetSubString(strain, 0, 10)];
        menuText  += qLabel + " " + strain + " — " + qty + "g\n";
    }
    buttons += ["Back", "Cancel"];
    g_listenStrain = llListen(DCHAN_STRAIN, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_STRAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 3: Pick batch size
// ----------------------------------------------------------------
showBatchMenu()
{
    closeAllListens();

    // How many can they afford?
    integer maxBatch = g_selectedFlowerQty / g_costPerItem;
    if (maxBatch <= 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "Not enough flower. You need at least " +
            (string)g_costPerItem + "g for one " +
            llToLower(g_selectedType) + ".");
        g_busy = FALSE;
        return;
    }

    list   buttons;
    string menuText = "=== HOW MANY? ===\n" +
                      g_selectedType + " — " + g_selectedStrain +
                      " [" + g_selectedQuality + "]\n" +
                      (string)g_selectedFlowerQty + "g available " +
                      "(" + (string)g_costPerItem + "g each)\n\n" +
                      "Max you can roll: " + (string)maxBatch + "\n";

    list counts = [1, 3, 5, 10, 20];
    integer c;
    for (c = 0; c < llGetListLength(counts); c++)
    {
        integer n = llList2Integer(counts, c);
        if (n <= maxBatch)
            buttons += [(string)n];
    }
    // "Fill" — roll as many as possible up to 20
    if (maxBatch > 20) maxBatch = 20;
    if (!~llListFindList(buttons, [(string)maxBatch]))
        buttons += [(string)maxBatch + " (max)"];
    buttons += ["Back", "Cancel"];

    g_listenBatch = llListen(DCHAN_BATCH, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_BATCH);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 4: Confirm
// ----------------------------------------------------------------
showConfirm()
{
    closeAllListens();
    g_listenConfirm = llListen(DCHAN_CONFIRM, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== CONFIRM ROLL ===\n\n" +
        "Crafting: " + (string)g_batchCount + "x " + g_selectedType + "\n" +
        "Strain:   " + g_selectedQuality + " " + g_selectedStrain + "\n" +
        "Cost:     " + (string)g_totalCost + "g of flower",
        ["Roll It!", "Cancel"], DCHAN_CONFIRM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Execute the craft — remove flower, add items, trigger effects
// ----------------------------------------------------------------
executeCraft()
{
    g_busy = TRUE;
    // Tell HUD to remove the flower
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_REMOVE_ITEM|flower_raw|" + g_selectedStrain + "|" +
        g_selectedQuality + "|" + (string)g_totalCost + "|" +
        g_selectedPackager);
    llSetTimerEvent(10.0); // wait for TC_REMOVE_OK
}

// ----------------------------------------------------------------
// Craft confirmed by HUD — add items and play effects
// ----------------------------------------------------------------
finishCraft()
{
    string itemID = llList2String(ITEM_IDS,
                   llListFindList(ITEM_TYPES, [g_selectedType]));

    // Add crafted items to HUD inventory
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|" + itemID + "|" + g_selectedStrain + "|" +
        g_selectedQuality + "|" + (string)g_batchCount + "|" + g_brandName);

    // Grant roller XP (1 XP per rolled item)
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_XP_UPDATE|roller|" + (string)g_batchCount);

    // Visual effects — quality-tinted particle burst from table surface
    vector col = qualColor(g_selectedQuality);
    llLinkParticleSystem(3, [
        PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                   PSYS_PART_INTERP_SCALE_MASK |
                                   PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     col,
        PSYS_PART_END_COLOR,       <1.0, 1.0, 1.0>,
        PSYS_PART_START_ALPHA,     0.7,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.04, 0.04, 0.0>,
        PSYS_PART_END_SCALE,       <0.1, 0.1, 0.0>,
        PSYS_PART_MAX_AGE,         3.0,
        PSYS_SRC_BURST_RATE,       0.05,
        PSYS_SRC_BURST_PART_COUNT, 8,
        PSYS_SRC_BURST_SPEED_MIN,  0.03,
        PSYS_SRC_BURST_SPEED_MAX,  0.08,
        PSYS_SRC_MAX_AGE,          1.2
    ]);

    // Light up rolling mat (link 2) briefly
    llSetLinkPrimitiveParamsFast(2, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_GLOW,  ALL_SIDES, 0.15
    ]);

    // Show completed item on display prim (link 4) briefly
    llSetLinkPrimitiveParamsFast(4, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_TEXT,
            (string)g_batchCount + "x " + g_selectedType + "\n" +
            g_selectedStrain,
        col, 1.0
    ]);

    llPlaySound("rolling_done", 0.6);

    // Notify player
    string rollPl = "";
    if (g_batchCount > 1) rollPl = "s";
    llRegionSayTo(g_ownerKey, 0,
        "✓ Rolled " + (string)g_batchCount + "x " +
        g_selectedQuality + " " + g_selectedStrain + " " +
        llToLower(g_selectedType) + rollPl +
        " (" + (string)g_totalCost + "g used)");

    // Schedule visual fade-down — g_craftDisplayActive flag is checked in timer()
    // so we never call llSleep() inside a listen handler
    g_craftDisplayActive = TRUE;
    llSetTimerEvent(3.0);
}

// ----------------------------------------------------------------
// Quality color helper
// ----------------------------------------------------------------
vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0, 0.85, 0.2>;
    if (quality == "loud")   return <0.2, 0.85, 0.3>;
    if (quality == "exotic") return <0.7, 0.3,  1.0>;
    return <0.55, 0.45, 0.3>;
}

// ----------------------------------------------------------------
// Clear transaction state
// ----------------------------------------------------------------
resetTransaction()
{
    g_selectedType      = "";
    g_selectedStrain    = "";
    g_selectedQuality   = "";
    g_selectedPackager  = "";
    g_selectedFlowerQty = 0;
    g_batchCount        = 0;
    g_costPerItem       = 0;
    g_totalCost         = 0;
}

// ----------------------------------------------------------------
// Hover text
// ----------------------------------------------------------------
updateHoverText()
{
    string status = "Touch to begin";
    if (g_registered) status = "Touch to roll";
    llSetText("THE CULTIVAR\nRolling Table\n" + status,
              <0.55, 0.45, 0.3>, 1.0);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");
        updateHoverText();
    }

    on_rez(integer start_param) { llResetScript(); }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    timer()
    {
        // Post-craft visual fade — fires 3s after finishCraft()
        if (g_craftDisplayActive)
        {
            g_craftDisplayActive = FALSE;
            llLinkParticleSystem(3, []);
            llSetLinkPrimitiveParamsFast(2, [
                PRIM_COLOR, ALL_SIDES, <0.3, 0.25, 0.2>, 1.0,
                PRIM_GLOW,  ALL_SIDES, 0.0
            ]);
            llSetLinkPrimitiveParamsFast(4, [
                PRIM_COLOR, ALL_SIDES, <0.3, 0.25, 0.2>, 0.0,
                PRIM_TEXT, "", ZERO_VECTOR, 0.0
            ]);
            g_busy = FALSE;
            resetTransaction();
            llSetTimerEvent(0.0);
            return;
        }

        // Dialog / HUD-registration timeout
        closeAllListens();
        llSetTimerEvent(0.0);
        g_busy = FALSE;

        if (!g_registered)
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't reach your HUD. Make sure your Cultivar HUD is worn.");
        else if (g_selectedStrain != "")
        {
            llRegionSayTo(g_ownerKey, 0, "Rolling session timed out.");
            resetTransaction();
        }
    }

    touch_start(integer nd)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (g_busy)
        {
            llRegionSayTo(g_ownerKey, 0, "Still working...");
            return;
        }
        g_ownerKey  = llDetectedKey(0);
        g_ownerName = llKey2Name(g_ownerKey);
        pingHUD();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // HUD registration
        if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);
            g_brandName  = llList2String(parts, 4);
            if (g_brandName == "") g_brandName = g_ownerName;
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            // Open listener on the derived HUD channel so TC_INVENTORY_DATA /
            // TC_REMOVE_OK / TC_REMOVE_FAIL can be received
            if (g_listenHUD) { llListenRemove(g_listenHUD); g_listenHUD = 0; }
            g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");
            llSetTimerEvent(0.0);
            updateHoverText();
            // Request flower inventory
            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_INVENTORY_REQUEST|flower_raw|" + (string)llGetKey());
        }

        // HUD sends flower inventory
        else if (channel == g_hudChannel && cmd == "TC_INVENTORY_DATA")
        {
            parseFlowerInventory(llList2String(parts, 1));
            showTypeMenu();
        }

        // HUD confirms flower removed
        else if (channel == g_hudChannel && cmd == "TC_REMOVE_OK")
        {
            llSetTimerEvent(0.0);
            finishCraft();
        }

        // HUD says not enough flower
        else if (channel == g_hudChannel && cmd == "TC_REMOVE_FAIL")
        {
            llSetTimerEvent(0.0);
            g_busy = FALSE;
            llRegionSayTo(g_ownerKey, 0, "Not enough flower. Check your inventory.");
            resetTransaction();
        }

        // TYPE SELECTION
        else if (channel == DCHAN_TYPE && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; return; }
            g_selectedType  = msg;
            integer typeIdx = llListFindList(ITEM_TYPES, [msg]);
            g_costPerItem   = llList2Integer(ITEM_COSTS, typeIdx);
            showStrainMenu();
        }

        // STRAIN SELECTION
        else if (channel == DCHAN_STRAIN && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; return; }
            if (msg == "Back")   { showTypeMenu(); return; }

            integer i;
            for (i = 0; i < llGetListLength(g_availableFlower); i += FLOWER_STRIDE)
            {
                string strain = llList2String(g_availableFlower, i);
                if (llGetSubString(strain, 0, 10) == msg)
                {
                    g_selectedStrain    = strain;
                    g_selectedQuality   = llList2String(g_availableFlower, i + 1);
                    g_selectedFlowerQty = (integer)llList2String(g_availableFlower, i + 2);
                    g_selectedPackager  = llList2String(g_availableFlower, i + 3);
                    jump found;
                }
            }
            llRegionSayTo(g_ownerKey, 0, "Couldn't match that strain. Try again.");
            showStrainMenu();
            return;
            @found;
            showBatchMenu();
        }

        // BATCH SELECTION
        else if (channel == DCHAN_BATCH && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; return; }
            if (msg == "Back")   { showStrainMenu(); return; }

            // Strip " (max)" suffix if present
            string numStr = msg;
            integer spaceIdx = llSubStringIndex(msg, " ");
            if (spaceIdx != -1) numStr = llGetSubString(msg, 0, spaceIdx - 1);

            g_batchCount = (integer)numStr;
            g_totalCost  = g_batchCount * g_costPerItem;

            if (g_totalCost > g_selectedFlowerQty)
            {
                llRegionSayTo(g_ownerKey, 0,
                    "Not enough flower for " + (string)g_batchCount +
                    ". Max: " + (string)(g_selectedFlowerQty / g_costPerItem));
                showBatchMenu();
                return;
            }
            showConfirm();
        }

        // CONFIRM
        else if (channel == DCHAN_CONFIRM && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; resetTransaction(); return; }
            if (msg == "Roll It!") executeCraft();
        }
    }
}
