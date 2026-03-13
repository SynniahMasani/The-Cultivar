// ============================================================
// TheCultivar_BreedingStation.lsl
// Version 1.0
// The Cultivar — Cannabis Roleplay Game
//
// World object allowing players to cross two seed strains from
// their HUD inventory into a new hybrid. Inherits averaged
// parent genetics with a 5% mutation chance. Exotic x Exotic
// crosses with high post-mutation potency yield Legendary
// phenotypes, announced region-wide.
//
// Hybrid names detected by Plant_Grow via " x " substring.
// Legendary names detected via "[LEGENDARY]" substring.
// Seeds go to HUD via TC_ADD_ITEM — no physical delivery.
//
// Communication pattern matches BaggingTable / RollingTable:
//   1. Touch -> pingHUD() broadcasts TC_PING on world channel
//   2. HUD_Comms replies TC_REGISTER on random reply channel
//   3. Station requests TC_INVENTORY_REQUEST|seed_raw
//   4. HUD replies TC_INVENTORY_DATA|rawSeeds
//   5. Player selects Parent 1, Parent 2, confirms
//   6. TC_REMOVE_ITEM x2 (sequential, wait for TC_REMOVE_OK)
//   7. calculateHybrid() -> TC_ADD_ITEM to HUD
// ============================================================

integer TC_OBJECT_PING_CHAN = -111222333;

integer DCHAN_PARENT1 = -88001;
integer DCHAN_PARENT2 = -88002;
integer DCHAN_CONFIRM = -88003;
integer DCHAN_NAME    = -88004;

integer SEED_STRIDE = 4;
integer GENE_STRIDE = 5;

// Stride-5 gene table: strainName, potency, yieldMod*100, speedMod*100, rarity
list STRAIN_GENES = [
    "Schwag",              10,  80, 100,  1,
    "Ditch Weed",          12,  70, 100,  1,
    "Brown Frown",         11,  70, 100,  1,
    "Blue Dream",          35, 100, 100,  3,
    "Green Crack",         38, 105, 110,  3,
    "Gorilla Glue",        40, 100,  95,  3,
    "Sour Diesel",         42, 105, 105,  4,
    "OG Kush",             65, 110, 100,  6,
    "Wedding Cake",        68, 115, 100,  6,
    "Zkittlez",            64, 110, 105,  6,
    "Gelato",              70, 115,  95,  7,
    "Runtz",               85, 120, 100,  8,
    "Biscotti",            88, 125,  95,  9,
    "Jealousy",            84, 120, 100,  8,
    "Lemon Cherry Gelato", 92, 130,  90, 10
];

// ── Global state ─────────────────────────────────────────
key     g_ownerKey;
string  g_ownerName;
string  g_brandName;
integer g_hudChannel;
integer g_registered;
integer g_busy;

// Stride-4 seed list parsed from HUD: strainName, quality, qty, packager
list    g_availableSeeds;

// Current transaction
string  g_parent1Name;
string  g_parent1Quality;
string  g_parent1Packager;
string  g_parent2Name;
string  g_parent2Quality;
string  g_parent2Packager;
integer g_removeStep;
string  g_hybridName;
integer g_isLegendary;
integer g_isMutation;

// Calculated child genes (stored for reference)
integer g_childPotency;
integer g_childYieldMod;
integer g_childSpeedMod;
integer g_childRarity;

// Listeners
integer g_registerChannel;
integer g_listenRegister;
integer g_listenParent1;
integer g_listenParent2;
integer g_listenConfirm;
integer g_listenName;
integer g_listenHUD;

// ─────────────────────────────────────────────────────────
// Helper: close all active listeners
// ─────────────────────────────────────────────────────────
closeAllListens()
{
    if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
    if (g_listenParent1)  { llListenRemove(g_listenParent1);  g_listenParent1  = 0; }
    if (g_listenParent2)  { llListenRemove(g_listenParent2);  g_listenParent2  = 0; }
    if (g_listenConfirm)  { llListenRemove(g_listenConfirm);  g_listenConfirm  = 0; }
    if (g_listenName)     { llListenRemove(g_listenName);      g_listenName     = 0; }
    if (g_listenHUD)      { llListenRemove(g_listenHUD);       g_listenHUD      = 0; }
    g_registerChannel = 0;
}

// ─────────────────────────────────────────────────────────
// Helper: reset per-transaction state
// ─────────────────────────────────────────────────────────
resetTransaction()
{
    g_parent1Name     = "";
    g_parent1Quality  = "";
    g_parent1Packager = "";
    g_parent2Name     = "";
    g_parent2Quality  = "";
    g_parent2Packager = "";
    g_removeStep      = 0;
    g_hybridName      = "";
    g_isLegendary     = FALSE;
    g_isMutation      = FALSE;
    g_childPotency    = 0;
    g_childYieldMod   = 0;
    g_childSpeedMod   = 0;
    g_childRarity     = 0;
    g_busy            = FALSE;
}

// ─────────────────────────────────────────────────────────
// Helper: quality display tag
// ─────────────────────────────────────────────────────────
string getQualityLabel(string quality)
{
    if (quality == "reggie") return "[R]";
    if (quality == "mids")   return "[M]";
    if (quality == "loud")   return "[L]";
    if (quality == "exotic") return "[E]";
    return "[?]";
}

// ─────────────────────────────────────────────────────────
// Helper: look up strain genes by name
// Returns [potency, yieldMod*100, speedMod*100, rarity]
// Falls back to mid-tier defaults for unknown / hybrid strains
// ─────────────────────────────────────────────────────────
list getStrainGenes(string strainName)
{
    integer count = llGetListLength(STRAIN_GENES);
    integer i;
    for (i = 0; i < count; i += GENE_STRIDE)
    {
        if (llList2String(STRAIN_GENES, i) == strainName)
        {
            return [
                llList2Integer(STRAIN_GENES, i + 1),
                llList2Integer(STRAIN_GENES, i + 2),
                llList2Integer(STRAIN_GENES, i + 3),
                llList2Integer(STRAIN_GENES, i + 4)
            ];
        }
    }
    return [50, 100, 100, 5];
}

// ─────────────────────────────────────────────────────────
// Helper: broadcast TC_PING and open registration listener
// ─────────────────────────────────────────────────────────
pingHUD()
{
    g_registerChannel = (integer)((llFrand(1000000.0) + 1000000.0) * -1.0);
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(g_registerChannel, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|breeding_station|" +
        (string)g_registerChannel);
    llSetTimerEvent(10.0);
}

// ─────────────────────────────────────────────────────────
// Helper: fill g_availableSeeds from TC_INVENTORY_DATA string
// Keeps only seed_raw items; stride 4: name, quality, qty, packager
// ─────────────────────────────────────────────────────────
parseInventoryData(string raw)
{
    g_availableSeeds = [];
    list slots = llParseString2List(raw, ["^"], []);
    integer count = llGetListLength(slots);
    integer i;
    for (i = 0; i < count; i++)
    {
        list fields = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(fields) >= 5)
        {
            string itemType   = llList2String(fields, 0);
            string strainName = llList2String(fields, 1);
            string quality    = llList2String(fields, 2);
            integer qty       = (integer)llList2String(fields, 3);
            string packager   = llList2String(fields, 4);
            if (itemType == "seed_raw")
                g_availableSeeds += [strainName, quality, qty, packager];
        }
    }
}

// ─────────────────────────────────────────────────────────
// Helper: list of unique strain names in g_availableSeeds
// ─────────────────────────────────────────────────────────
list getUniqueStrains()
{
    list unique = [];
    integer count = llGetListLength(g_availableSeeds);
    integer i;
    for (i = 0; i < count; i += SEED_STRIDE)
    {
        string name = llList2String(g_availableSeeds, i);
        if (llListFindList(unique, (list)name) == -1)
            unique += [name];
    }
    return unique;
}

// ─────────────────────────────────────────────────────────
// Helper: quality string for first seed entry of a strain
// ─────────────────────────────────────────────────────────
string getSeedQuality(string strainName)
{
    integer count = llGetListLength(g_availableSeeds);
    integer i;
    for (i = 0; i < count; i += SEED_STRIDE)
    {
        if (llList2String(g_availableSeeds, i) == strainName)
            return llList2String(g_availableSeeds, i + 1);
    }
    return "mids";
}

// ─────────────────────────────────────────────────────────
// Helper: total quantity across all entries for a strain
// ─────────────────────────────────────────────────────────
integer getSeedQty(string strainName)
{
    integer count = llGetListLength(g_availableSeeds);
    integer i;
    integer total = 0;
    for (i = 0; i < count; i += SEED_STRIDE)
    {
        if (llList2String(g_availableSeeds, i) == strainName)
            total += llList2Integer(g_availableSeeds, i + 2);
    }
    return total;
}

// ─────────────────────────────────────────────────────────
// Helper: packager for first matching seed entry
// ─────────────────────────────────────────────────────────
string getSeedPackager(string strainName)
{
    integer count = llGetListLength(g_availableSeeds);
    integer i;
    for (i = 0; i < count; i += SEED_STRIDE)
    {
        if (llList2String(g_availableSeeds, i) == strainName)
            return llList2String(g_availableSeeds, i + 3);
    }
    return "";
}

// ─────────────────────────────────────────────────────────
// Helper: resolve full strain name from 11-char dialog button
// Skips excludeName (pass "" to skip nothing)
// ─────────────────────────────────────────────────────────
string resolveStrainName(string btnText, string excludeName)
{
    list unique = getUniqueStrains();
    integer count = llGetListLength(unique);
    integer i;
    for (i = 0; i < count; i++)
    {
        string name = llList2String(unique, i);
        if (name != excludeName)
        {
            if (llGetSubString(name, 0, 10) == btnText)
                return name;
        }
    }
    return btnText;
}

// ─────────────────────────────────────────────────────────
// Menu: Parent 1 selection
// ─────────────────────────────────────────────────────────
showParent1Menu()
{
    if (g_listenParent1) llListenRemove(g_listenParent1);
    g_listenParent1 = llListen(DCHAN_PARENT1, "", g_ownerKey, "");

    list unique = getUniqueStrains();
    integer count = llGetListLength(unique);

    if (count < 2)
    {
        llRegionSayTo(g_ownerKey, 0,
            "You need at least 2 different strains to breed. Grow more plants first.");
        g_busy = FALSE;
        return;
    }

    string msg = "=== BREEDING STATION ===\nSelect Parent 1:\n(This seed will be consumed)\n";
    list buttons = [];
    integer shown = 0;
    integer i;
    for (i = 0; i < count && shown < 9; i++)
    {
        string name = llList2String(unique, i);
        string qual = getSeedQuality(name);
        integer qty = getSeedQty(name);
        msg += getQualityLabel(qual) + " " + name + " — " + (string)qty + " available\n";
        buttons += [llGetSubString(name, 0, 10)];
        shown++;
    }
    buttons += ["Cancel"];

    if (llStringLength(msg) > 480)
        msg = llGetSubString(msg, 0, 479);

    llSetTimerEvent(30.0);
    llDialog(g_ownerKey, msg, buttons, DCHAN_PARENT1);
}

// ─────────────────────────────────────────────────────────
// Menu: Parent 2 selection (excludes parent 1)
// ─────────────────────────────────────────────────────────
showParent2Menu()
{
    if (g_listenParent2) llListenRemove(g_listenParent2);
    g_listenParent2 = llListen(DCHAN_PARENT2, "", g_ownerKey, "");

    list unique = getUniqueStrains();
    integer count = llGetListLength(unique);

    string msg = "=== BREEDING STATION ===\nParent 1: " + g_parent1Name +
                 "\nSelect Parent 2:\n(This seed will also be consumed)\n";
    list buttons = [];
    integer shown = 0;
    integer i;
    for (i = 0; i < count && shown < 9; i++)
    {
        string name = llList2String(unique, i);
        if (name != g_parent1Name)
        {
            string qual = getSeedQuality(name);
            integer qty = getSeedQty(name);
            msg += getQualityLabel(qual) + " " + name + " — " + (string)qty + " available\n";
            buttons += [llGetSubString(name, 0, 10)];
            shown++;
        }
    }
    buttons += ["Cancel"];

    if (llStringLength(msg) > 480)
        msg = llGetSubString(msg, 0, 479);

    llSetTimerEvent(30.0);
    llDialog(g_ownerKey, msg, buttons, DCHAN_PARENT2);
}

// ─────────────────────────────────────────────────────────
// Menu: Breeding confirmation
// ─────────────────────────────────────────────────────────
showBreedConfirmMenu()
{
    if (g_listenConfirm) llListenRemove(g_listenConfirm);
    g_listenConfirm = llListen(DCHAN_CONFIRM, "", g_ownerKey, "");

    string q1 = getQualityLabel(g_parent1Quality);
    string q2 = getQualityLabel(g_parent2Quality);

    string msg = "=== CONFIRM BREEDING ===\n" +
                 "Parent 1: " + q1 + " " + g_parent1Name + "\n" +
                 "Parent 2: " + q2 + " " + g_parent2Name + "\n" +
                 "Result: " + g_parent1Name + " x " + g_parent2Name + " hybrid seed\n" +
                 "WARNING: Both seeds will be consumed.\n" +
                 "Success is guaranteed but legendary\n" +
                 "phenotypes are extremely rare.\n" +
                 "Proceed?";

    if (llStringLength(msg) > 480)
        msg = llGetSubString(msg, 0, 479);

    llSetTimerEvent(30.0);
    llDialog(g_ownerKey, msg, ["Breed!", "Cancel"], DCHAN_CONFIRM);
}

// ─────────────────────────────────────────────────────────
// Send TC_REMOVE_ITEM for parent 1 seed
// ─────────────────────────────────────────────────────────
removeParent1()
{
    g_removeStep = 1;
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_REMOVE_ITEM|seed_raw|" + g_parent1Name + "|" +
        g_parent1Quality + "|1|" + g_parent1Packager);
    llSetTimerEvent(15.0);
}

// ─────────────────────────────────────────────────────────
// Send TC_REMOVE_ITEM for parent 2 seed
// ─────────────────────────────────────────────────────────
removeParent2()
{
    g_removeStep = 2;
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_REMOVE_ITEM|seed_raw|" + g_parent2Name + "|" +
        g_parent2Quality + "|1|" + g_parent2Packager);
}

// ─────────────────────────────────────────────────────────
// Calculate hybrid genetics, mutation, and legendary check
// Sets g_hybridName, g_isLegendary, g_isMutation, child genes
// ─────────────────────────────────────────────────────────
calculateHybrid()
{
    list genes1 = getStrainGenes(g_parent1Name);
    list genes2 = getStrainGenes(g_parent2Name);

    integer p1Potency = llList2Integer(genes1, 0);
    integer p1Yield   = llList2Integer(genes1, 1);
    integer p1Speed   = llList2Integer(genes1, 2);
    integer p1Rarity  = llList2Integer(genes1, 3);

    integer p2Potency = llList2Integer(genes2, 0);
    integer p2Yield   = llList2Integer(genes2, 1);
    integer p2Speed   = llList2Integer(genes2, 2);
    integer p2Rarity  = llList2Integer(genes2, 3);

    g_childPotency  = (p1Potency + p2Potency) / 2;
    g_childYieldMod = (p1Yield   + p2Yield)   / 2;
    g_childSpeedMod = (p1Speed   + p2Speed)   / 2;
    g_childRarity   = (p1Rarity  + p2Rarity)  / 2;

    g_isMutation = FALSE;
    if (llFrand(1.0) < 0.05)
    {
        g_isMutation = TRUE;
        integer boost = (integer)(llFrand(20.0)) + 1;
        if (llFrand(1.0) < 0.5)
            g_childPotency += boost;
        else
            g_childPotency -= boost;
        if (g_childPotency < 1)   g_childPotency = 1;
        if (g_childPotency > 100) g_childPotency = 100;
    }

    g_isLegendary = FALSE;
    if (g_isMutation &&
        p1Rarity >= 8 && p2Rarity >= 8 &&
        g_childPotency >= 90)
    {
        g_isLegendary = TRUE;
    }

    g_hybridName = g_parent1Name + " x " + g_parent2Name;
}

// ─────────────────────────────────────────────────────────
// Add the hybrid seed to the HUD, fire particles and announce
// ─────────────────────────────────────────────────────────
finalizeBreeding()
{
    string seedQuality;
    if (g_isLegendary)
        seedQuality = "exotic";
    else
        seedQuality = "loud";

    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|seed_raw|" + g_hybridName + "|" +
        seedQuality + "|1|" + g_brandName);

    vector burstColor;
    if (g_isLegendary)
        burstColor = <0.8, 0.3, 1.0>;
    else
        burstColor = <0.4, 0.9, 0.4>;

    llParticleSystem([
        PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK | PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
        PSYS_PART_START_COLOR,     burstColor,
        PSYS_PART_END_COLOR,       <1.0, 1.0, 1.0>,
        PSYS_PART_START_ALPHA,     1.0,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.06, 0.06, 0.0>,
        PSYS_PART_END_SCALE,       <0.02, 0.02, 0.0>,
        PSYS_PART_MAX_AGE,         2.5,
        PSYS_SRC_BURST_RATE,       0.05,
        PSYS_SRC_BURST_PART_COUNT, 20,
        PSYS_SRC_MAX_AGE,          0.5
    ]);
    llPlaySound("breed_success", 0.8);

    if (g_isLegendary)
    {
        llRegionSay(0,
            "⚡ LEGENDARY PHENOTYPE! " + g_ownerName +
            " just bred a legendary " + g_hybridName +
            "! One of a kind — this strain can never be replicated.");
        llRegionSayTo(g_ownerKey, 0,
            "🌿 LEGENDARY bred: " + g_hybridName +
            " — Grows 15% faster, +20% yield. Exotic quality guaranteed.");
    }
    else
    {
        llRegionSayTo(g_ownerKey, 0,
            "🌿 Bred: " + g_hybridName +
            " seed added to your inventory!\nHybrid grows 8% faster with increased yields.");
    }

    resetTransaction();
    llSetTimerEvent(3.0);
}

// ─────────────────────────────────────────────────────────
default
{
    state_entry()
    {
        g_registered      = FALSE;
        g_busy            = FALSE;
        g_registerChannel = 0;
        g_hudChannel      = 0;
        closeAllListens();
        resetTransaction();
        llSetText("THE CULTIVAR\nBreeding Station\nTouch to breed strains",
            <0.6, 0.4, 0.9>, 1.0);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
            llResetScript();
    }

    timer()
    {
        llSetTimerEvent(0.0);

        if (!g_registered)
        {
            closeAllListens();
            g_busy = FALSE;
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't connect to HUD. Make sure your Cultivar HUD is worn.");
            return;
        }

        // Clear any particle burst from finalizeBreeding
        llParticleSystem([]);

        // Dialog or remove timeout — abort transaction
        if (g_busy)
        {
            closeAllListens();
            resetTransaction();
        }
    }

    touch_start(integer num)
    {
        key toucher = llDetectedKey(0);
        if (toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0,
                "This breeding station belongs to " + llKey2Name(llGetOwner()) + ".");
            return;
        }
        if (g_busy)
        {
            llRegionSayTo(toucher, 0, "Breeding station is busy. Please wait.");
            return;
        }
        g_busy       = TRUE;
        g_ownerKey   = toucher;
        g_registered = FALSE;
        pingHUD();
    }

    listen(integer channel, string name, key id, string message)
    {
        list parts = llParseString2List(message, ["|"], []);
        string cmd = llList2String(parts, 0);

        // ── HUD registration reply ──────────────────────────
        if (channel == g_registerChannel && g_registerChannel != 0)
        {
            if (cmd != "TC_REGISTER") return;

            llListenRemove(g_listenRegister);
            g_listenRegister  = 0;
            g_registerChannel = 0;
            llSetTimerEvent(0.0);

            g_ownerKey   = (key)llList2String(parts, 1);
            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);
            g_brandName  = llList2String(parts, 4);
            g_registered = TRUE;

            llSetText("THE CULTIVAR\nBreeding Station\nTouch to cross your seeds",
                <0.7, 0.5, 1.0>, 1.0);

            if (g_listenHUD) llListenRemove(g_listenHUD);
            g_listenHUD = llListen(g_hudChannel, "", g_ownerKey, "");

            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_INVENTORY_REQUEST|seed_raw|" + (string)llGetKey());
            llSetTimerEvent(10.0);
            return;
        }

        // ── HUD private channel: inventory + remove responses ─
        if (channel == g_hudChannel && g_hudChannel != 0)
        {
            if (cmd == "TC_INVENTORY_DATA")
            {
                llSetTimerEvent(0.0);
                parseInventoryData(llList2String(parts, 1));

                list unique = getUniqueStrains();
                if (llGetListLength(unique) < 2)
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "You need at least 2 different strains to breed. Grow more plants first.");
                    g_busy = FALSE;
                    return;
                }
                showParent1Menu();
                return;
            }

            if (cmd == "TC_REMOVE_OK")
            {
                if (g_removeStep == 1)
                {
                    removeParent2();
                }
                else if (g_removeStep == 2)
                {
                    g_removeStep = 0;
                    llSetTimerEvent(0.0);
                    calculateHybrid();

                    if (g_isLegendary)
                    {
                        if (g_listenName) llListenRemove(g_listenName);
                        g_listenName = llListen(DCHAN_NAME, "", g_ownerKey, "");
                        llTextBox(g_ownerKey,
                            "LEGENDARY PHENOTYPE!\n\n" +
                            "This cross produced a one-of-a-kind legendary strain.\n" +
                            "Give it a name (max 32 chars).\n" +
                            "It will be saved as: [YourName] [LEGENDARY]\n\n" +
                            "Enter your strain name:",
                            DCHAN_NAME);
                        llSetTimerEvent(30.0);
                    }
                    else
                    {
                        finalizeBreeding();
                    }
                }
                return;
            }

            if (cmd == "TC_REMOVE_FAIL")
            {
                llSetTimerEvent(0.0);
                if (g_removeStep == 1)
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "Seed not found in inventory. Try again.");
                    resetTransaction();
                }
                else if (g_removeStep == 2)
                {
                    llRegionSayTo(g_ownerKey, 0,
                        "Could not remove second seed. Parent 1 was already consumed — contact support.");
                    resetTransaction();
                }
                return;
            }
            return;
        }

        // ── Parent 1 strain selection ───────────────────────
        if (channel == DCHAN_PARENT1)
        {
            llListenRemove(g_listenParent1);
            g_listenParent1 = 0;
            llSetTimerEvent(0.0);

            if (message == "Cancel")
            {
                g_busy = FALSE;
                return;
            }

            string fullName   = resolveStrainName(message, "");
            g_parent1Name     = fullName;
            g_parent1Quality  = getSeedQuality(fullName);
            g_parent1Packager = getSeedPackager(fullName);
            showParent2Menu();
            return;
        }

        // ── Parent 2 strain selection ───────────────────────
        if (channel == DCHAN_PARENT2)
        {
            llListenRemove(g_listenParent2);
            g_listenParent2 = 0;
            llSetTimerEvent(0.0);

            if (message == "Cancel")
            {
                g_busy = FALSE;
                return;
            }

            string fullName = resolveStrainName(message, g_parent1Name);
            if (fullName == g_parent1Name)
            {
                llRegionSayTo(g_ownerKey, 0,
                    "Cannot breed a strain with itself. Select two different strains.");
                showParent1Menu();
                return;
            }

            g_parent2Name     = fullName;
            g_parent2Quality  = getSeedQuality(fullName);
            g_parent2Packager = getSeedPackager(fullName);
            showBreedConfirmMenu();
            return;
        }

        // ── Breeding confirmation ───────────────────────────
        if (channel == DCHAN_CONFIRM)
        {
            llListenRemove(g_listenConfirm);
            g_listenConfirm = 0;
            llSetTimerEvent(0.0);

            if (message == "Cancel")
            {
                g_busy = FALSE;
                return;
            }
            if (message == "Breed!")
                removeParent1();
            return;
        }

        // ── Legendary strain naming via llTextBox ───────────
        if (channel == DCHAN_NAME)
        {
            llListenRemove(g_listenName);
            g_listenName = 0;
            llSetTimerEvent(0.0);

            string playerName = llStringTrim(message, STRING_TRIM);
            playerName = llGetSubString(playerName, 0, 31);
            playerName = llDumpList2String(
                llParseString2List(playerName, ["|", "~", "^"], []), "");

            if (playerName == "")
                playerName = g_parent1Name + " x " + g_parent2Name;

            g_hybridName = playerName + " [LEGENDARY]";
            finalizeBreeding();
            return;
        }
    }
}
