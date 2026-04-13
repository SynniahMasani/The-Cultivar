// ================================================================
// THE CULTIVAR  -  HUD Comms Script
// Version: 1.7
// Preserves the full working HUD Comms logic while:
//   - removing debug spam
//   - forcing smoke cleanup on session end / leave / early stop
//   - relaying overhead text cleanup to UI
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_IDENTITY  = 400;
integer CHAN_ANIMATION = 500;
integer CHAN_SESSION   = 600;

integer PUBLIC_SESSION_CHAN = -987654321;
integer TC_OBJECT_PING_CHAN = -111222333;

integer g_privateChannel;
integer g_listenPrivate;
integer g_listenSession;

key     g_ownerKey;
string  g_ownerName;

list g_wrapperInventory = [];

integer g_inSession = FALSE;
key     g_sessionObjectKey = NULL_KEY;
string  g_sessionHost = "";

integer g_myStoryChannel = -140200;

string  g_smokingItemType = "";
string  g_smokingQuality  = "";
string  g_smokingStrain   = "";
integer g_smokingResumeSecs = 0;

integer g_waitingForSessionRez = FALSE;
integer g_sessionRezArmedAt    = 0;
integer SESSION_REZ_WINDOW_SEC = 15;

integer getSmokeDuration(string itemType, string quality)
{
    if (itemType == "blunt")
    {
        if (quality == "mids")   return 600;
        if (quality == "loud")   return 720;
        if (quality == "exotic") return 900;
        return 480;
    }
    if (itemType == "spliff")
    {
        if (quality == "mids")   return 300;
        if (quality == "loud")   return 360;
        if (quality == "exotic") return 480;
        return 240;
    }
    if (itemType == "edible")
    {
        if (quality == "mids")   return 720;
        if (quality == "loud")   return 900;
        if (quality == "exotic") return 1200;
        return 600;
    }
    if (quality == "mids")   return 360;
    if (quality == "loud")   return 480;
    if (quality == "exotic") return 600;
    return 300;
}

string capitalize(string s)
{
    if (s == "") return s;
    return llToUpper(llGetSubString(s, 0, 0)) + llGetSubString(s, 1, -1);
}

integer derivePrivateChannel(key ownerID)
{
    string hexSub = llGetSubString((string)ownerID, 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub,["-"],[]),"");
    return (integer)("0x" + hexSub) * -1;
}

startListening()
{
    g_listenPrivate = llListen(g_privateChannel, "", NULL_KEY, "");
    g_listenSession = llListen(PUBLIC_SESSION_CHAN, "", NULL_KEY, "");
    llListen(TC_OBJECT_PING_CHAN, "", NULL_KEY, "");
}

registerWithObject(key objectKey)
{
    llRegionSayTo(objectKey, 0,
        "TC_REGISTER|" + (string)g_ownerKey + "|" +
        (string)g_privateChannel + "|" + g_ownerName + "|" +
        llLinksetDataRead("id_brand"));
}

clearSmokeState()
{
    g_smokingItemType = "";
    g_smokingQuality  = "";
    g_smokingStrain   = "";
    g_smokingResumeSecs = 0;
}

forceSmokeCleanup()
{
    llSay(g_privateChannel, "TC_END_SMOKE");
    llMessageLinked(LINK_SET, CHAN_ANIMATION, "STOP_SMOKE_ANIM", NULL_KEY);
    llMessageLinked(LINK_SET, CHAN_UI, "SMOKE_STOPPED", NULL_KEY);
    llMessageLinked(LINK_SET, CHAN_UI, "SESSION_OVERHEAD|", NULL_KEY);
    clearSmokeState();
}

default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llGetDisplayName(g_ownerKey);
        g_privateChannel = derivePrivateChannel(g_ownerKey);
        llLinksetDataWrite("hud_private_chan", (string)g_privateChannel);
        startListening();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != CHAN_COMMS) return;

        if (msg == "ARM_SESSION_REZ")
        {
            g_waitingForSessionRez = TRUE;
            g_sessionRezArmedAt    = llGetUnixTime();
            return;
        }
        if (msg == "CANCEL_SESSION_REZ")
        {
            g_waitingForSessionRez = FALSE;
            g_sessionRezArmedAt    = 0;
            return;
        }
        if (msg == "END_SMOKE_EARLY")
        {
            // Keep smoke state until TC_SMOKE_PAUSED/TC_SMOKE_FINISHED arrives
            // so resume data can be written before cleanup.
            llSay(g_privateChannel, "TC_END_SMOKE");
            llMessageLinked(LINK_SET, CHAN_ANIMATION, "STOP_SMOKE_ANIM", NULL_KEY);
            return;
        }
        if (msg == "LEAVE_SESSION")
        {
            if (g_inSession && g_sessionObjectKey != NULL_KEY)
            {
                llRegionSayTo(g_sessionObjectKey, 0,
                    "TC_SESSION_LEAVE|" + (string)g_ownerKey);
            }
            g_inSession        = FALSE;
            g_sessionObjectKey = NULL_KEY;
            g_sessionHost      = "";
            llMessageLinked(LINK_SET, CHAN_SESSION,
                "SYNC_SESSION_STATE|0||", NULL_KEY);
            // Request end, then wait for paused/finished callback to preserve resume.
            llSay(g_privateChannel, "TC_END_SMOKE");
            llMessageLinked(LINK_SET, CHAN_ANIMATION, "STOP_SMOKE_ANIM", NULL_KEY);
            llMessageLinked(LINK_SET, CHAN_UI, "SESSION_OVERHEAD|", NULL_KEY);
            return;
        }
        if (msg == "MYSTORY_TRIGGER")
        {
            llSay(g_myStoryChannel, "Start Effects");
            return;
        }

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (cmd == "REGISTER_OBJECT")
        {
            registerWithObject((key)llList2String(parts, 1));
        }
        else if (cmd == "START_SESSION")
        {
            key sessionObj = (key)llList2String(parts, 1);
            g_inSession        = TRUE;
            g_sessionObjectKey = sessionObj;
            g_sessionHost      = g_ownerName;
            llLinksetDataWrite("hud_private_chan", (string)g_privateChannel);
            llMessageLinked(LINK_SET, CHAN_UI,
                "SESSION_STARTED|" + (string)sessionObj, NULL_KEY);
            llMessageLinked(LINK_SET, CHAN_SESSION,
                "SYNC_SESSION_STATE|1|" + (string)sessionObj + "|" + g_sessionHost, NULL_KEY);
        }
        else if (cmd == "JOIN_SESSION")
        {
            key    sessObjKey = (key)llList2String(parts, 1);
            string hostName   = llList2String(parts, 2);
            llRegionSayTo(sessObjKey, 0,
                "TC_SESSION_JOIN|" + (string)g_ownerKey + "|" +
                (string)g_privateChannel + "|" + g_ownerName);
            g_inSession        = TRUE;
            g_sessionObjectKey = sessObjKey;
            g_sessionHost      = hostName;
            llMessageLinked(LINK_SET, CHAN_SESSION,
                "SYNC_SESSION_STATE|1|" + (string)g_sessionObjectKey + "|" + g_sessionHost, NULL_KEY);
        }
        else if (cmd == "PASS_TO_PLAYER")
        {
            key    targetKey = (key)llList2String(parts, 1);
            string passMsg   = "TC_RECEIVE_PASS|" +
                               llList2String(parts, 2) + "|" +
                               llList2String(parts, 3) + "|" +
                               llList2String(parts, 4) + "|" +
                               llList2String(parts, 5) + "|" +
                               llList2String(parts, 6) + "|" +
                               g_ownerName;
            integer targetChan = derivePrivateChannel(targetKey);
            llRegionSayTo(targetKey, targetChan, passMsg);
            llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_PASSED", NULL_KEY);
        }
        else if (cmd == "REMOVE_SUCCESS")
        {
            llMessageLinked(LINK_SET, CHAN_UI, "ITEM_USED|" + msg, NULL_KEY);
            if (id != NULL_KEY)
                llRegionSayTo(id, g_privateChannel, "TC_REMOVE_OK");
        }
        else if (cmd == "REMOVE_FAIL")
        {
            llMessageLinked(LINK_SET, CHAN_UI, "ITEM_FAILED|" + msg, NULL_KEY);
            if (id != NULL_KEY)
                llRegionSayTo(id, g_privateChannel, "TC_REMOVE_FAIL");
        }
        else if (cmd == "TC_SMOKE_START")
        {
            if (g_smokingItemType != "")
            {
                integer activeDur = getSmokeDuration(g_smokingItemType, g_smokingQuality);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SMOKE_STARTED|" + g_smokingStrain + "|" +
                    g_smokingQuality + "|" + (string)activeDur, NULL_KEY);
                llOwnerSay("You're already smoking. Put it out first.");
                return;
            }

            g_smokingItemType = llList2String(parts, 1);
            g_smokingQuality  = llList2String(parts, 2);
            g_smokingStrain   = llList2String(parts, 3);
            integer resumeSeconds = (integer)llList2String(parts, 4);
            g_smokingResumeSecs = resumeSeconds;

            if (resumeSeconds > 0)
            {
                llLinksetDataDelete("smoke_paused_" + g_smokingItemType +
                                    "_" + g_smokingQuality +
                                    "_" + g_smokingStrain);
            }

            string propName = "TC_Smoke_" + capitalize(g_smokingItemType) +
                              "_" + capitalize(g_smokingQuality);
            if (llGetInventoryType(propName) != INVENTORY_OBJECT)
                propName = "TC_Smoke_Joint_Reggie";

            if (llGetInventoryType(propName) == INVENTORY_OBJECT)
            {
                vector ownerPos = llList2Vector(
                    llGetObjectDetails(g_ownerKey, [OBJECT_POS]), 0);
                if (ownerPos == ZERO_VECTOR)
                    ownerPos = llGetPos();
                llRezObject(propName, ownerPos + <0.0, 0.0, 0.3>,
                            ZERO_VECTOR, ZERO_ROTATION, resumeSeconds);
            }
            else
            {
                llOwnerSay("[TC] Smoke prop '" + propName + "' not found in HUD.");
            }
        }
        else if (cmd == "RAW_INVENTORY")
        {
            string rawData   = llList2String(parts, 1);
            key    reqObject = (key)llList2String(parts, 3);
            if (reqObject != NULL_KEY)
                llRegionSayTo(reqObject, g_privateChannel, "TC_INVENTORY_DATA|" + rawData);
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (channel == TC_OBJECT_PING_CHAN && cmd == "TC_PING")
        {
            key     objectKey    = (key)llList2String(parts, 1);
            integer replyChannel = (integer)llList2String(parts, 3);
            if (replyChannel == 0) return;
            llRegionSayTo(objectKey, replyChannel,
                "TC_REGISTER|" + (string)g_ownerKey + "|" +
                (string)g_privateChannel + "|" + g_ownerName + "|" +
                llLinksetDataRead("id_brand"));
        }
        else if (channel == TC_OBJECT_PING_CHAN && cmd == "TC_SESSION_REZZED")
        {
            integer ageOK = (llGetUnixTime() - g_sessionRezArmedAt) < SESSION_REZ_WINDOW_SEC;
            if (!g_waitingForSessionRez || !ageOK)
                return;

            key sessObjKey = (key)llList2String(parts, 1);
            g_waitingForSessionRez = FALSE;
            g_sessionRezArmedAt    = 0;
            llMessageLinked(LINK_SET, CHAN_UI,
                "SESSION_OBJECT_READY|" + (string)sessObjKey, NULL_KEY);
            llMessageLinked(LINK_SET, CHAN_SESSION,
                "SESSION_OBJECT_READY|" + (string)sessObjKey, NULL_KEY);
        }
        else if (channel == g_privateChannel)
        {
            if (cmd == "TC_SMOKE_ATTACH_READY")
            {
                integer duration;
                if (g_smokingResumeSecs > 0)
                    duration = g_smokingResumeSecs;
                else
                    duration = getSmokeDuration(g_smokingItemType, g_smokingQuality);
                g_smokingResumeSecs = 0;
                llMessageLinked(LINK_SET, CHAN_ANIMATION,
                    "START_SMOKE_ANIM|" + g_smokingStrain + "|" +
                    g_smokingQuality + "|" + g_smokingItemType, NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SMOKE_STARTED|" + g_smokingStrain + "|" + g_smokingQuality +
                    "|" + (string)duration, NULL_KEY);
            }
            else if (cmd == "TC_SMOKE_FINISHED")
            {
                if (g_smokingItemType != "")
                {
                    llLinksetDataDelete("smoke_paused_" + g_smokingItemType +
                                        "_" + g_smokingQuality +
                                        "_" + g_smokingStrain);
                }
                forceSmokeCleanup();
            }
            else if (cmd == "TC_SMOKE_PAUSED")
            {
                string pType    = llList2String(parts, 1);
                string pQuality = llList2String(parts, 2);
                integer pRem    = (integer)llList2String(parts, 3);
                string pStrain  = g_smokingStrain;
                if (pType != "" && pQuality != "" && pStrain != "" && pRem > 0)
                {
                    llLinksetDataWrite("smoke_paused_" + pType + "_" +
                                       pQuality + "_" + pStrain,
                                       (string)pRem);
                }
                forceSmokeCleanup();
            }
            else if (cmd == "TC_HARVEST_RESULT")
            {
                string strain  = llList2String(parts, 1);
                string quality = llList2String(parts, 2);
                integer qty    = (integer)llList2String(parts, 3);
                string owner   = llGetDisplayName(g_ownerKey);

                integer growerLevel = (integer)llLinksetDataRead("grower_level");
                if (growerLevel >= 20)
                    qty = qty + (qty * 30 / 100);
                else if (growerLevel >= 10)
                    qty = qty + (qty * 15 / 100);

                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "ADD_ITEM|flower_raw|" + strain + "|" + quality + "|" +
                    (string)qty + "|" + owner, NULL_KEY);

                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_GROWN", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_XP|grower|5", NULL_KEY);

                llOwnerSay("Harvest received: " + (string)qty + "g of " +
                           quality + " " + strain + "!");
            }
            else if (cmd == "TC_SMOKED")
            {
                string strain  = llList2String(parts, 1);
                string quality = llList2String(parts, 2);
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_SMOKED|" + strain, NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_ANIMATION,
                    "START_SMOKE_ANIM|" + strain + "|" + quality, NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SMOKE_STARTED|" + strain + "|" + quality + "|0", NULL_KEY);

                integer qualTier = 1;
                if (quality == "mids")        qualTier = 2;
                else if (quality == "loud")   qualTier = 3;
                else if (quality == "exotic") qualTier = 4;
                llSay(g_myStoryChannel, "Start Effects " + (string)qualTier);
            }
            else if (cmd == "TC_SESSION_SYNC")
            {
                string itemType = llList2String(parts, 1);
                string strain   = llList2String(parts, 2);
                string quality  = llList2String(parts, 3);
                if (g_smokingItemType == "") g_smokingItemType = itemType;
                if (g_smokingStrain == "")   g_smokingStrain   = strain;
                if (g_smokingQuality == "")  g_smokingQuality  = quality;
            }
            else if (cmd == "TC_SESSION_END")
            {
                g_inSession        = FALSE;
                g_sessionObjectKey = NULL_KEY;
                g_sessionHost      = "";
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|0||", NULL_KEY);
                forceSmokeCleanup();
                llMessageLinked(LINK_SET, CHAN_UI, "SESSION_ENDED", NULL_KEY);
            }
            else if (cmd == "TC_JOIN_REJECTED")
            {
                string reason = llList2String(parts, 1);
                if (reason == "distance")
                    llOwnerSay("Couldn't join: you're too far from the session object. Move closer.");
                else
                    llOwnerSay("Couldn't join the session.");
                g_inSession = FALSE;
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|0||", NULL_KEY);
            }
            else if (cmd == "TC_SESSION_JOINED")
            {
                g_sessionObjectKey = (key)llList2String(parts, 1);
                g_inSession        = TRUE;
                g_sessionHost      = llList2String(parts, 3);
                string itemType    = llList2String(parts, 4);
                string strain      = llList2String(parts, 5);
                string quality     = llList2String(parts, 6);
                if (g_smokingItemType == "") g_smokingItemType = itemType;
                if (g_smokingStrain == "")   g_smokingStrain   = strain;
                if (g_smokingQuality == "")  g_smokingQuality  = quality;
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SESSION_JOINED|" + g_sessionHost + "|" +
                    (string)g_sessionObjectKey, NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|1|" + (string)g_sessionObjectKey + "|" + g_sessionHost, NULL_KEY);
            }
            else if (cmd == "SESSION_OVERHEAD")
            {
                llMessageLinked(LINK_SET, CHAN_UI, msg, NULL_KEY);
            }
            else if (cmd == "TC_PASS_RECEIVED")
            {
                string strain  = llList2String(parts, 1);
                llMessageLinked(LINK_SET, CHAN_ANIMATION, "PLAY_PASS_RECEIVE", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_SMOKED|" + strain, NULL_KEY);
            }
            else if (cmd == "TC_PASS_GIVEN")
            {
                llMessageLinked(LINK_SET, CHAN_ANIMATION, "PLAY_PASS_GIVE", NULL_KEY);
            }
            else if (cmd == "TC_SESSION_MEMBER_JOIN")
            {
                string joinerName = llList2String(parts, 1);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SESSION_MEMBER_JOIN|" + joinerName, NULL_KEY);
            }
            else if (cmd == "TC_SESSION_MEMBER_LEAVE")
            {
                string leaverName = llList2String(parts, 1);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SESSION_MEMBER_LEAVE|" + leaverName, NULL_KEY);
            }
            else if (cmd == "TC_SALE_COMPLETE")
            {
                string salePrice  = llList2String(parts, 1);
                string buyerName  = llList2String(parts, 2);
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_SOLD", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_XP|seller|1", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "NOTIFY|sale_made|Sale! L$" + salePrice +
                    " from " + buyerName + ".", NULL_KEY);
                llOwnerSay("Sale complete! L$" + salePrice +
                           " has been paid to you.");
            }
            else if (cmd == "TC_NOTIFY")
            {
                llMessageLinked(LINK_SET, CHAN_UI,
                    "NOTIFY|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }
            else if (cmd == "TC_XP_UPDATE")
            {
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_XP|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }
            else if (cmd == "TC_YOUR_TURN")
            {
                llMessageLinked(LINK_SET, CHAN_UI,
                    "YOUR_TURN_COUNTDOWN|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }
            else if (cmd == "TC_CYPHER_MODE")
            {
                llMessageLinked(LINK_SET, CHAN_UI,
                    "CYPHER_MODE_CHANGE|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }
            else if (cmd == "TC_RECEIVE_PASS")
            {
                string fromName = llList2String(parts, 6);
                string strain   = llList2String(parts, 2);
                string quality  = llList2String(parts, 3);
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "ADD_ITEM|"     + llList2String(parts,1) + "|" +
                    strain          + "|" +
                    quality         + "|" +
                    llList2String(parts,4) + "|" +
                    llList2String(parts,5), NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_ANIMATION, "PLAY_PASS_RECEIVE", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "PASS_RECEIVED_NOTIFY|" + fromName + "|" + strain + "|" + quality,
                    NULL_KEY);
            }
            else if (cmd == "TC_REP_GIVEN")
            {
                integer delta = (integer)llList2String(parts,1);
                string  from  = llList2String(parts,2);
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_REP|" + (string)delta, NULL_KEY);
                llOwnerSay(from + " gave you a rep point!");
            }
            else if (cmd == "TC_INVENTORY_REQUEST")
            {
                string filterType = llList2String(parts, 1);
                string rawAll     = llLinksetDataRead("inv_data");
                string output;

                if (filterType == "" || filterType == "all")
                {
                    output = rawAll;
                }
                else
                {
                    output = "";
                    list slots = llParseString2List(rawAll, ["^"], []);
                    integer si;
                    for (si = 0; si < llGetListLength(slots); si++)
                    {
                        string slot   = llList2String(slots, si);
                        list   fields = llParseString2List(slot, ["~"], []);
                        if (llList2String(fields, 0) == filterType)
                        {
                            if (output == "") output  = slot;
                            else              output += "^" + slot;
                        }
                    }
                }
                llRegionSayTo(id, g_privateChannel, "TC_INVENTORY_DATA|" + output);
            }
            else if (cmd == "TC_ADD_ITEM")
            {
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "ADD_ITEM|"             +
                    llList2String(parts, 1) + "|" +
                    llList2String(parts, 2) + "|" +
                    llList2String(parts, 3) + "|" +
                    llList2String(parts, 4) + "|" +
                    llList2String(parts, 5), NULL_KEY);
            }
            else if (cmd == "TC_REMOVE_ITEM")
            {
                string iType     = llList2String(parts, 1);
                string iStrain   = llList2String(parts, 2);
                string iQuality  = llList2String(parts, 3);
                integer iQty     = (integer)llList2String(parts, 4);
                string iPackager = llList2String(parts, 5);

                string rawData = llLinksetDataRead("inv_data");
                list   inv     = [];

                list slots = llParseString2List(rawData, ["^"], []);
                integer si;
                for (si = 0; si < llGetListLength(slots); si++)
                {
                    list fields = llParseStringKeepNulls(llList2String(slots, si), ["~"], []);
                    if (llGetListLength(fields) == 5)
                        inv += fields;
                }

                integer found = -1;
                integer fi;
                for (fi = 0; fi < llGetListLength(inv); fi += 5)
                {
                    if (llList2String(inv, fi)   == iType   &&
                        llList2String(inv, fi+1) == iStrain &&
                        llList2String(inv, fi+2) == iQuality &&
                        (iPackager == "" || llList2String(inv, fi+4) == iPackager))
                    {
                        found = fi;
                        fi = llGetListLength(inv);
                    }
                }

                integer success = FALSE;
                if (found != -1)
                {
                    integer current = (integer)llList2String(inv, found + 3);
                    if (current >= iQty)
                    {
                        integer newQty = current - iQty;
                        if (newQty <= 0)
                            inv = llDeleteSubList(inv, found, found + 4);
                        else
                            inv = llListReplaceList(inv, [(string)newQty], found+3, found+3);
                        success = TRUE;
                    }
                }

                if (success)
                {
                    string serial = "";
                    integer wi;
                    for (wi = 0; wi < llGetListLength(inv); wi += 5)
                    {
                        string slot = llList2String(inv, wi)   + "~" +
                                      llList2String(inv, wi+1) + "~" +
                                      llList2String(inv, wi+2) + "~" +
                                      llList2String(inv, wi+3) + "~" +
                                      llList2String(inv, wi+4);
                        if (serial == "") serial  = slot;
                        else              serial += "^" + slot;
                    }
                    llLinksetDataWrite("inv_data", serial);
                    llMessageLinked(LINK_SET, CHAN_INVENTORY, "RELOAD_INVENTORY", NULL_KEY);
                    llMessageLinked(LINK_SET, CHAN_UI, "ITEM_USED|" + iType + "|" + iStrain, NULL_KEY);
                    llRegionSayTo(id, g_privateChannel, "TC_REMOVE_OK");
                }
                else
                {
                    llMessageLinked(LINK_SET, CHAN_UI, "ITEM_FAILED|" + iType + "|" + iStrain, NULL_KEY);
                    llRegionSayTo(id, g_privateChannel, "TC_REMOVE_FAIL");
                }
            }
            else if (cmd == "TC_CONSUME_ITEM")
            {
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "REMOVE_ITEM|"          +
                    llList2String(parts, 1) + "|" +
                    llList2String(parts, 2) + "|" +
                    llList2String(parts, 3) + "|" +
                    llList2String(parts, 4) + "|", id);
            }
            else if (cmd == "TC_REQUEST_RAW_INVENTORY")
            {
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "REQUEST_RAW_INVENTORY|" + llList2String(parts, 1) + "|" + (string)id,
                    NULL_KEY);
            }
            else if (cmd == "TC_WRAPPER_GIVE")
            {
                string  flavor    = llList2String(parts, 1);
                integer count     = (integer)llList2String(parts, 2);
                key     avatarKey = (key)llList2String(parts, 3);

                if (avatarKey != g_ownerKey) return;
                if (flavor == "") return;
                if (count <= 0) return;

                integer found = llListFindList(g_wrapperInventory, [flavor]);
                if (found >= 0)
                {
                    integer existing = llList2Integer(g_wrapperInventory, found + 1);
                    g_wrapperInventory = llListReplaceList(g_wrapperInventory,
                        [existing + count], found + 1, found + 1);
                }
                else
                {
                    g_wrapperInventory += [flavor, count];
                }

                llRegionSayTo(id, g_privateChannel, "TC_WRAPPER_ACK");
                llMessageLinked(LINK_SET, CHAN_UI,
                    "WRAPPER_ADDED|" + flavor + "|" + (string)count, NULL_KEY);
            }
        }
        else if (channel == PUBLIC_SESSION_CHAN)
        {
            if (cmd == "TC_SESSION_INVITE")
            {
                string hostName  = llList2String(parts, 1);
                key    hostKey   = (key)llList2String(parts, 2);
                key    sessKey   = (key)llList2String(parts, 3);
                string strain    = llList2String(parts, 4);
                string quality   = llList2String(parts, 5);

                if (hostKey == g_ownerKey) return;
                if (g_inSession) return;

                string brandName = llList2String(parts, 7);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SHOW_SESSION_INVITE|" + hostName + "|" +
                    (string)sessKey + "|" + strain + "|" + quality + "|" +
                    brandName, NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SESSION_INVITE|" + hostName + "|" +
                    (string)sessKey + "|" + strain + "|" + quality + "|" +
                    brandName, NULL_KEY);
            }
        }
    }
}
