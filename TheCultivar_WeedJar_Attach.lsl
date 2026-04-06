// ================================================================
// THE CULTIVAR  -  Weed Jar Attach Script
// Version: 2.0
// Handles: Rez a smokeable near the smoker so it can self-attach
//          to the avatar's right hand via llAttachToAvatarTemp.
//          Falls back to inventory give in no-rez zones.
//
// SMOKEABLE ASSETS IN JAR INVENTORY (copy/transfer, no modify):
//   TC_Smoke_Joint_Reggie
//   TC_Smoke_Joint_Mids
//   TC_Smoke_Joint_Loud
//   TC_Smoke_Joint_Exotic
//   TC_Smoke_Blunt_Reggie
//   TC_Smoke_Blunt_Mids
//   TC_Smoke_Blunt_Loud
//   TC_Smoke_Blunt_Exotic
//
// ATTACH FLOW:
//   1. Main script sends ATTACH|smokerKey|strain|quality
//   2. This script selects the right asset
//   3. Rezzes a temp copy at smoker's position
//   4. The smokeable's own script self-attaches and handles everything
//   5. In no-rez zones, gives the item to inventory instead
// ================================================================

integer JCHAN_MAIN   = 2000;
integer JCHAN_ATTACH = 2100;

// Default smokeable type (can be expanded to blunts, pipes etc.)
string  g_smokeType = "Joint"; // Joint | Blunt

// ----------------------------------------------------------------
// Build the asset name based on type and quality
// ----------------------------------------------------------------
string buildAssetName(string smokeType, string quality)
{
    // Normalize quality to title case for asset name
    string q = llToUpper(llGetSubString(quality, 0, 0)) +
               llGetSubString(quality, 1, -1);
    return "TC_Smoke_" + smokeType + "_" + q;
}

// ----------------------------------------------------------------
// Rez the smokeable near the smoker — it will self-attach
// ----------------------------------------------------------------
rezSmokeable(key smoker, string strain, string quality)
{
    string assetName = buildAssetName(g_smokeType, quality);

    if (llGetInventoryType(assetName) != INVENTORY_OBJECT)
    {
        assetName = buildAssetName(g_smokeType, "reggie");
        if (llGetInventoryType(assetName) != INVENTORY_OBJECT)
        {
            llRegionSayTo(smoker, 0,
                "[Jar] Missing smokeable asset. Giving to inventory instead.");
            giveToInventory(smoker, quality);
            return;
        }
    }

    list   agentInfo = llGetObjectDetails(smoker, [OBJECT_POS]);
    vector smokerPos = llList2Vector(agentInfo, 0);

    if (smokerPos == ZERO_VECTOR)
    {
        giveToInventory(smoker, quality);
        return;
    }

    vector rezPos = smokerPos + <0.0, 0.0, 0.3>;
    llRezObject(assetName, rezPos, ZERO_VECTOR, ZERO_ROTATION, 0);
}

// ----------------------------------------------------------------
// Fall back to giving the item directly to inventory
// (no-rez zones, missing asset fallback)
// ----------------------------------------------------------------
giveToInventory(key smoker, string quality)
{
    string assetName = buildAssetName(g_smokeType, quality);
    if (llGetInventoryType(assetName) != INVENTORY_OBJECT)
        assetName = buildAssetName(g_smokeType, "reggie");

    if (llGetInventoryType(assetName) == INVENTORY_OBJECT)
    {
        llGiveInventory(smoker, assetName);
        llRegionSayTo(smoker, 0,
            "Smokeable added to your inventory " +
            "(can't auto-attach here  -  rez disabled in this area).");
    }
    else
    {
        llRegionSayTo(smoker, 0,
            "[Jar] Smokeable prop not found in jar inventory. " +
            "Place TC_Smoke_Joint_* or TC_Smoke_Blunt_* objects inside the jar.");
    }
}

// ================================================================
default
{
    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != JCHAN_ATTACH) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (cmd == "ATTACH")
        {
            // ATTACH|smokerKey|strain|quality
            key    smoker  = (key)llList2String(parts, 1);
            string strain  = llList2String(parts, 2);
            string quality = llList2String(parts, 3);

            // llAttachToAvatarTemp only works when the object is owned by the
            // smoker. Since the jar is owned by its owner, only the jar owner
            // can use the temp-attach path. For anyone else, give the asset
            // directly from the jar's inventory.
            if (smoker != llGetOwner())
                giveToInventory(smoker, quality);
            else
                rezSmokeable(smoker, strain, quality);
        }

        else if (cmd == "SET_SMOKE_TYPE")
        {
            g_smokeType = llList2String(parts, 1); // Joint, Blunt, Pipe
        }
    }
}
