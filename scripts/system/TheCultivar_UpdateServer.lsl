// ================================================================
// TheCultivar_UpdateServer.lsl
// ================================================================
// UPDATE SERVER — SYNNIAH'S EYES ONLY
//
// Place this script inside a single prim object on Synniah's land.
//
// IMPORTANT: Before pushing updates, place all updated scripts
// into this server object's inventory. The server delivers
// WHATEVER SCRIPTS ARE IN ITS INVENTORY to client objects —
// make sure the inventory is current before triggering any push.
//
// NOTE: llRemoteLoadScriptPin only works if the target object is
// in the SAME REGION as this server object. Cross-region delivery
// is not supported by Second Life.
// ================================================================

integer TC_UPDATE_CHAN     = -777333111;
string  TC_CURRENT_VERSION = "1.0.0";

// Owner of the update server (Synniah's key — set automatically on state_entry)
key g_serverOwner = NULL_KEY;

// Listen handles
integer g_listenUpdate  = 0;
integer g_listenConfirm = 0;
integer g_listenMenu    = 0;

// Dialog channels
integer DCHAN_MENU    = -770001;
integer DCHAN_VERSION = -770002;

// Current version being served
string g_currentVersion = "1.0.0";

// Pending update: objectKey waiting for script delivery
key     g_pendingObject = NULL_KEY;
key     g_pendingOwner  = NULL_KEY;
string  g_pendingItem   = "";
integer g_pendingPin    = 0;

// ----------------------------------------------------------------
// isWhitelisted — returns TRUE if ownerKey is in the whitelist
// ----------------------------------------------------------------
integer isWhitelisted(key ownerKey)
{
    integer count = (integer)llLinksetDataRead("wl_count");
    integer i = 0;
    while (i < count)
    {
        string entry = llLinksetDataRead("wl_" + (string)i);
        list parts = llParseString2List(entry, ["|"], []);
        if ((key)llList2String(parts, 0) == ownerKey)
            return TRUE;
        i++;
    }
    return FALSE;
}

// ----------------------------------------------------------------
// registerOwner — adds a new owner to the whitelist, notifies Synniah
// ----------------------------------------------------------------
registerOwner(key ownerKey, string ownerName, string itemName)
{
    if (isWhitelisted(ownerKey))
        return;

    integer count = (integer)llLinksetDataRead("wl_count");
    string entry = (string)ownerKey + "|" + ownerName + "|" + itemName + "|" + llGetDate();
    llLinksetDataWrite("wl_" + (string)count, entry);
    count++;
    llLinksetDataWrite("wl_count", (string)count);

    llRegionSayTo(g_serverOwner, 0,
        "[Update Server] New registration: " + ownerName + " — " + itemName);
}

// ----------------------------------------------------------------
// registerObject — stores or updates an object's registry entry
// ----------------------------------------------------------------
registerObject(key objectKey, key ownerKey, string itemName, string version, integer pin)
{
    integer count = (integer)llLinksetDataRead("obj_count");
    string newEntry = (string)objectKey + "|" + (string)ownerKey + "|" + itemName + "|" + version + "|" + (string)pin;

    integer i = 0;
    integer found = FALSE;
    while (i < count)
    {
        string entry = llLinksetDataRead("obj_" + (string)i);
        list parts = llParseString2List(entry, ["|"], []);
        if ((key)llList2String(parts, 0) == objectKey)
        {
            llLinksetDataWrite("obj_" + (string)i, newEntry);
            found = TRUE;
            i = count;
        }
        else
        {
            i++;
        }
    }

    if (!found)
    {
        llLinksetDataWrite("obj_" + (string)count, newEntry);
        count++;
        llLinksetDataWrite("obj_count", (string)count);
    }
}

// ----------------------------------------------------------------
// getRegisteredPin — returns the script pin for a registered object
// ----------------------------------------------------------------
integer getRegisteredPin(key objectKey)
{
    integer count = (integer)llLinksetDataRead("obj_count");
    integer i = 0;
    while (i < count)
    {
        string entry = llLinksetDataRead("obj_" + (string)i);
        list parts = llParseString2List(entry, ["|"], []);
        if ((key)llList2String(parts, 0) == objectKey)
            return (integer)llList2String(parts, 4);
        i++;
    }
    return 0;
}

// ----------------------------------------------------------------
// getObjectItemName — looks up the item name for a registered object
// ----------------------------------------------------------------
string getObjectItemName(key objectKey)
{
    integer count = (integer)llLinksetDataRead("obj_count");
    integer i = 0;
    while (i < count)
    {
        string entry = llLinksetDataRead("obj_" + (string)i);
        list parts = llParseString2List(entry, ["|"], []);
        if ((key)llList2String(parts, 0) == objectKey)
            return llList2String(parts, 2);
        i++;
    }
    return "unknown item";
}

// ----------------------------------------------------------------
// pushScripts — delivers all inventory scripts to target object
// NOTE: Target object must be in the same region as this server.
// ----------------------------------------------------------------
pushScripts(key objectKey, integer pin)
{
    integer total = llGetInventoryNumber(INVENTORY_SCRIPT);
    integer i = 0;
    while (i < total)
    {
        string scriptName = llGetInventoryName(INVENTORY_SCRIPT, i);
        if (scriptName != "TheCultivar_UpdateServer")
        {
            llRemoteLoadScriptPin(objectKey, scriptName, pin, TRUE, 0);
        }
        i++;
    }
}

// ----------------------------------------------------------------
// showOwnerMenu — displays management dialog to Synniah
// ----------------------------------------------------------------
showOwnerMenu()
{
    llDialog(g_serverOwner,
        "=== THE CULTIVAR UPDATE SERVER ===\n\nv" + g_currentVersion + " — Choose an action:",
        ["Version Info", "List Owners", "Remove Owner", "Force Update All", "Close"],
        DCHAN_MENU);
}

// ================================================================
// DEFAULT STATE
// ================================================================
default
{
    state_entry()
    {
        g_serverOwner    = llGetOwner();
        g_currentVersion = TC_CURRENT_VERSION;

        string saved = llLinksetDataRead("server_version");
        if (saved != "")
            g_currentVersion = saved;

        if (llLinksetDataRead("wl_count") == "")
            llLinksetDataWrite("wl_count", "0");

        if (llLinksetDataRead("obj_count") == "")
            llLinksetDataWrite("obj_count", "0");

        g_listenUpdate = llListen(TC_UPDATE_CHAN, "", NULL_KEY, "");
        g_listenMenu   = llListen(DCHAN_MENU, "", g_serverOwner, "");

        llSetText("THE CULTIVAR\nUpdate Server v" + g_currentVersion +
                  "\nOwner touch to manage", <0.2, 0.9, 0.2>, 1.0);
    }

    touch_start(integer num)
    {
        key toucher = llDetectedKey(0);
        if (toucher != g_serverOwner)
        {
            llRegionSayTo(toucher, 0,
                "[The Cultivar] This update server is private.");
            return;
        }
        showOwnerMenu();
    }

    listen(integer channel, string name, key id, string msg)
    {
        // ---- TC_UPDATE_CHAN: client pings and confirmations ----
        if (channel == TC_UPDATE_CHAN)
        {
            list parts = llParseString2List(msg, ["|"], []);
            string cmd = llList2String(parts, 0);

            if (cmd == "TC_UPDATE_PING")
            {
                string  clientVersion = llList2String(parts, 1);
                key     ownerKey      = (key)llList2String(parts, 2);
                string  ownerName     = llList2String(parts, 3);
                key     objectKey     = (key)llList2String(parts, 4);
                string  itemName      = llList2String(parts, 5);
                integer pin           = (integer)llList2String(parts, 6);
                integer replyChannel  = (integer)llList2String(parts, 7);

                if (!isWhitelisted(ownerKey))
                    registerOwner(ownerKey, ownerName, itemName);

                registerObject(objectKey, ownerKey, itemName, clientVersion, pin);

                if (clientVersion == g_currentVersion)
                    return;

                llRegionSay(replyChannel,
                    "TC_UPDATE_AVAILABLE|" + g_currentVersion + "|" + itemName);
            }
            else if (cmd == "TC_UPDATE_CONFIRM")
            {
                key objectKey = (key)llList2String(parts, 1);
                key ownerKey  = (key)llList2String(parts, 2);

                integer pin = getRegisteredPin(objectKey);
                if (pin == 0)
                {
                    llRegionSayTo(ownerKey, 0,
                        "[The Cultivar] Update failed — object not registered. " +
                        "Please re-rez your item and try again.");
                    return;
                }

                g_pendingObject = objectKey;
                g_pendingOwner  = ownerKey;
                g_pendingItem   = getObjectItemName(objectKey);

                llRegionSayTo(ownerKey, 0,
                    "[The Cultivar] Pushing update to your " +
                    g_pendingItem + "... please wait.");

                pushScripts(objectKey, pin);

                llRegionSayTo(ownerKey, 0,
                    "[The Cultivar] Update complete! Your item is now v" +
                    g_currentVersion + ". You may need to re-rez it.");
            }
        }

        // ---- DCHAN_MENU: owner management dialog responses ----
        else if (channel == DCHAN_MENU)
        {
            if (msg == "Version Info")
            {
                integer wlCount = (integer)llLinksetDataRead("wl_count");
                llRegionSayTo(g_serverOwner, 0,
                    "[Update Server] Current version: " + g_currentVersion +
                    " | Registered owners: " + (string)wlCount);
            }
            else if (msg == "List Owners")
            {
                integer count = (integer)llLinksetDataRead("wl_count");
                if (count == 0)
                {
                    llRegionSayTo(g_serverOwner, 0,
                        "[Update Server] No owners registered yet.");
                }
                else
                {
                    integer i = 0;
                    while (i < count)
                    {
                        string entry = llLinksetDataRead("wl_" + (string)i);
                        list parts = llParseString2List(entry, ["|"], []);
                        llRegionSayTo(g_serverOwner, 0,
                            "[" + (string)(i + 1) + "] " +
                            llList2String(parts, 1) + " — " +
                            llList2String(parts, 2) +
                            " (registered " + llList2String(parts, 3) + ")");
                        i++;
                    }
                }
            }
            else if (msg == "Remove Owner")
            {
                llTextBox(g_serverOwner,
                    "Enter the owner UUID key to remove from the whitelist:",
                    DCHAN_VERSION);
                if (g_listenConfirm)
                    llListenRemove(g_listenConfirm);
                g_listenConfirm = llListen(DCHAN_VERSION, "", g_serverOwner, "");
            }
            else if (msg == "Force Update All")
            {
                llRegionSay(TC_UPDATE_CHAN,
                    "TC_FORCE_UPDATE|" + g_currentVersion);
                llRegionSayTo(g_serverOwner, 0,
                    "[Update Server] Force update broadcast sent. " +
                    "Objects will be notified on their next ping.");
            }
            // "Close" — do nothing
        }

        // ---- DCHAN_VERSION: text box response for Remove Owner ----
        else if (channel == DCHAN_VERSION)
        {
            if (g_listenConfirm)
            {
                llListenRemove(g_listenConfirm);
                g_listenConfirm = 0;
            }

            key removeKey = (key)msg;
            if (removeKey == NULL_KEY)
            {
                llRegionSayTo(g_serverOwner, 0,
                    "[Update Server] Invalid key — nothing removed.");
                return;
            }

            integer count = (integer)llLinksetDataRead("wl_count");
            integer found = FALSE;
            list newEntries = [];
            integer i = 0;
            while (i < count)
            {
                string entry = llLinksetDataRead("wl_" + (string)i);
                list parts = llParseString2List(entry, ["|"], []);
                if ((key)llList2String(parts, 0) != removeKey)
                {
                    newEntries += [entry];
                }
                else
                {
                    found = TRUE;
                }
                i++;
            }

            if (!found)
            {
                llRegionSayTo(g_serverOwner, 0,
                    "[Update Server] Key not found in whitelist.");
                return;
            }

            integer newCount = llGetListLength(newEntries);
            i = 0;
            while (i < newCount)
            {
                llLinksetDataWrite("wl_" + (string)i, llList2String(newEntries, i));
                i++;
            }
            llLinksetDataWrite("wl_count", (string)newCount);
            llRegionSayTo(g_serverOwner, 0,
                "[Update Server] Owner removed from whitelist. (" +
                (string)newCount + " remaining)");
        }
    }
}
