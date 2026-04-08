// ================================================================
// THE CULTIVAR - HUD Session UI
// Handles: Spark Session menus, item selection, and invites.
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_SESSION   = 600; // New dedicated routing channel

integer DCHAN_SESSION_MENU   = -11006;
integer DCHAN_SESSION_INVITE = -11007;
integer DCHAN_SESSION_ITEM   = -11008;

integer g_lisSessionMenu;
integer g_lisSessionInvite;
integer g_lisSessionItem;

key     g_ownerKey;
integer g_inSession     = FALSE;
key     g_sessionObjKey = NULL_KEY;
string  g_sessionHost   = "";

key     g_inviteSessKey  = NULL_KEY;
string  g_inviteHostName = "";
string  g_inviteStrain   = "";
string  g_inviteQuality  = "";

key     g_pendingSessionObjKey = NULL_KEY;
list    g_availableItems;
integer ITEM_STRIDE = 5;

closeSessListens() {
    if (g_lisSessionMenu)   { llListenRemove(g_lisSessionMenu);   g_lisSessionMenu = 0; }
    if (g_lisSessionInvite) { llListenRemove(g_lisSessionInvite); g_lisSessionInvite = 0; }
    if (g_lisSessionItem)   { llListenRemove(g_lisSessionItem);   g_lisSessionItem = 0; }
}

showSessionMenu() {
    closeSessListens();
    g_lisSessionMenu = llListen(DCHAN_SESSION_MENU, "", g_ownerKey, "");
    string msg = "Spark Session\nHost: " + g_sessionHost + "\nStatus: " + (string)g_inSession;
    llDialog(g_ownerKey, msg, ["Spark It", "Leave", "Close"], DCHAN_SESSION_MENU);
}

showSessionItemMenu() {
    closeSessListens();
    g_lisSessionItem = llListen(DCHAN_SESSION_ITEM, "", g_ownerKey, "");
    list buttons = [];
    integer i;
    for (i = 0; i < llGetListLength(g_availableItems); i += ITEM_STRIDE) {
        string type = llList2String(g_availableItems, i);
        if (type == "joint" || type == "blunt" || type == "spliff") {
            string btn = llList2String(g_availableItems, i+1) + " (" + llList2String(g_availableItems, i+2) + ")";
            if (llListFindList(buttons, [btn]) == -1) buttons += [btn];
        }
    }
    buttons = llList2List(buttons, 0, 10) + ["BACK"];
    llDialog(g_ownerKey, "Pick what to spark for the group:", buttons, DCHAN_SESSION_ITEM);
}

default {
    state_entry() {
        g_ownerKey = llGetOwner();
    }

    link_message(integer sn, integer num, string msg, key id) {
        if (num == CHAN_SESSION) {
            list parts = llParseString2List(msg, ["|"], []);
            string cmd = llList2String(parts, 0);

            if (cmd == "SHOW_SESSION_MENU") {
                g_sessionObjKey = id;
                showSessionMenu();
            }
            else if (cmd == "SESSION_INVITE") {
                // SESSION_INVITE|sessKey|hostName|strain|quality
                g_inviteSessKey = (key)llList2String(parts, 1);
                g_inviteHostName = llList2String(parts, 2);
                g_inviteStrain = llList2String(parts, 3);
                g_inviteQuality = llList2String(parts, 4);
                
                closeSessListens();
                g_lisSessionInvite = llListen(DCHAN_SESSION_INVITE, "", g_ownerKey, "");
                llDialog(g_ownerKey, g_inviteHostName + " invited you to spark " + g_inviteStrain + "!", ["Join!", "No thanks"], DCHAN_SESSION_INVITE);
            }
            else if (cmd == "UPDATE_SESSION_STATE") {
                g_inSession = (integer)llList2String(parts, 1);
                g_sessionHost = llList2String(parts, 2);
            }
            else if (cmd == "INVENTORY_DATA") {
                g_availableItems = llCSV2List(llList2String(parts, 1));
            }
        }
    }

    listen(integer chan, string name, key id, string msg) {
        if (chan == DCHAN_SESSION_MENU) {
            if (msg == "Spark It") {
                llMessageLinked(LINK_SET, CHAN_UI, "GET_INVENTORY_FOR_SESSION", NULL_KEY);
                showSessionItemMenu();
            }
            else if (msg == "Leave") {
                llMessageLinked(LINK_SET, CHAN_COMMS, "SESSION_LEAVE", g_sessionObjKey);
            }
        }
        else if (chan == DCHAN_SESSION_ITEM) {
            if (msg == "BACK") showSessionMenu();
            else {
                // Find matching item in g_availableItems and send TC_SESSION_START via Comms
                llMessageLinked(LINK_SET, CHAN_COMMS, "SESSION_START_PICKED|" + msg, g_sessionObjKey);
            }
        }
        else if (chan == DCHAN_SESSION_INVITE) {
            if (msg == "Join!") {
                llMessageLinked(LINK_SET, CHAN_COMMS, "TC_SESSION_JOIN", g_inviteSessKey);
            }
        }
    }
}
