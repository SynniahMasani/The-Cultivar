// ================================================================
// THE CULTIVAR  -  Gacha Seed Pack Script
// Version: 1.0
// Lives inside: any TC seed pack object (e.g. "Biscotti Pack")
//
// WHAT IT DOES:
//   Players purchase a seed pack object and rez or use it.
//   On touch, the script rolls random odds based on the pack type
//   stored in the object description, determines a quality tier,
//   sends TC_ADD_ITEM to the player's HUD, announces the result,
//   plays a quality-colored particle burst, then calls llDie().
//
// OBJECT SETUP:
//   Name        : Strain name, e.g. "Biscotti" or "Biscotti Pack"
//                 " Pack" suffix is stripped automatically.
//   Description : Pack type — mystery | reggie | mids | loud | exotic
//                 Defaults to "mystery" if blank.
//
// QUALITY ODDS BY PACK TYPE:
//   mystery : reggie 30%  mids 35%  loud 25%  exotic 10%
//   reggie  : reggie 70%  mids 25%  loud  5%  exotic  0%
//   mids    : reggie 10%  mids 65%  loud 22%  exotic  3%
//   loud    : reggie  0%  mids 15%  loud 70%  exotic 15%
//   exotic  : reggie  0%  mids  5%  loud 35%  exotic 60%
//
// HUD COMMUNICATION:
//   Derives the private HUD channel from the owner UUID using the
//   same derivation function used by all TC world objects.
//   Sends: TC_ADD_ITEM|seed_raw|<strain>|<quality>|1|SeedPack
//
// CHANNEL:
//   No ping/register flow — seed pack is a single-use object that
//   derives the channel directly and fires once, then dies.
// ================================================================

key     g_ownerKey   = NULL_KEY;
integer g_hudChannel = 0;
string  g_strainName = "";
string  g_packType   = "mystery";

// ----------------------------------------------------------------
// Derive the private HUD channel from the owner UUID.
// Matches the derivation used by HUD_Comms and all world objects.
// ----------------------------------------------------------------
integer deriveHUDChannel(key ownerID)
{
    string hexSub = llGetSubString((string)ownerID, 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}

// ----------------------------------------------------------------
// Return a display color for each quality tier.
// ----------------------------------------------------------------
vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0, 0.85, 0.2>;
    if (quality == "loud")   return <0.2, 0.85, 0.3>;
    if (quality == "exotic") return <0.7, 0.3,  1.0>;
    return <0.55, 0.45, 0.3>;
}

// ----------------------------------------------------------------
// Roll quality based on pack type odds table.
// Returns "reggie", "mids", "loud", or "exotic".
// ----------------------------------------------------------------
string rollQuality(string packType)
{
    float roll = llFrand(100.0);

    if (packType == "reggie")
    {
        if (roll < 70.0)       return "reggie";
        else if (roll < 95.0)  return "mids";
        else                   return "loud";
    }
    else if (packType == "mids")
    {
        if (roll < 10.0)       return "reggie";
        else if (roll < 75.0)  return "mids";
        else if (roll < 97.0)  return "loud";
        else                   return "exotic";
    }
    else if (packType == "loud")
    {
        if (roll < 15.0)       return "mids";
        else if (roll < 85.0)  return "loud";
        else                   return "exotic";
    }
    else if (packType == "exotic")
    {
        if (roll < 5.0)        return "mids";
        else if (roll < 40.0)  return "loud";
        else                   return "exotic";
    }
    else
    {
        // mystery (default)
        if (roll < 30.0)       return "reggie";
        else if (roll < 65.0)  return "mids";
        else if (roll < 90.0)  return "loud";
        else                   return "exotic";
    }
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey   = llGetOwner();
        g_hudChannel = deriveHUDChannel(g_ownerKey);

        // Strip " Pack" suffix from object name if present
        string rawName = llGetObjectName();
        integer packIdx = llSubStringIndex(rawName, " Pack");
        if (packIdx != -1 && packIdx == llStringLength(rawName) - 5)
            g_strainName = llGetSubString(rawName, 0, packIdx - 1);
        else
            g_strainName = rawName;

        // Read pack type from description; default to mystery
        g_packType = llGetObjectDesc();
        if (g_packType == "") g_packType = "mystery";

        llSetText("Seed Pack: " + g_strainName + "\nTouch to open!", qualColor("loud"), 1.0);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    touch_start(integer nd)
    {
        // Only the owner can open their own seed pack
        if (llDetectedKey(0) != g_ownerKey) return;

        string quality = rollQuality(g_packType);

        // Send seed to HUD inventory
        llRegionSayTo(g_ownerKey, g_hudChannel,
            "TC_ADD_ITEM|seed_raw|" + g_strainName + "|" + quality + "|1|SeedPack");

        // Private result message to opener
        llRegionSayTo(g_ownerKey, 0,
            "Opened: " + g_strainName + " seed  -  " + quality + " phenotype!");

        // Public broadcast only for exotic pulls
        if (quality == "exotic")
            llRegionSay(0,
                llKey2Name(g_ownerKey) +
                " cracked an exotic " + g_strainName + " phenotype!");

        // Quality-colored particle burst before dying
        llParticleSystem([
            PSYS_PART_FLAGS,           PSYS_PART_EMISSIVE_MASK,
            PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
            PSYS_PART_START_COLOR,     qualColor(quality),
            PSYS_PART_START_ALPHA,     1.0,
            PSYS_PART_END_ALPHA,       0.0,
            PSYS_PART_START_SCALE,     <0.05, 0.05, 0.0>,
            PSYS_PART_END_SCALE,       <0.02, 0.02, 0.0>,
            PSYS_PART_MAX_AGE,         1.5,
            PSYS_SRC_BURST_RATE,       0.05,
            PSYS_SRC_BURST_PART_COUNT, 12,
            PSYS_SRC_BURST_SPEED_MIN,  0.1,
            PSYS_SRC_BURST_SPEED_MAX,  0.3,
            PSYS_SRC_MAX_AGE,          0.4
        ]);
        llSleep(2.0);
        llDie();
    }
}
