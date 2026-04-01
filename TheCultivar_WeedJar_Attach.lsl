// ================================================================
// THE CULTIVAR  -  Weed Jar Attach Script
// Version: 1.0
// Handles: Temp-attach system for auto-attaching a smokeable
//          to the avatar's right hand when they take from the jar.
//          No inventory clutter  -  the item is temp-attached and
//          auto-detaches after the smoke animation runs.
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
// TEMP ATTACH FLOW:
//   1. Main script sends ATTACH|smokerKey|strain|quality
//   2. This script selects the right asset
//   3. Rezzes a temp copy at smoker's position
//   4. Temp object attaches itself to the smoker's right hand
//   5. After ATTACH_DURATION seconds it detaches and dies
//   6. In no-rez zones, gives the item to inventory instead
//
// ATTACH DURATION: 120 seconds (2 minutes per smoke session)
// ================================================================

integer JCHAN_MAIN   = 2000;
integer JCHAN_ATTACH = 2100;

// How long the smokeable stays attached (seconds)
integer ATTACH_DURATION = 120;

// Default smokeable type (can be expanded to blunts, pipes etc.)
string  g_smokeType = "Joint"; // Joint | Blunt

// Track active attachments: [smokerKey, tempChan, listenHandle, expireTime, strain, quality]
// Stride 6  -  strain/quality stored so listen handler can send TC_ATTACH_TO on confirmation
list    g_attachments;
integer ATTACH_STRIDE = 6;

// Cleanup timer interval
float   CLEANUP_INTERVAL = 15.0;

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
// Rez the smokeable near the smoker and instruct it to attach
// ----------------------------------------------------------------
rezSmokeable(key smoker, string strain, string quality)
{
    string assetName = buildAssetName(g_smokeType, quality);

    // Check asset exists
    if (llGetInventoryType(assetName) != INVENTORY_OBJECT)
    {
        // Try the reggie version as fallback
        assetName = buildAssetName(g_smokeType, "reggie");
        if (llGetInventoryType(assetName) != INVENTORY_OBJECT)
        {
            llRegionSayTo(smoker, 0,
                "[Jar] Missing smokeable asset. Giving to inventory instead.");
            giveToInventory(smoker, quality);
            return;
        }
    }

    // Get smoker position to rez near them
    list   agentInfo = llGetObjectDetails(smoker,
                       [OBJECT_POS, OBJECT_ROT]);
    vector smokerPos = llList2Vector(agentInfo, 0);

    if (smokerPos == ZERO_VECTOR)
    {
        // Couldn't get position  -  fall back to inventory give
        giveToInventory(smoker, quality);
        return;
    }

    // Rez slightly above smoker (will attach immediately via script)
    vector rezPos = smokerPos + <0.0, 0.0, 0.3>;

    // Encode smoker key and duration in start_param
    // We can only pass an integer  -  use a temp listener channel instead
    integer tempChan   = (integer)(llFrand(2000000.0) + 1000000.0) * -1;
    integer tempListen = llListen(tempChan, "", NULL_KEY, "");

    // Rez the smokeable  -  its script will listen for attach instructions
    llRezObject(assetName, rezPos, ZERO_VECTOR, ZERO_ROTATION, tempChan);

    // DO NOT send TC_ATTACH_TO here  -  the smokeable's state_entry() hasn't
    // run yet so its listener isn't open. We send TC_ATTACH_TO in listen()
    // after we receive TC_ATTACH_CONFIRMED from the smokeable.

    // Track this attachment  -  store strain/quality so the listen handler
    // can build the TC_ATTACH_TO message after confirmation.
    integer expireTime = llGetUnixTime() + ATTACH_DURATION + 5;
    g_attachments += [smoker, tempChan, tempListen, expireTime, strain, quality];
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
}

// ----------------------------------------------------------------
// Clean up expired attachment tracking entries
// Also removes their listen handles so we don't leak listeners
// ----------------------------------------------------------------
cleanupExpired()
{
    integer now = llGetUnixTime();
    list    fresh;
    integer i;
    for (i = 0; i < llGetListLength(g_attachments); i += ATTACH_STRIDE)
    {
        integer expireTime = llList2Integer(g_attachments, i + 3);
        if (now < expireTime)
            fresh += llList2List(g_attachments, i, i + ATTACH_STRIDE - 1);
        else
            llListenRemove(llList2Integer(g_attachments, i + 2)); // remove expired listen
    }
    g_attachments = fresh;
}

// ================================================================
default
{
    state_entry()
    {
        llSetTimerEvent(CLEANUP_INTERVAL);
    }

    timer()
    {
        cleanupExpired();
    }

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
            // directly from the jar's inventory  -  no rez needed.
            if (smoker != llGetOwner())
                giveToInventory(smoker, quality);
            else
                rezSmokeable(smoker, strain, quality);
        }

        // Main script can change the default smokeable type
        else if (cmd == "SET_SMOKE_TYPE")
        {
            g_smokeType = llList2String(parts, 1); // Joint, Blunt, Pipe
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        // We opened temp listeners for each rez  -  close them after
        // the smokeable object has confirmed it received attach instructions
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (cmd == "TC_ATTACH_CONFIRMED")
        {
            // Smokeable's listener is now open  -  send the attach instruction,
            // then clean up our tracking entry.
            integer i;
            for (i = 0; i < llGetListLength(g_attachments); i += ATTACH_STRIDE)
            {
                if (llList2Integer(g_attachments, i + 1) == channel)
                {
                    key    smoker  = (key)llList2String(g_attachments, i);
                    string strain  = llList2String(g_attachments, i + 4);
                    string quality = llList2String(g_attachments, i + 5);

                    // Now the smokeable is listening  -  send the attach instruction
                    llRegionSay(channel,
                        "TC_ATTACH_TO|" + (string)smoker + "|" +
                        (string)ATTACH_DURATION + "|" + strain + "|" + quality + "|" + g_smokeType);

                    llListenRemove(llList2Integer(g_attachments, i + 2));
                    g_attachments = llDeleteSubList(g_attachments, i, i + ATTACH_STRIDE - 1);
                    return;
                }
            }
        }
    }
}
