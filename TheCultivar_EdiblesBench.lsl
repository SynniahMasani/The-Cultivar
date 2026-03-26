// ================================================================
// THE CULTIVAR  -  Edibles & Concentrate Bench Script
// Version: 1.0
// Handles: Crafting edible and concentrate items from flower_raw.
//          Two modes: Edibles and Press  -  owner picks via menu.
//
// CRAFTING RATIOS:
//   Brownie  : 3g  -> 1 brownie         (slow onset, long duration)
//   Gummies  : 4g  -> 8 gummies         (portioned, shareable)
//   Drink    : 2g  -> 1 infused drink   (fast onset)
//   Concentrate: 5g -> 1 concentrate    (potent, dab-ready)
//
// QUALITY SCALING:
//   Reggie    -  standard output
//   Mids      -  standard output, slightly better effects desc
//   Loud      -  +1 bonus item on batch (e.g. 3g -> 2 brownies)
//   Exotic    -  +2 bonus items on batch
//
// PRIM LINK STRUCTURE:
//   Link 1 (root) : Bench body
//   Link 2        : Prep surface (color by mode  -  warm for edibles, cool for press)
//   Link 3        : Burner/heat element (glows during crafting)
//   Link 4        : Output tray (flashes with completed item color)
//   Link 5        : Particle emitter (steam for edibles, vapor for concentrate)
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;
integer HOVER_FADE_SECS = 30;

integer DCHAN_MODE    = -113001;
integer DCHAN_ITEM    = -113002;
integer DCHAN_STRAIN  = -113003;
integer DCHAN_BATCH   = -113004;
integer DCHAN_CONFIRM = -113005;

integer g_replyChannel  = 0;
integer g_listenRegister;
integer g_listenHUD;
integer g_listenMode;
integer g_listenItem;
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
string  g_benchMode   = ""; // "edibles" or "press"

// Available flower
list    g_availableFlower;
integer FLOWER_STRIDE = 4;

// Transaction state
string  g_selectedItem     = "";  // edible_brownie | edible_gummy | edible_drink | concentrate
string  g_selectedStrain   = "";
string  g_selectedQuality  = "";
string  g_selectedPackager = "";
integer g_selectedFlowerQty = 0;
integer g_batchCount       = 0;
integer g_costPerItem      = 0;
integer g_totalCost        = 0;
integer g_outputCount      = 0;  // includes quality bonus

// Item definitions
// Edibles
list EDIBLE_NAMES  = ["Brownie",  "Gummies (x8)", "Infused Drink"];
list EDIBLE_IDS    = ["edible_brownie", "edible_gummy", "edible_drink"];
list EDIBLE_COSTS  = [3,           4,              2             ];
list EDIBLE_YIELDS = [1,           8,              1             ]; // base output per craft

// Concentrate
string CONC_ID    = "concentrate";
integer CONC_COST = 5;

// Quality bonus items added to output
list QUALITY_BONUS = [0, 0, 1, 2]; // reggie=0, mids=0, loud=+1, exotic=+2
list QUALITY_NAMES = ["reggie","mids","loud","exotic"];

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
    g_replyChannel   = (integer)(llFrand(1000000.0) + 1000000) * -1;
    g_listenRegister = llListen(g_replyChannel, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|edibles_bench|" +
        (string)g_replyChannel);
    llSetTimerEvent(10.0);
}

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

closeAllListens()
{
    if (g_listenMode)    { llListenRemove(g_listenMode);    g_listenMode    = 0; }
    if (g_listenItem)    { llListenRemove(g_listenItem);    g_listenItem    = 0; }
    if (g_listenStrain)  { llListenRemove(g_listenStrain);  g_listenStrain  = 0; }
    if (g_listenBatch)   { llListenRemove(g_listenBatch);   g_listenBatch   = 0; }
    if (g_listenConfirm) { llListenRemove(g_listenConfirm); g_listenConfirm = 0; }
}

vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0, 0.85, 0.2>;
    if (quality == "loud")   return <0.2, 0.85, 0.3>;
    if (quality == "exotic") return <0.7, 0.3,  1.0>;
    return <0.55, 0.45, 0.3>;
}

// ----------------------------------------------------------------
// Calculate total output including quality bonus
// ----------------------------------------------------------------
integer calcOutput(string itemID, string quality, integer batchCount)
{
    integer qIdx    = llListFindList(QUALITY_NAMES, [quality]);
    integer bonus   = llList2Integer(QUALITY_BONUS, qIdx);
    integer baseIdx = llListFindList(EDIBLE_IDS, [itemID]);
    integer baseYield;

    if (itemID == CONC_ID)
        baseYield = 1;
    else
        baseYield = llList2Integer(EDIBLE_YIELDS, baseIdx);

    return (baseYield + bonus) * batchCount;
}

// ----------------------------------------------------------------
// STEP 1: Mode select  -  edibles or concentrate press
// ----------------------------------------------------------------
showModeMenu()
{
    closeAllListens();
    g_listenMode = llListen(DCHAN_MODE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== CRAFTING BENCH ===\nWhat are you making?\n\n" +
        "Edibles   -  brownies, gummies, drinks\n" +
        "Press     -  concentrate / wax / oil",
        ["Edibles", "Press", "Cancel"], DCHAN_MODE);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 2a: Edible type select
// ----------------------------------------------------------------
showEdibleMenu()
{
    closeAllListens();
    g_listenItem = llListen(DCHAN_ITEM, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== EDIBLES ===\nChoose what to make:\n\n" +
        "Brownie       -  3g each, strong\n" +
        "Gummies(x8)   -  4g per batch\n" +
        "Infused Drink  -  2g each, fast",
        ["Brownie", "Gummies (x8)", "Infused Drink", "Back", "Cancel"],
        DCHAN_ITEM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 2b: Concentrate  -  no item pick needed, go straight to strain
// ----------------------------------------------------------------
// (falls through to showStrainMenu directly)

// ----------------------------------------------------------------
// STEP 3: Pick strain
// ----------------------------------------------------------------
showStrainMenu()
{
    closeAllListens();
    if (llGetListLength(g_availableFlower) == 0)
    {
        llRegionSayTo(g_ownerKey, 0, "No flower to work with. Harvest first.");
        g_busy = FALSE;
        return;
    }

    list qualNames  = ["reggie","mids","loud","exotic"];
    list qualLabels = ["[R]","[M]","[L]","[E]"];
    list buttons;
    string menuText = "=== SELECT FLOWER ===\n" +
                      "Making: " + g_selectedItem + "\n" +
                      (string)g_costPerItem + "g per craft\n\n";

    integer i;
    for (i = 0; i < llGetListLength(g_availableFlower) && i < FLOWER_STRIDE * 9;
         i += FLOWER_STRIDE)
    {
        string  strain  = llList2String(g_availableFlower, i);
        string  quality = llList2String(g_availableFlower, i + 1);
        string  qty     = llList2String(g_availableFlower, i + 2);
        integer qIdx    = llListFindList(qualNames, [quality]);
        string  qLabel  = llList2String(qualLabels, qIdx);
        buttons  += [llGetSubString(strain, 0, 10)];
        menuText += qLabel + " " + strain + "  -  " + qty + "g\n";
    }
    buttons += ["Back", "Cancel"];
    g_listenStrain = llListen(DCHAN_STRAIN, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_STRAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 4: Pick batch size
// ----------------------------------------------------------------
showBatchMenu()
{
    closeAllListens();
    integer maxBatch = g_selectedFlowerQty / g_costPerItem;
    if (maxBatch <= 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "Need at least " + (string)g_costPerItem +
            "g. You only have " + (string)g_selectedFlowerQty + "g.");
        g_busy = FALSE;
        return;
    }
    if (maxBatch > 10) maxBatch = 10; // cap for dialog buttons

    integer qIdx   = llListFindList(QUALITY_NAMES, [g_selectedQuality]);
    integer bonus  = llList2Integer(QUALITY_BONUS, qIdx);
    integer baseIdx = llListFindList(EDIBLE_IDS, [g_selectedItem]);
    integer yield;
    if (g_selectedItem == CONC_ID) yield = 1;
    else yield = llList2Integer(EDIBLE_YIELDS, baseIdx);
    string  bonusStr = "";
    if (bonus > 0) bonusStr = "  (+" + (string)bonus + " " + g_selectedQuality + " bonus!)";

    list   buttons;
    string menuText = "=== HOW MANY BATCHES? ===\n" +
                      g_selectedItem + "  -  " + g_selectedStrain +
                      "\nYield per batch: " + (string)(yield + bonus) +
                      bonusStr + "\n\n";

    integer b;
    for (b = 1; b <= maxBatch && b <= 9; b++)
        buttons += [(string)b];
    buttons += ["Back", "Cancel"];

    g_listenBatch = llListen(DCHAN_BATCH, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_BATCH);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 5: Confirm
// ----------------------------------------------------------------
showConfirm()
{
    closeAllListens();
    g_outputCount = calcOutput(g_selectedItem, g_selectedQuality, g_batchCount);
    g_listenConfirm = llListen(DCHAN_CONFIRM, "", g_ownerKey, "");

    string itemLabel = g_selectedItem;
    if (g_selectedItem == "edible_brownie") itemLabel = "brownie";
    else if (g_selectedItem == "edible_gummy") itemLabel = "gummy batch (x8)";
    else if (g_selectedItem == "edible_drink") itemLabel = "infused drink";

    llDialog(g_ownerKey,
        "=== CONFIRM CRAFT ===\n\n" +
        "Making: " + (string)g_outputCount + "x " + itemLabel + "\n" +
        "Strain: " + g_selectedQuality + " " + g_selectedStrain + "\n" +
        "Cost:   " + (string)g_totalCost + "g of flower",
        ["Make It!", "Cancel"], DCHAN_CONFIRM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Execute craft
// ----------------------------------------------------------------
executeCraft()
{
    g_busy = TRUE;
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_REMOVE_ITEM|flower_raw|" + g_selectedStrain + "|" +
        g_selectedQuality + "|" + (string)g_totalCost + "|" +
        g_selectedPackager);
    llSetTimerEvent(10.0);
}

// ----------------------------------------------------------------
// Finish craft after HUD confirms removal
// ----------------------------------------------------------------
finishCraft()
{
    // Add output to HUD inventory
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|" + g_selectedItem + "|" + g_selectedStrain + "|" +
        g_selectedQuality + "|" + (string)g_outputCount + "|" + g_brandName);

    vector col = qualColor(g_selectedQuality);

    // Bench mode determines visual flavor
    integer isPress = (g_benchMode == "press");

    // Burner glow (link 3)
    vector burnerCol = <1.0, 0.5, 0.1>;
    if (isPress) burnerCol = <0.5, 0.8, 1.0>;
    llSetLinkPrimitiveParamsFast(3, [
        PRIM_COLOR, ALL_SIDES, burnerCol, 1.0,
        PRIM_GLOW,  ALL_SIDES, 0.2
    ]);

    // Output tray flash (link 4)
    llSetLinkPrimitiveParamsFast(4, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_GLOW,  ALL_SIDES, 0.15,
        PRIM_TEXT,
            "? " + (string)g_outputCount + "x crafted",
        col, 1.0
    ]);

    // Particle steam or vapor (link 5)
    vector steamCol = <1.0, 0.95, 0.8>;
    if (isPress) steamCol = <0.7, 0.9, 1.0>;
    llLinkParticleSystem(5, [
        PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                   PSYS_PART_INTERP_SCALE_MASK |
                                   PSYS_PART_WIND_MASK |
                                   PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     steamCol,
        PSYS_PART_END_COLOR,       <1.0, 1.0, 1.0>,
        PSYS_PART_START_ALPHA,     0.5,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.05, 0.05, 0.0>,
        PSYS_PART_END_SCALE,       <0.15, 0.15, 0.0>,
        PSYS_PART_MAX_AGE,         5.0,
        PSYS_SRC_BURST_RATE,       0.15,
        PSYS_SRC_BURST_PART_COUNT, 4,
        PSYS_SRC_BURST_SPEED_MIN,  0.02,
        PSYS_SRC_BURST_SPEED_MAX,  0.06,
        PSYS_SRC_MAX_AGE,          3.0,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        0.25
    ]);

    string craftSound = "cook_done";
    if (isPress) craftSound = "press_done";
    llPlaySound(craftSound, 0.6);

    // Nice readable item label for the notification
    string itemLabel = g_selectedItem;
    if (g_selectedItem == "edible_brownie") itemLabel = "brownie";
    else if (g_selectedItem == "edible_gummy") itemLabel = "gummy pack";
    else if (g_selectedItem == "edible_drink") itemLabel = "infused drink";
    else if (g_selectedItem == "concentrate")  itemLabel = "concentrate";

    llRegionSayTo(g_ownerKey, 0,
        "? Crafted " + (string)g_outputCount + "x " +
        g_selectedQuality + " " + g_selectedStrain + " " + itemLabel +
        " (" + (string)g_totalCost + "g used)");

    // Schedule visual fade-down via timer  -  never call llSleep in a listen handler
    g_craftDisplayActive = TRUE;
    llSetTimerEvent(4.0);
}

resetTransaction()
{
    g_selectedItem      = "";
    g_selectedStrain    = "";
    g_selectedQuality   = "";
    g_selectedPackager  = "";
    g_selectedFlowerQty = 0;
    g_batchCount        = 0;
    g_costPerItem       = 0;
    g_totalCost         = 0;
    g_outputCount       = 0;
    g_benchMode         = "";
}

updateHoverText()
{
    string benchPrompt = "Touch to begin";
    if (g_registered) benchPrompt = "Touch to craft";
    llSetText("THE CULTIVAR\nEdibles Bench\n" + benchPrompt,
              <0.9, 0.6, 0.2>, 1.0);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llGetDisplayName(g_ownerKey);
        updateHoverText();
        llSetTimerEvent(HOVER_FADE_SECS);
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer change)     { if (change & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        // Post-craft visual fade  -  fires 4s after finishCraft()
        if (g_craftDisplayActive)
        {
            g_craftDisplayActive = FALSE;
            llLinkParticleSystem(5, []);
            llSetLinkPrimitiveParamsFast(3, [PRIM_GLOW, ALL_SIDES, 0.0]);
            llSetLinkPrimitiveParamsFast(4, [
                PRIM_GLOW, ALL_SIDES, 0.0,
                PRIM_TEXT, "", ZERO_VECTOR, 0.0
            ]);
            g_busy = FALSE;
            resetTransaction();
            llSetTimerEvent(HOVER_FADE_SECS);
            return;
        }

        // Idle fade: no active transaction — fade hover text and stop timer
        if (!g_busy)
        {
            string benchPrompt = "Touch to begin";
            if (g_registered) benchPrompt = "Touch to craft";
            llSetText("THE CULTIVAR\nEdibles Bench\n" + benchPrompt,
                      <0.9, 0.6, 0.2>, 0.0);
            llSetTimerEvent(0.0);
            return;
        }

        // Dialog / HUD-registration timeout
        closeAllListens();
        g_busy = FALSE;
        if (!g_registered)
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't reach your HUD. Make sure it's worn.");
        else if (g_selectedStrain != "")
        {
            llRegionSayTo(g_ownerKey, 0, "Crafting session timed out.");
            resetTransaction();
        }
        llSetTimerEvent(HOVER_FADE_SECS);
    }

    touch_start(integer nd)
    {
        updateHoverText();
        if (llDetectedKey(0) != llGetOwner()) return;
        if (g_busy) { llRegionSayTo(g_ownerKey, 0, "Still working..."); return; }
        g_ownerKey  = llDetectedKey(0);
        g_ownerName = llGetDisplayName(g_ownerKey);
        pingHUD();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (channel == g_replyChannel && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);
            g_brandName  = llList2String(parts, 4);
            if (g_brandName == "") g_brandName = g_ownerName;
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            g_replyChannel = 0;
            // Open HUD channel listener so TC_INVENTORY_DATA / TC_REMOVE_OK /
            // TC_REMOVE_FAIL can be received
            if (g_listenHUD) { llListenRemove(g_listenHUD); g_listenHUD = 0; }
            g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");
            llSetTimerEvent(0.0);
            updateHoverText();
            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_INVENTORY_REQUEST|flower_raw|" + (string)llGetKey());
        }

        else if (channel == g_hudChannel && cmd == "TC_INVENTORY_DATA")
        {
            parseFlowerInventory(llList2String(parts, 1));
            showModeMenu();
        }

        else if (channel == g_hudChannel && cmd == "TC_REMOVE_OK")
        {
            llSetTimerEvent(0.0);
            finishCraft();
        }

        else if (channel == g_hudChannel && cmd == "TC_REMOVE_FAIL")
        {
            llSetTimerEvent(0.0);
            g_busy = FALSE;
            llRegionSayTo(g_ownerKey, 0, "Not enough flower.");
            resetTransaction();
        }

        // MODE SELECT
        else if (channel == DCHAN_MODE && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; return; }
            g_benchMode = llToLower(msg);
            if (msg == "Edibles")
                showEdibleMenu();
            else if (msg == "Press")
            {
                g_selectedItem = CONC_ID;
                g_costPerItem  = CONC_COST;
                showStrainMenu();
            }
        }

        // EDIBLE ITEM SELECT
        else if (channel == DCHAN_ITEM && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; return; }
            if (msg == "Back")   { showModeMenu(); return; }

            integer idx = llListFindList(EDIBLE_NAMES, [msg]);
            if (idx == -1) { showEdibleMenu(); return; }
            g_selectedItem = llList2String(EDIBLE_IDS, idx);
            g_costPerItem  = llList2Integer(EDIBLE_COSTS, idx);
            showStrainMenu();
        }

        // STRAIN SELECT
        else if (channel == DCHAN_STRAIN && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; return; }
            if (msg == "Back")
            {
                if (g_benchMode == "press") showModeMenu();
                else showEdibleMenu();
                return;
            }

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
                    jump found_strain;
                }
            }
            llRegionSayTo(g_ownerKey, 0, "Couldn't match strain. Try again.");
            showStrainMenu();
            return;
            @found_strain;
            showBatchMenu();
        }

        // BATCH SELECT
        else if (channel == DCHAN_BATCH && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; return; }
            if (msg == "Back")   { showStrainMenu(); return; }

            g_batchCount = (integer)msg;
            g_totalCost  = g_batchCount * g_costPerItem;
            if (g_totalCost > g_selectedFlowerQty)
            {
                llRegionSayTo(g_ownerKey, 0, "Not enough flower for that many.");
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
            if (msg == "Make It!") executeCraft();
        }
    }
}
