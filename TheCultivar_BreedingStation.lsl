// ================================================================
// THE CULTIVAR  -  Breeding Station Script
// Version: 2.0
// Lives inside: TC Breeding Station world object
//
// WHAT IT DOES:
//   Player touches the station, selects two seeds from their HUD
//   inventory as parents, and the station breeds them into one
//   hybrid seed added back to the HUD. Both parents are consumed.
//
// GENETICS:
//   Child stats = average of both parents (potency, yield, speed,
//   rarity). 5% chance of mutation (potency ±1-20). Legendary
//   requires: mutation AND both parents rarity >= 8 AND potency >= 90.
//
// HUD REGISTRATION FLOW:
//   1. Touch -> pingHUD() -> TC_PING on TC_OBJECT_PING_CHAN
//   2. HUD_Comms responds: TC_REGISTER|ownerKey|hudChannel|name|brand
//   3. Station requests seed inventory: TC_INVENTORY_REQUEST|seed_raw
//   4. HUD responds: TC_INVENTORY_DATA|rawData
//   5. Player picks Parent 1, Parent 2, confirms
//   6. TC_REMOVE_ITEM x2 (sequential, waits for TC_REMOVE_OK each)
//   7. calculateHybrid() -> TC_ADD_ITEM hybrid seed to HUD
//
// DIALOG CHANNELS:
//   DCHAN_PARENT1 = -88001
//   DCHAN_PARENT2 = -88002
//   DCHAN_CONFIRM = -88003
//   DCHAN_NAME    = -88004  (llTextBox for legendary naming)
//
// HYBRID NAME FORMAT:
//   Standard  : "Parent1 x Parent2"
//   Legendary : "PlayerChosenName [LEGENDARY]"
//   Plant_Grow detects hybrid via " x " and legendary via "[LEGENDARY]"
// ================================================================

// ---- Channel constants ----
integer TC_OBJECT_PING_CHAN = -111222333;
integer HOVER_FADE_SECS = 30;

// ---- Dialog channels ----
integer DCHAN_PARENT1 = -88001;
integer DCHAN_PARENT2 = -88002;
integer DCHAN_CONFIRM = -88003;
integer DCHAN_NAME    = -88004;

// ---- Genetics table ----
// Stride 5: strainName, potency, yieldMod*100, speedMod*100, rarity
list GENE_DATA = [
    "Zone Weed",           10,  80, 100, 1,
    "Schwag",              10,  80, 100, 1,
    "Brown Frown",         11,  70, 100, 1,
    "Blue Dream",          35, 100, 100, 3,
    "OG Kush",             38, 105, 110, 3,
    "Gorilla Glue",        40, 100,  95, 3,
    "Sour Diesel",         42, 105, 105, 4,
    "Green Crack",         65, 110, 100, 6,
    "Wedding Cake",        68, 115, 100, 6,
    "Zkittlez",            64, 110, 105, 6,
    "Gelato",              70, 115,  95, 7,
    "Runtz",               85, 120, 100, 8,
    "Biscotti",            88, 125,  95, 9,
    "Jealousy",            84, 120, 100, 8,
    "Lemon Cherry Gelato", 92, 130,  90, 10
];
integer GENE_STRIDE = 5;

// ---- Global state ----
key     g_ownerKey       = NULL_KEY;
integer g_hudChannel     = 0;
string  g_ownerName      = "";
integer g_replyChannel   = 0;
integer g_listenReply    = 0;
integer g_listenMenu     = 0;
integer g_removeStep     = 0;

// Seed list: stride 3 — strainName, quality, qty
list    g_seedSlots      = [];

string  g_parent1Strain  = "";
string  g_parent1Quality = "";
string  g_parent2Strain  = "";
string  g_parent2Quality = "";
string  g_hybridName     = "";
string  g_hybridQuality  = "";
integer g_isLegendary    = FALSE;
integer g_isMutation     = FALSE;

// Listen handles
integer g_listenParent1  = 0;
integer g_listenParent2  = 0;
integer g_listenConfirm  = 0;
integer g_listenName     = 0;
integer g_listenHUD      = 0;

// ----------------------------------------------------------------
// Look up parent genes from GENE_DATA.
// Returns [potency, yieldMod, speedMod, rarity].
// Unknown / hybrid strains return default mid-tier values.
// ----------------------------------------------------------------
list getGenes(string strainName)
{
    integer i;
    for (i = 0; i < llGetListLength(GENE_DATA); i += GENE_STRIDE)
    {
        if (llList2String(GENE_DATA, i) == strainName)
        {
            return [
                llList2Integer(GENE_DATA, i + 1),
                llList2Integer(GENE_DATA, i + 2),
                llList2Integer(GENE_DATA, i + 3),
                llList2Integer(GENE_DATA, i + 4)
            ];
        }
    }
    return [50, 100, 100, 5];
}

// ----------------------------------------------------------------
// Parse TC_INVENTORY_DATA payload into g_seedSlots (stride 3).
// Only keeps seed_raw items. Consolidates duplicate strain+quality
// entries by summing qty.
// ----------------------------------------------------------------
parseSeedInventory(string rawData)
{
    g_seedSlots = [];
    if (rawData == "") return;
    list slots = llParseString2List(rawData, ["^"], []);
    integer i;
    for (i = 0; i < llGetListLength(slots); i++)
    {
        list fields = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(fields) >= 5 &&
            llList2String(fields, 0) == "seed_raw")
        {
            string  strainName = llList2String(fields, 1);
            string  quality    = llList2String(fields, 2);
            integer qty        = (integer)llList2String(fields, 3);

            // Find existing entry for this strain+quality to consolidate
            integer found = -1;
            integer j;
            for (j = 0; j < llGetListLength(g_seedSlots); j += 3)
            {
                if (llList2String(g_seedSlots, j)     == strainName &&
                    llList2String(g_seedSlots, j + 1) == quality)
                    found = j;
            }

            if (found >= 0)
            {
                integer existing = llList2Integer(g_seedSlots, found + 2);
                g_seedSlots = llListReplaceList(g_seedSlots,
                    [strainName, quality, existing + qty], found, found + 2);
            }
            else
            {
                g_seedSlots += [strainName, quality, qty];
            }
        }
    }
}

// ----------------------------------------------------------------
// Return up to 9 dialog button strings from g_seedSlots.
// Skips any entry where strainName == excludeStrain.
// Always appends "Cancel".
// ----------------------------------------------------------------
list buildSeedButtons(string excludeStrain)
{
    list    buttons = [];
    integer count   = 0;
    integer i;
    for (i = 0; i < llGetListLength(g_seedSlots) && count < 9; i += 3)
    {
        string strainName = llList2String(g_seedSlots, i);
        if (excludeStrain == "" || strainName != excludeStrain)
        {
            buttons += [llGetSubString(strainName, 0, 10)];
            count++;
        }
    }
    buttons += ["Cancel"];
    return buttons;
}

// ----------------------------------------------------------------
// Find the full strain name in g_seedSlots whose first 11 chars
// match buttonLabel. Skips excludeStrain.
// Returns buttonLabel unchanged if no match found.
// ----------------------------------------------------------------
string resolveStrainFromButton(string buttonLabel, string excludeStrain)
{
    integer i;
    for (i = 0; i < llGetListLength(g_seedSlots); i += 3)
    {
        string strainName = llList2String(g_seedSlots, i);
        if (strainName != excludeStrain &&
            llGetSubString(strainName, 0, 10) == buttonLabel)
            return strainName;
    }
    return buttonLabel;
}

// ----------------------------------------------------------------
// Look up quality string for a strain in g_seedSlots.
// ----------------------------------------------------------------
string getSeedQuality(string strainName)
{
    integer i;
    for (i = 0; i < llGetListLength(g_seedSlots); i += 3)
    {
        if (llList2String(g_seedSlots, i) == strainName)
            return llList2String(g_seedSlots, i + 1);
    }
    return "mids";
}

// ----------------------------------------------------------------
// Quality tier display label.
// ----------------------------------------------------------------
string qualLabel(string tier)
{
    if (tier == "mids")   return "Mids";
    if (tier == "loud")   return "Loud";
    if (tier == "exotic") return "Exotic";
    return "Reggie";
}

// ----------------------------------------------------------------
// Remove all active listens.
// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenReply)   { llListenRemove(g_listenReply);   g_listenReply   = 0; }
    if (g_listenHUD)     { llListenRemove(g_listenHUD);     g_listenHUD     = 0; }
    if (g_listenParent1) { llListenRemove(g_listenParent1); g_listenParent1 = 0; }
    if (g_listenParent2) { llListenRemove(g_listenParent2); g_listenParent2 = 0; }
    if (g_listenConfirm) { llListenRemove(g_listenConfirm); g_listenConfirm = 0; }
    if (g_listenName)    { llListenRemove(g_listenName);    g_listenName    = 0; }
}

// ----------------------------------------------------------------
// Reset all state to defaults and restore idle hover text.
// ----------------------------------------------------------------
resetStation()
{
    closeAllListens();
    g_ownerKey       = NULL_KEY;
    g_hudChannel     = 0;
    g_ownerName      = "";
    g_replyChannel   = 0;
    g_removeStep     = 0;
    g_seedSlots      = [];
    g_parent1Strain  = "";
    g_parent1Quality = "";
    g_parent2Strain  = "";
    g_parent2Quality = "";
    g_hybridName     = "";
    g_hybridQuality  = "";
    g_isLegendary    = FALSE;
    g_isMutation     = FALSE;
    llSetTimerEvent(HOVER_FADE_SECS);
    llSetText("Breeding Station\nTouch to breed two seeds\ninto a hybrid strain",
        <0.3, 0.8, 0.3>, 1.0);
}

// ----------------------------------------------------------------
// Broadcast TC_PING and open timed registration listen.
// ----------------------------------------------------------------
pingHUD()
{
    g_replyChannel = (integer)(llFrand(1000000.0) + 1000000.0) * -1;
    if (g_listenReply) llListenRemove(g_listenReply);
    g_listenReply = llListen(g_replyChannel, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|breeding_station|" +
        (string)g_replyChannel);
    llSetTimerEvent(15.0);
    llSetText("Breeding Station\nSearching for HUD...", <0.9, 0.6, 0.1>, 1.0);
}

// ----------------------------------------------------------------
// MENU: Parent 1 selection
// ----------------------------------------------------------------
showParent1Menu()
{
    if (g_listenParent1) llListenRemove(g_listenParent1);
    g_listenParent1 = llListen(DCHAN_PARENT1, "", g_ownerKey, "");

    list buttons = buildSeedButtons("");

    string msg = "=== BREEDING STATION ===\n"
               + "Select Parent 1:\n"
               + "(This seed will be consumed)\n\n";

    integer i;
    integer len = llGetListLength(g_seedSlots);
    for (i = 0; i < len; i += 3)
    {
        msg += llList2String(g_seedSlots, i) + " x"
             + llList2String(g_seedSlots, i + 2) + "\n";
    }

    if (llStringLength(msg) > 480)
        msg = llGetSubString(msg, 0, 479);

    llSetTimerEvent(30.0);
    llDialog(g_ownerKey, msg, buttons, DCHAN_PARENT1);
}

// ----------------------------------------------------------------
// MENU: Parent 2 selection (excludes Parent 1)
// ----------------------------------------------------------------
showParent2Menu()
{
    if (g_listenParent2) llListenRemove(g_listenParent2);
    g_listenParent2 = llListen(DCHAN_PARENT2, "", g_ownerKey, "");

    list buttons = buildSeedButtons(g_parent1Strain);

    string msg = "=== BREEDING STATION ===\n"
               + "Parent 1: " + g_parent1Strain + "\n"
               + "Select Parent 2:\n"
               + "(This seed will also be consumed)\n\n";

    integer i;
    integer len = llGetListLength(g_seedSlots);
    for (i = 0; i < len; i += 3)
    {
        string strainName = llList2String(g_seedSlots, i);
        if (strainName != g_parent1Strain)
            msg += strainName + " x" + llList2String(g_seedSlots, i + 2) + "\n";
    }

    if (llStringLength(msg) > 480)
        msg = llGetSubString(msg, 0, 479);

    llSetTimerEvent(30.0);
    llDialog(g_ownerKey, msg, buttons, DCHAN_PARENT2);
}

// ----------------------------------------------------------------
// MENU: Breeding confirmation
// ----------------------------------------------------------------
showConfirmMenu()
{
    if (g_listenConfirm) llListenRemove(g_listenConfirm);
    g_listenConfirm = llListen(DCHAN_CONFIRM, "", g_ownerKey, "");

    string msg = "=== CONFIRM BREEDING ===\n"
               + "Parent 1: " + qualLabel(g_parent1Quality) + " " + g_parent1Strain + "\n"
               + "Parent 2: " + qualLabel(g_parent2Quality) + " " + g_parent2Strain + "\n"
               + "Result: "   + g_parent1Strain + " x " + g_parent2Strain + "\n"
               + "WARNING: Both seeds will be consumed.\n"
               + "Proceed?";

    if (llStringLength(msg) > 480)
        msg = llGetSubString(msg, 0, 479);

    llSetTimerEvent(30.0);
    llDialog(g_ownerKey, msg, ["Breed!", "Cancel"], DCHAN_CONFIRM);
}

// ----------------------------------------------------------------
// MENU: Legendary phenotype naming (llTextBox)
// ----------------------------------------------------------------
showNameMenu()
{
    if (g_listenName) llListenRemove(g_listenName);
    g_listenName = llListen(DCHAN_NAME, "", g_ownerKey, "");
    llTextBox(g_ownerKey,
        "LEGENDARY PHENOTYPE DISCOVERED!\n\n"
      + "Name your creation.\n"
      + "It will be saved as: [Your Name] [LEGENDARY]\n\n"
      + "Enter a name (no special characters):",
        DCHAN_NAME);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Calculate hybrid genetics from the two selected parents.
// Sets g_hybridName, g_hybridQuality, g_isLegendary, g_isMutation.
// ----------------------------------------------------------------
calculateHybrid()
{
    list genes1 = getGenes(g_parent1Strain);
    list genes2 = getGenes(g_parent2Strain);

    integer p1Potency  = llList2Integer(genes1, 0);
    integer p1YieldMod = llList2Integer(genes1, 1);
    integer p1SpeedMod = llList2Integer(genes1, 2);
    integer p1Rarity   = llList2Integer(genes1, 3);

    integer p2Potency  = llList2Integer(genes2, 0);
    integer p2YieldMod = llList2Integer(genes2, 1);
    integer p2SpeedMod = llList2Integer(genes2, 2);
    integer p2Rarity   = llList2Integer(genes2, 3);

    integer childPotency  = (p1Potency  + p2Potency)  / 2;
    integer childYieldMod = (p1YieldMod + p2YieldMod) / 2;
    integer childSpeedMod = (p1SpeedMod + p2SpeedMod) / 2;
    integer childRarity   = (p1Rarity   + p2Rarity)   / 2;

    g_isMutation = FALSE;
    if (llFrand(1.0) < 0.05)
    {
        g_isMutation = TRUE;
        integer boost = (integer)(llFrand(20.0)) + 1;
        if (llFrand(1.0) < 0.5)
            childPotency += boost;
        else
            childPotency -= boost;
        if (childPotency < 1)   childPotency = 1;
        if (childPotency > 100) childPotency = 100;
    }

    g_isLegendary = FALSE;
    if (g_isMutation && p1Rarity >= 8 && p2Rarity >= 8 && childPotency >= 90)
        g_isLegendary = TRUE;

    if (g_isLegendary)
        g_hybridQuality = "exotic";
    else
        g_hybridQuality = "loud";

    g_hybridName = g_parent1Strain + " x " + g_parent2Strain;
}

// ----------------------------------------------------------------
// Send hybrid seed to HUD and notify player. Reset when done.
// ----------------------------------------------------------------
deliverHybrid()
{
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|seed_raw|" + g_hybridName + "|"
        + g_hybridQuality + "|1|BreedingStation");

    if (g_isLegendary)
    {
        llRegionSayTo(g_ownerKey, 0,
            "LEGENDARY PHENOTYPE: " + g_hybridName +
            " has been added to your inventory!");
    }
    else if (g_isMutation)
    {
        llRegionSayTo(g_ownerKey, 0,
            "MUTATION DETECTED! " + g_hybridName +
            " [" + g_hybridQuality + "] added to your inventory.");
    }
    else
    {
        llRegionSayTo(g_ownerKey, 0,
            g_hybridName +
            " [" + g_hybridQuality + "] added to your inventory.");
    }
    resetStation();
}

// ================================================================
default
{
    state_entry()
    {
        // Full reset ensures no dirty state survives a script reload or update push.
        resetStation();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    timer()
    {
        // Idle fade: station is idle — fade hover text and stop timer
        if (g_ownerKey == NULL_KEY && g_listenReply == 0)
        {
            llSetText("Breeding Station\nTouch to breed two seeds\ninto a hybrid strain",
                <0.3, 0.8, 0.3>, 0.0);
            llSetTimerEvent(0.0);
            return;
        }

        llSetTimerEvent(0.0);

        if (g_listenReply != 0)
        {
            // Registration phase timed out — HUD never responded.
            // g_ownerKey is the toucher (set before pingHUD), so we can
            // still notify them directly before clearing state.
            if (g_listenReply) llListenRemove(g_listenReply);
            g_listenReply  = 0;
            g_replyChannel = 0;
            key noHudOwner = g_ownerKey;
            g_ownerKey     = NULL_KEY;
            llSetText("Breeding Station\nTouch to breed two seeds\ninto a hybrid strain",
                <0.3, 0.8, 0.3>, 1.0);
            llRegionSayTo(noHudOwner, 0,
                "No HUD detected. Make sure your Cultivar HUD is attached and try again.");
            llSetTimerEvent(HOVER_FADE_SECS);
        }
        else
        {
            key timedOutOwner = g_ownerKey;
            if (g_hybridName != "" && g_removeStep == 0)
            {
                // Seeds were already consumed and hybrid calculated but the
                // naming dialog timed out.  Deliver with the default generated
                // name so the player doesn't lose their seeds for no result.
                if (g_isLegendary)
                    g_hybridName = g_hybridName + " [LEGENDARY]";
                llRegionSayTo(timedOutOwner, 0,
                    "Name entry timed out — delivering as '" + g_hybridName + "'.");
                deliverHybrid();
            }
            else
            {
                // Menu or remove timed out before seeds were consumed
                resetStation();
                llRegionSayTo(timedOutOwner, 0, "Menu timed out. Touch to try again.");
            }
        }
    }

    touch_start(integer nd)
    {
        llSetText("Breeding Station\nTouch to breed two seeds\ninto a hybrid strain",
            <0.3, 0.8, 0.3>, 1.0);
        key toucher = llDetectedKey(0);

        if (g_ownerKey != NULL_KEY)
        {
            if (toucher == g_ownerKey && g_removeStep == 0)
            {
                // Owner re-touching while waiting on HUD or a menu (stale/pending).
                // Reset and let them start fresh.
                resetStation();
                // fall through to start a new session
            }
            else if (toucher == g_ownerKey)
            {
                // Seeds are actively being removed — cannot interrupt.
                llSay(0, "Still processing your previous request...");
                return;
            }
            else
            {
                llSay(0, "This station is currently in use.");
                return;
            }
        }

        if (toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0,
                "This breeding station belongs to " + llGetDisplayName(llGetOwner()) + ".");
            return;
        }

        g_ownerKey  = toucher;
        g_ownerName = llGetDisplayName(toucher);
        pingHUD();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- HUD registration response ----
        if (channel == g_replyChannel && g_replyChannel != 0 && cmd == "TC_REGISTER")
        {
            // Every HUD in the region listens on TC_OBJECT_PING_CHAN and will
            // respond to our ping.  Only accept the registration that belongs
            // to the player who actually touched this station.
            key registeredOwner = (key)llList2String(parts, 1);
            if (registeredOwner == NULL_KEY || registeredOwner != g_ownerKey) return;

            if (g_listenReply) llListenRemove(g_listenReply);
            g_listenReply  = 0;
            g_replyChannel = 0;
            llSetTimerEvent(0.0);

            // g_ownerKey already correct; just capture HUD channel and name
            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);

            if (g_listenHUD) llListenRemove(g_listenHUD);
            g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");

            llSetText("Breeding Station\nIn use by " + g_ownerName,
                <0.8, 0.2, 0.9>, 1.0);

            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_INVENTORY_REQUEST|seed_raw|" + (string)llGetKey());
            // 30 seconds: HUD_Comms now handles TC_INVENTORY_REQUEST synchronously,
            // but give extra headroom for slow regions / script queue backup.
            llSetTimerEvent(30.0);
            return;
        }

        // ---- HUD private channel messages ----
        if (channel == g_hudChannel && g_hudChannel != 0)
        {
            if (cmd == "TC_INVENTORY_DATA")
            {
                if (g_ownerKey == NULL_KEY) return; // stale response
                llSetTimerEvent(0.0);
                string dbgRaw = llList2String(parts, 1);
                llRegionSayTo(g_ownerKey, 0, "[TC_Breed] rawData=" + (string)llStringLength(dbgRaw) + "B");
                parseSeedInventory(dbgRaw);

                // Count distinct strain names
                list uniqueStrains = [];
                integer ui;
                for (ui = 0; ui < llGetListLength(g_seedSlots); ui += 3)
                {
                    string sn = llList2String(g_seedSlots, ui);
                    if (llListFindList(uniqueStrains, (list)sn) == -1)
                        uniqueStrains += [sn];
                }

                if (llGetListLength(uniqueStrains) < 2)
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "You need at least 2 different seed strains to breed.");
                    resetStation();
                    return;
                }
                showParent1Menu();
                return;
            }

            if (cmd == "TC_REMOVE_OK")
            {
                if (g_ownerKey == NULL_KEY || g_removeStep == 0) return; // stale response
                if (g_removeStep == 1)
                {
                    g_removeStep = 2;
                    llRegionSayTo(g_ownerKey, g_hudChannel,
                        "TC_REMOVE_ITEM|seed_raw|" + g_parent2Strain + "|"
                        + g_parent2Quality + "|1|");
                }
                else if (g_removeStep == 2)
                {
                    g_removeStep = 0;
                    llSetTimerEvent(0.0);
                    calculateHybrid();
                    if (g_isLegendary)
                        showNameMenu();
                    else
                        deliverHybrid();
                }
                return;
            }

            if (cmd == "TC_REMOVE_FAIL")
            {
                if (g_ownerKey == NULL_KEY) return; // stale response
                llSetTimerEvent(0.0);
                if (g_removeStep == 2)
                {
                    // Parent 1 was already consumed successfully.  Return it so
                    // the player doesn't lose a seed when the second removal fails.
                    llRegionSayTo(g_ownerKey, g_hudChannel,
                        "TC_ADD_ITEM|seed_raw|" + g_parent1Strain + "|"
                        + g_parent1Quality + "|1|");
                    llRegionSayTo(g_ownerKey, 0,
                        "Breeding failed  -  could not remove " + g_parent2Strain
                        + " from inventory. Your " + g_parent1Strain
                        + " seed has been returned. Please try again.");
                }
                else
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "Breeding failed  -  could not remove seeds from inventory. Please try again.");
                }
                g_removeStep = 0;
                resetStation();
                return;
            }
            return;
        }

        // ---- Parent 1 selection ----
        if (channel == DCHAN_PARENT1 && id == g_ownerKey)
        {
            if (g_listenParent1) llListenRemove(g_listenParent1);
            g_listenParent1 = 0;
            llSetTimerEvent(0.0);

            if (msg == "Cancel")
            {
                resetStation();
                return;
            }

            g_parent1Strain  = resolveStrainFromButton(msg, "");
            g_parent1Quality = getSeedQuality(g_parent1Strain);
            showParent2Menu();
            return;
        }

        // ---- Parent 2 selection ----
        if (channel == DCHAN_PARENT2 && id == g_ownerKey)
        {
            if (g_listenParent2) llListenRemove(g_listenParent2);
            g_listenParent2 = 0;
            llSetTimerEvent(0.0);

            if (msg == "Cancel")
            {
                resetStation();
                return;
            }

            g_parent2Strain  = resolveStrainFromButton(msg, g_parent1Strain);
            g_parent2Quality = getSeedQuality(g_parent2Strain);
            showConfirmMenu();
            return;
        }

        // ---- Confirm breeding ----
        if (channel == DCHAN_CONFIRM && id == g_ownerKey)
        {
            if (g_listenConfirm) llListenRemove(g_listenConfirm);
            g_listenConfirm = 0;
            llSetTimerEvent(0.0);

            if (msg == "Cancel")
            {
                resetStation();
                return;
            }
            if (msg == "Breed!")
            {
                g_removeStep = 1;
                llRegionSayTo(g_ownerKey, g_hudChannel,
                    "TC_REMOVE_ITEM|seed_raw|" + g_parent1Strain + "|"
                    + g_parent1Quality + "|1|");
                llSetTimerEvent(15.0);
            }
            return;
        }

        // ---- Legendary strain naming ----
        if (channel == DCHAN_NAME && id == g_ownerKey)
        {
            if (g_listenName) llListenRemove(g_listenName);
            g_listenName = 0;
            llSetTimerEvent(0.0);

            string playerName = llStringTrim(msg, STRING_TRIM);
            playerName = llDumpList2String(
                llParseString2List(playerName, ["|", "~", "^"], []), "");
            playerName = llGetSubString(playerName, 0, 31);

            if (playerName == "")
                playerName = g_parent1Strain + " x " + g_parent2Strain;

            g_hybridName = playerName + " [LEGENDARY]";
            deliverHybrid();
            return;
        }
    }
}
