// ================================================================
// TheCultivar_UpdateClient.lsl
// ================================================================
// SETUP INSTRUCTIONS:
// Change g_itemName below to match the item this script lives in.
// Each kit item needs its own copy of this script with the correct
// g_itemName set. Examples:
//   "TC_HUD"
//   "TC_GrowLight"
//   "TC_WeedJar"
//   "TC_BaggingTable"
//   "TC_RollingTable"
//   "TC_StashBox"
//   "TC_Plant"
//   "TC_SessionObject"
// ================================================================

integer TC_UPDATE_CHAN     = -777333111;
string  TC_CURRENT_VERSION = "1.0.0";

string  g_itemName      = "TC_Item";   // SET THIS per item
string  g_version       = "1.0.0";     // Current version of this item
integer g_scriptPin     = 0;           // Generated from object key
integer g_replyChannel  = 0;           // Private reply channel
integer g_listenReply   = 0;           // Listen handle for server reply
integer g_listenConfirm = 0;           // Listen handle for update dialog
integer DCHAN_UPDATE    = -771001;     // Dialog channel for update permission

// ----------------------------------------------------------------
// derivePin — generates a consistent positive non-zero pin from
// this object's key so the server can inject scripts remotely
// ----------------------------------------------------------------
integer derivePin()
{
    string keyStr = llGetSubString((string)llGetKey(), 0, 7);
    keyStr = llDumpList2String(llParseString2List(keyStr, ["-"], []), "");
    integer pin = (integer)("0x" + keyStr);
    if (pin < 0)
        pin = pin * -1;
    if (pin == 0)
        pin = 12345;
    return pin;
}

// ----------------------------------------------------------------
// pingServer — broadcasts a version check to the update server
// ----------------------------------------------------------------
pingServer()
{
    if (g_listenReply)
    {
        llListenRemove(g_listenReply);
        g_listenReply = 0;
    }

    g_replyChannel = -1000000 - (integer)llFrand(999999.0);
    g_listenReply  = llListen(g_replyChannel, "", NULL_KEY, "");

    llSetRemoteScriptAccessPin(g_scriptPin);

    llRegionSay(TC_UPDATE_CHAN,
        "TC_UPDATE_PING|" + g_version + "|" +
        (string)llGetOwner() + "|" +
        llGetDisplayName(llGetOwner()) + "|" +
        (string)llGetKey() + "|" +
        g_itemName + "|" +
        (string)g_scriptPin + "|" +
        (string)g_replyChannel);

    // 30-second timeout — silently remove listener if no server response
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// showUpdateDialog — asks owner whether to apply the update
// ----------------------------------------------------------------
showUpdateDialog(string newVersion)
{
    if (g_listenConfirm)
    {
        llListenRemove(g_listenConfirm);
        g_listenConfirm = 0;
    }
    g_listenConfirm = llListen(DCHAN_UPDATE, "", llGetOwner(), "");

    llDialog(llGetOwner(),
        "=== THE CULTIVAR UPDATE ===\n\n" +
        "A new update is available for your " + g_itemName + "!\n\n" +
        "Current version: " + g_version + "\n" +
        "New version: " + newVersion + "\n\n" +
        "Scripts will be replaced in place.\n" +
        "Your object will stay exactly where it is.",
        ["Update Now", "Skip"],
        DCHAN_UPDATE);
}

// ================================================================
// DEFAULT STATE
// ================================================================
default
{
    state_entry()
    {
        g_version   = TC_CURRENT_VERSION;
        g_scriptPin = derivePin();
        llSetRemoteScriptAccessPin(g_scriptPin);

        // Small delay so the sim has settled after rez before pinging
        llSetTimerEvent(3.0);
    }

    timer()
    {
        llSetTimerEvent(0.0);

        // If the reply listener is still open, this is the 30-second timeout
        if (g_listenReply)
        {
            llListenRemove(g_listenReply);
            g_listenReply = 0;
            // Server unreachable or offline — fail silently
            return;
        }

        // Otherwise this is the initial 3-second startup delay
        pingServer();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list parts = llParseString2List(msg, ["|"], []);
        string cmd = llList2String(parts, 0);

        // ---- Reply from server: update is available ----
        if (channel == g_replyChannel && cmd == "TC_UPDATE_AVAILABLE")
        {
            string newVersion = llList2String(parts, 1);

            if (g_listenReply)
            {
                llListenRemove(g_listenReply);
                g_listenReply = 0;
            }

            // Cancel the 30-second timeout — we got a reply
            llSetTimerEvent(0.0);

            llRegionSayTo(llGetOwner(), 0,
                "[The Cultivar] An update is available for your " +
                g_itemName + " (v" + g_version + " -> v" + newVersion + "). " +
                "Check your dialog box.");

            showUpdateDialog(newVersion);
        }

        // ---- Dialog response from owner ----
        else if (channel == DCHAN_UPDATE)
        {
            if (g_listenConfirm)
            {
                llListenRemove(g_listenConfirm);
                g_listenConfirm = 0;
            }

            if (msg == "Update Now")
            {
                llRegionSayTo(llGetOwner(), 0,
                    "[The Cultivar] Requesting update for " + g_itemName +
                    "... please stand by.");

                llRegionSay(TC_UPDATE_CHAN,
                    "TC_UPDATE_CONFIRM|" +
                    (string)llGetKey() + "|" +
                    (string)llGetOwner());
            }
            else if (msg == "Skip")
            {
                llRegionSayTo(llGetOwner(), 0,
                    "[The Cultivar] Update skipped. You can re-rez this item " +
                    "later to be prompted again.");
            }
        }
    }

    on_rez(integer start_param)
    {
        // Re-derive pin in case object key changed after copy
        g_scriptPin = derivePin();
        llSetRemoteScriptAccessPin(g_scriptPin);
        llSetTimerEvent(3.0);
    }
}
