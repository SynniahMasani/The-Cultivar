// ================================================================
// THE CULTIVAR  -  Seed Pack Script
// Version: 1.0
// Lives inside: TC Seed Pack objects (Sampler's, Beginner's,
//               Hustler's, or Plug's Special)
//
// WHAT IT DOES:
//   Single-use rezzable pack. Owner touches it to reveal seeds
//   one at a time in local chat. Each seed is sent to the HUD
//   as TC_ADD_ITEM. The pack then deletes itself.
//
// SETUP:
//   Set PACK_TYPE to one of:
//     "Sampler's Pack"   -- 1-3 seeds, mostly reggie
//     "Beginner's Pack"  -- 2-5 seeds, balanced
//     "Hustler's Pack"   -- 5-10 seeds, good odds
//     "Plug's Special"   -- 8-15 seeds, exotic-heavy
//
// QUALITY ODDS (cumulative thresholds):
//   Sampler's  : 70% reggie  25% mids   5% loud   0% exotic
//   Beginner's : 40% reggie  40% mids  18% loud   2% exotic
//   Hustler's  : 20% reggie  35% mids  30% loud  15% exotic
//   Plug's     :  5% reggie  20% mids  40% loud  35% exotic
//
// HUD DELIVERY:
//   TC_ADD_ITEM|seed|<strainName>|<quality>|1
//   Sent on private HUD channel derived from owner UUID.
//   HUD_Comms routes TC_ADD_ITEM to HUD_Inventory automatically.
// ================================================================

string PACK_TYPE = "Hustler's Pack";

integer g_hudChannel = 0;

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
// Return pack config: [minSeeds, maxSeeds, reggieMax, midsMax, loudMax]
// Cumulative upper bounds for rollQuality():
//   roll < reggieMax  -> reggie
//   roll < midsMax    -> mids
//   roll < loudMax    -> loud
//   roll >= loudMax   -> exotic
// ----------------------------------------------------------------
list getPackConfig(string packType)
{
    if (packType == "Sampler's Pack")
        return [1, 3, 70, 95, 100];
    if (packType == "Beginner's Pack")
        return [2, 5, 40, 80, 98];
    if (packType == "Hustler's Pack")
        return [5, 10, 20, 55, 85];
    return [8, 15, 5, 25, 65];
}

// ----------------------------------------------------------------
// Roll quality using cumulative thresholds from pack config
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
// Pick a random strain from the quality-matched pool
// ----------------------------------------------------------------
string randomStrain(string quality)
{
    list pool;
    if (quality == "reggie")
        pool = ["Zone Weed", "Schwag", "Brown Frown"];
    else if (quality == "mids")
        pool = ["Blue Dream", "OG Kush", "Gorilla Glue", "Sour Diesel"];
    else if (quality == "loud")
        pool = ["Green Crack", "Wedding Cake", "Zkittlez", "Gelato"];
    else
        pool = ["Runtz", "Biscotti", "Jealousy", "Lemon Cherry Gelato"];
    return llList2String(pool, (integer)llFrand((float)llGetListLength(pool)));
}

// ----------------------------------------------------------------
// Quality display label
// ----------------------------------------------------------------
string qualLabel(string quality)
{
    if (quality == "reggie") return "Reggie";
    if (quality == "mids")   return "Mids";
    if (quality == "loud")   return "Loud";
    return "Exotic";
}

// ----------------------------------------------------------------
// Hover text color per pack tier
// ----------------------------------------------------------------
vector packColor(string packType)
{
    if (packType == "Sampler's Pack")  return <0.6, 0.6, 0.6>;
    if (packType == "Beginner's Pack") return <0.3, 0.7, 0.3>;
    if (packType == "Hustler's Pack")  return <0.9, 0.6, 0.1>;
    return <0.8, 0.2, 0.9>;
}

// ----------------------------------------------------------------
// Seed count range label for hover text
// ----------------------------------------------------------------
string seedRangeText(string packType)
{
    if (packType == "Sampler's Pack")  return "1-3 Random Seeds";
    if (packType == "Beginner's Pack") return "2-5 Random Seeds";
    if (packType == "Hustler's Pack")  return "5-10 Random Seeds";
    return "8-15 Random Seeds";
}

// ================================================================
default
{
    state_entry()
    {
        g_hudChannel = deriveHUDChannel(llGetOwner());
        llSetText(PACK_TYPE + "\n" + seedRangeText(PACK_TYPE) +
                  "\nTouch to open", packColor(PACK_TYPE), 1.0);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    touch_start(integer nd)
    {
        if (llDetectedKey(0) != llGetOwner())
        {
            llSay(0, "This pack belongs to someone else.");
            return;
        }

        list    config    = getPackConfig(PACK_TYPE);
        integer minSeeds  = llList2Integer(config, 0);
        integer maxSeeds  = llList2Integer(config, 1);
        integer reggieMax = llList2Integer(config, 2);
        integer midsMax   = llList2Integer(config, 3);
        integer loudMax   = llList2Integer(config, 4);

        integer seedCount = minSeeds +
            (integer)llFrand((float)(maxSeeds - minSeeds + 1));

        // Opening announcement
        llSay(0, "==========================");
        llSay(0, " " + PACK_TYPE + " - Opening...");
        llSay(0, "==========================");

        // Reveal each seed one at a time and deliver to HUD
        integer i;
        for (i = 1; i <= seedCount; i++)
        {
            string quality = rollQuality(reggieMax, midsMax, loudMax);
            string strain  = randomStrain(quality);

            llSay(0, "Seed #" + (string)i + " - " +
                qualLabel(quality) + " [" + strain + "]");

            llRegionSayTo(llGetOwner(), g_hudChannel,
                "TC_ADD_ITEM|seed|" + strain + "|" + quality + "|1");

            llSleep(0.5);
        }

        llSay(0, (string)seedCount +
            " seeds added to your HUD inventory. Happy growing!");
        llSleep(0.5);
        llDie();
    }
}
