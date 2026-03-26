// ================================================================
// THE CULTIVAR  -  Seed Pack Script
// Version: 2.0
// Lives inside: all 19 TC seed pack objects
//   - 15 strain-locked Synful Sprouts Co. packets (PACK_MODE = "strain")
//   - 4 gacha mystery packs (PACK_MODE = "gacha")
//
// SETUP — change these three constants only:
//
//   Strain-locked example:
//     string PACK_MODE   = "strain";
//     string PACK_STRAIN = "Lemon Cherry Gelato";
//     string PACK_TYPE   = "";
//
//   Gacha example:
//     string PACK_MODE   = "gacha";
//     string PACK_STRAIN = "";
//     string PACK_TYPE   = "Hustler's Pack";
//
// STRAIN MODE:  Always gives PACK_STRAIN. Tier auto-looked up.
//               Rolls 1-3 seeds.
// GACHA MODE:   Strain AND tier both randomly rolled per seed.
//               Seed count range set by PACK_TYPE tier.
//
// QUALITY ODDS (cumulative thresholds for llFrand(100.0)):
//   Sampler's  : reggie<70  mids<95  loud<100  exotic=0%
//   Beginner's : reggie<40  mids<80  loud<98   exotic=2%
//   Hustler's  : reggie<20  mids<55  loud<85   exotic=15%
//   Plug's     : reggie<5   mids<25  loud<65   exotic=35%
//
// HUD DELIVERY:
//   TC_ADD_ITEM|seed|<strainName>|<qualityTier>|1
//   Sent on TC_HUD_CHANNEL per seed.
// ================================================================

// ---- Variant constants: change these per object ----
string PACK_MODE   = "gacha";
string PACK_STRAIN = "";
string PACK_TYPE   = "Hustler's Pack";

// ---- Depletion guard ----
integer g_used = FALSE;

// ---- Channel constants ----
string  TC_ADD_ITEM    = "TC_ADD_ITEM";

// ---- Derive private HUD channel from owner UUID (matches HUD_Comms) ----
integer deriveHUDChannel(key ownerID)
{
    string h = llGetSubString((string)ownerID, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

// ---- Strain master table ----
// Stride 3: strainName, tierString, tierIndex
list STRAIN_DATA = [
    "Zone Weed",           "reggie", 0,
    "Schwag",              "reggie", 0,
    "Brown Frown",         "reggie", 0,
    "Blue Dream",          "mids",   1,
    "OG Kush",             "mids",   1,
    "Gorilla Glue",        "mids",   1,
    "Sour Diesel",         "mids",   1,
    "Green Crack",         "loud",   2,
    "Wedding Cake",        "loud",   2,
    "Zkittlez",            "loud",   2,
    "Gelato",              "loud",   2,
    "Runtz",               "exotic", 3,
    "Biscotti",            "exotic", 3,
    "Jealousy",            "exotic", 3,
    "Lemon Cherry Gelato", "exotic", 3
];
integer STRAIN_STRIDE = 3;

// ---- Strain pools per tier (for gacha random selection) ----
list REGGIE_POOL = ["Zone Weed", "Schwag", "Brown Frown"];
list MIDS_POOL   = ["Blue Dream", "OG Kush", "Gorilla Glue", "Sour Diesel"];
list LOUD_POOL   = ["Green Crack", "Wedding Cake", "Zkittlez", "Gelato"];
list EXOTIC_POOL = ["Runtz", "Biscotti", "Jealousy", "Lemon Cherry Gelato"];

// ----------------------------------------------------------------
// Look up tier string for a strain name.
// Returns "reggie" as safe fallback if not found.
// ----------------------------------------------------------------
string getTierFromStrain(string strainName)
{
    integer i;
    for (i = 0; i < llGetListLength(STRAIN_DATA); i += STRAIN_STRIDE)
    {
        if (llList2String(STRAIN_DATA, i) == strainName)
            return llList2String(STRAIN_DATA, i + 1);
    }
    return "reggie";
}

// ----------------------------------------------------------------
// Roll quality tier using cumulative thresholds.
// ----------------------------------------------------------------
string rollQuality(integer reggieMax, integer midsMax, integer loudMax)
{
    float roll = llFrand(100.0);
    if (roll < (float)reggieMax) return "reggie";
    if (roll < (float)midsMax)   return "mids";
    if (roll < (float)loudMax)   return "loud";
    return "exotic";
}

// ----------------------------------------------------------------
// Pick a random strain from the quality-matched pool.
// ----------------------------------------------------------------
string randomStrainForTier(string tier)
{
    list pool = REGGIE_POOL;
    if (tier == "mids")   pool = MIDS_POOL;
    if (tier == "loud")   pool = LOUD_POOL;
    if (tier == "exotic") pool = EXOTIC_POOL;
    integer idx = (integer)llFrand((float)llGetListLength(pool));
    return llList2String(pool, idx);
}

// ----------------------------------------------------------------
// Display label for a quality tier.
// ----------------------------------------------------------------
string qualLabel(string tier)
{
    if (tier == "mids")   return "Mids";
    if (tier == "loud")   return "Loud";
    if (tier == "exotic") return "Exotic";
    return "Reggie";
}

// ----------------------------------------------------------------
// Return pack config: [minSeeds, maxSeeds, reggieMax, midsMax, loudMax]
// ----------------------------------------------------------------
list getPackConfig(string packType)
{
    if (packType == "Sampler's Pack")  return [1, 3,  70, 95,  100];
    if (packType == "Beginner's Pack") return [2, 5,  40, 80,  98];
    if (packType == "Hustler's Pack")  return [5, 10, 20, 55,  85];
    if (packType == "Plug's Special")  return [8, 15,  5, 25,  65];
    return [1, 3, 70, 95, 100];
}

// ----------------------------------------------------------------
// Hover text color for a quality tier.
// ----------------------------------------------------------------
vector tierColor(string tier)
{
    if (tier == "mids")   return <0.3, 0.7, 0.3>;
    if (tier == "loud")   return <0.9, 0.6, 0.1>;
    if (tier == "exotic") return <0.8, 0.2, 0.9>;
    return <0.5, 0.5, 0.5>;
}

// ----------------------------------------------------------------
// Hover text color for a gacha pack type.
// ----------------------------------------------------------------
vector packColor(string packType)
{
    if (packType == "Sampler's Pack")  return <0.6, 0.6, 0.6>;
    if (packType == "Beginner's Pack") return <0.3, 0.7, 0.3>;
    if (packType == "Hustler's Pack")  return <0.9, 0.6, 0.1>;
    return <0.8, 0.2, 0.9>;
}

// ----------------------------------------------------------------
// Set hover text based on current mode and constants.
// ----------------------------------------------------------------
setHoverText()
{
    if (PACK_MODE == "strain")
    {
        string tier = getTierFromStrain(PACK_STRAIN);
        llSetText(PACK_STRAIN + "\nSynful Sprouts Co.\n1-3 Seeds\nTouch to open",
            tierColor(tier), 1.0);
    }
    else
    {
        list    cfg      = getPackConfig(PACK_TYPE);
        integer minSeeds = llList2Integer(cfg, 0);
        integer maxSeeds = llList2Integer(cfg, 1);
        llSetText(PACK_TYPE + "\n" +
            (string)minSeeds + "-" + (string)maxSeeds + " Mystery Seeds\nTouch to open",
            packColor(PACK_TYPE), 1.0);
    }
}

// ================================================================
default
{
    state_entry()
    {
        // Non-creator who re-rezzed an already-used pack sees it as empty.
        if (llLinksetDataRead("pack_used") == "1")
        {
            llSetText("EMPTY\nAll seeds have been claimed.\nPurchase a new pack to get more seeds.",
                <0.35, 0.35, 0.35>, 0.6);
            return;
        }
        setHoverText();
    }

    on_rez(integer start_param)
    {
        // Original creator re-rezzes → clear used flag so packs can be
        // distributed fresh. Everyone else keeps the empty/used state.
        if (llGetOwner() == llGetCreator())
            llLinksetDataDelete("pack_used");
        llResetScript();
    }

    touch_start(integer nd)
    {
        if (g_used) return;

        if (llDetectedKey(0) != llGetOwner())
        {
            llSay(0, "This pack belongs to someone else.");
            return;
        }

        g_used = TRUE;
        // Persist the used state so a non-creator re-rezzing a copy-enabled
        // pack cannot claim seeds again.
        if (llGetOwner() != llGetCreator())
            llLinksetDataWrite("pack_used", "1");

        integer seedCount   = 0;
        string  displayName = "";
        string  lockedTier  = "";
        integer reggieMax   = 0;
        integer midsMax     = 0;
        integer loudMax     = 0;

        if (PACK_MODE == "strain")
        {
            seedCount   = 1 + (integer)llFrand(3.0);
            lockedTier  = getTierFromStrain(PACK_STRAIN);
            displayName = PACK_STRAIN;
        }
        else
        {
            list    cfg      = getPackConfig(PACK_TYPE);
            integer minSeeds = llList2Integer(cfg, 0);
            integer maxSeeds = llList2Integer(cfg, 1);
            reggieMax        = llList2Integer(cfg, 2);
            midsMax          = llList2Integer(cfg, 3);
            loudMax          = llList2Integer(cfg, 4);
            seedCount        = minSeeds +
                (integer)llFrand((float)(maxSeeds - minSeeds + 1));
            displayName      = PACK_TYPE;
        }

        // Opening announcement
        llSay(0, "==========================");
        llSay(0, " " + displayName + " - Opening...");
        llSay(0, "==========================");

        // Reveal each seed one at a time
        integer i;
        for (i = 1; i <= seedCount; i++)
        {
            string qualTier   = "";
            string strainName = "";

            if (PACK_MODE == "strain")
            {
                strainName = PACK_STRAIN;
                qualTier   = lockedTier;
            }
            else
            {
                qualTier   = rollQuality(reggieMax, midsMax, loudMax);
                strainName = randomStrainForTier(qualTier);
            }

            llSay(0, "Seed #" + (string)i + " - " +
                qualLabel(qualTier) + " - " + strainName);

            llRegionSayTo(llGetOwner(), deriveHUDChannel(llGetOwner()),
                TC_ADD_ITEM + "|seed_raw|" + strainName + "|" + qualTier + "|1");

            llSleep(0.5);
        }

        llSay(0, (string)seedCount +
            " seeds added to your HUD inventory. Happy growing!");
        llSetText("EMPTY\nAll seeds delivered.\nNothing left to see here, bestie.\nGo grow something.",
            <0.35, 0.35, 0.35>, 0.6);
        llSleep(2.0);
        llDie();
    }
}
