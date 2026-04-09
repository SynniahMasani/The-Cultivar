// ================================================================
// THE CULTIVAR  -  HUD Session UI Script
// Version: 1.5
// Handles: Session menu, session invite dialog, and session spark item
//          picker. Extracted from HUD_UI to reduce baseline memory
//          pressure in the main UI script.
//
// 1.5 change:
//   Stop using the truncated dialog label as the selection key.
//   Session spark buttons now use stable indexed labels so the chosen
//   inventory row cannot collide with another item and accidentally
//   start the wrong smoke type.
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_SESSION   = 600;

integer DCHAN_SESSION_MENU   = -11006;
integer DCHAN_SESSION_INVITE = -11007;
integer DCHAN_SESSION_ITEM   = -11008;

integer g_lisSessionMenu;
integer g_lisSessionInvite;
integer g_lisSessionItem;

key     g_ownerKey = NULL_KEY;

integer g_inSession     = FALSE;
key     g_sessionObjKey = NULL_KEY;
string  g_sessionHost   = "";

key     g_inviteSessKey  = NULL_KEY;
string  g_inviteHostName = "";
string  g_inviteStrain   = "";
string  g_inviteQuality  = "";

list    g_availableItems;
integer ITEM_STRIDE = 5;

key     g_pendingSessionObjKey = NULL_KEY;
list    g_sessionButtonMap;

string typePrefix(string iType)
{
    if (iType == "joint")  return "J";
    if (iType == "blunt")  return "B";
    if (iType == "spliff") return "S";
    return "F";
}

string typeLabel(string iType)
{
    if (iType == "joint")           return "Joint";
    if (iType == "blunt")           return "Blunt";
    if (iType == "spliff")          return "Spliff";
    if (iType == "flower_raw")      return "Flower";
    return iType;
}

closeSessionListens()
{
    if (g_lisSessionMenu)   { llListenRemove(g_lisSessionMenu);   g_lisSessionMenu   = 0; }
    if (g_lisSessionInvite) { llListenRemove(g_lisSessionInvite); g_lisSessionInvite = 0; }
    if (g_lisSessionItem)   { llListenRemove(g_lisSessionItem);   g_lisSessionItem   = 0; }
}

showSessionMenu()
{
    closeSessionListens();
    g_lisSessionMenu = llListen(DCHAN_SESSION_MENU, "", g_ownerKey, "");
    if (g_inSession)
    {
        llDialog(g_ownerKey,
            "=== SESSION ===\n" +
            "Host: " + g_sessionHost,
            ["Pass It", "Session Info", "End Session", "Close"],
            DCHAN_SESSION_MENU);
    }
    else
    {
        llDialog(g_ownerKey,
            "=== SESSION ===\nSpark a smoke sesh and invite nearby homies.\n" +
            "Everyone shares the same smoke.",
            ["Spark Session", "Close"],
            DCHAN_SESSION_MENU);
    }
    llSetTimerEvent(30.0);
}

showSessionItemMenu()
{
    closeSessionListens();
    g_sessionButtonMap = [];

    integer count = llGetListLength(g_availableItems) / ITEM_STRIDE;
    if (count == 0)
    {
        llOwnerSay("Nothing to spark. Roll something first.");
        if (g_pendingSessionObjKey != NULL_KEY)
        {
            llRegionSayTo(g_pendingSessionObjKey, 0, "TC_SESSION_CANCEL");
            g_pendingSessionObjKey = NULL_KEY;
        }
        g_availableItems = [];
        return;
    }

    list   buttons;
    string menuText = "=== SPARK SESSION ===\n" +
                      "What are you putting in the circle?\n\n";
    integer i;
    integer shown = 0;
    for (i = 0; i < count && shown < 9; i++)
    {
        string iType   = llList2String(g_availableItems, i * ITEM_STRIDE);
        string strain  = llList2String(g_availableItems, i * ITEM_STRIDE + 1);
        string quality = llList2String(g_availableItems, i * ITEM_STRIDE + 2);
        integer qty    = llList2Integer(g_availableItems, i * ITEM_STRIDE + 3);

        string button = typePrefix(iType) + (string)(shown + 1);
        buttons += [button];
        g_sessionButtonMap += [button, i];

        menuText += button + "  " + typeLabel(iType) + "  " + quality + " " + strain +
                    "  x" + (string)qty + "\n";
        shown++;
    }
    buttons += ["Cancel"];
    g_lisSessionItem = llListen(DCHAN_SESSION_ITEM, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_SESSION_ITEM);
    llSetTimerEvent(30.0);
}

default
{
    state_entry()
    {
        g_ownerKey = llGetOwner();
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer c)          { if (c & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        closeSessionListens();
        llSetTimerEvent(0.0);
        if (g_pendingSessionObjKey != NULL_KEY)
        {
            llRegionSayTo(g_pendingSessionObjKey, 0, "TC_SESSION_CANCEL");
            g_pendingSessionObjKey = NULL_KEY;
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (id != g_ownerKey) return;
        closeSessionListens();
        llSetTimerEvent(0.0);

        if (channel == DCHAN_SESSION_MENU)
        {
            if (msg == "Spark Session")
                llMessageLinked(LINK_SET, CHAN_SESSION, "START_SESSION_FLOW", NULL_KEY);
            else if (msg == "Pass It")
            {
                if (g_sessionObjKey != NULL_KEY)
                    llRegionSayTo(g_sessionObjKey, 0,
                        "TC_PASS_REQUEST|" + (string)g_ownerKey);
                else
                    llOwnerSay("No active session object found.");
            }
            else if (msg == "Session Info")
                llOwnerSay("Session hosted by: " + g_sessionHost);
            else if (msg == "End Session")
                llMessageLinked(LINK_SET, CHAN_COMMS, "LEAVE_SESSION", NULL_KEY);
        }
        else if (channel == DCHAN_SESSION_ITEM)
        {
            if (msg == "Cancel")
            {
                if (g_pendingSessionObjKey != NULL_KEY)
                    llRegionSayTo(g_pendingSessionObjKey, 0, "TC_SESSION_CANCEL");
                g_pendingSessionObjKey = NULL_KEY;
                g_availableItems = [];
                g_sessionButtonMap = [];
                return;
            }

            integer mapIdx = llListFindList(g_sessionButtonMap, [msg]);
            if (mapIdx != -1)
            {
                integer i = llList2Integer(g_sessionButtonMap, mapIdx + 1);
                string iType   = llList2String(g_availableItems, i * ITEM_STRIDE);
                string quality = llList2String(g_availableItems, i * ITEM_STRIDE + 2);
                string strain  = llList2String(g_availableItems, i * ITEM_STRIDE + 1);

                string hudChanStr = llLinksetDataRead("hud_private_chan");
                integer hudChan   = (integer)hudChanStr;
                string ownerName  = llGetDisplayName(g_ownerKey);
                string brandName  = llLinksetDataRead("id_brand");

                llRegionSayTo(g_pendingSessionObjKey, 0,
                    "TC_SESSION_START|" + (string)g_ownerKey + "|" +
                    (string)hudChan + "|" + ownerName + "|" +
                    iType + "|" + strain + "|" + quality + "|" + brandName);
                llMessageLinked(LINK_SET, CHAN_COMMS,
                    "START_SESSION|" + (string)g_pendingSessionObjKey,
                    NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_COMMS,
                    "TC_SMOKE_START|" + iType + "|" + quality + "|" + strain,
                    NULL_KEY);
                g_pendingSessionObjKey = NULL_KEY;
                g_availableItems       = [];
                g_sessionButtonMap     = [];
                return;
            }
        }
        else if (channel == DCHAN_SESSION_INVITE)
        {
            if (msg == "Join!")
            {
                llMessageLinked(LINK_SET, CHAN_COMMS,
                    "JOIN_SESSION|" + (string)g_inviteSessKey + "|" +
                    g_inviteHostName, NULL_KEY);
            }
            g_inviteSessKey  = NULL_KEY;
            g_inviteHostName = "";
            g_inviteStrain   = "";
            g_inviteQuality  = "";
        }
    }

    link_message(integer sender, integer num, string msg, key id)
    {
        if (num != CHAN_SESSION) return;

        if (msg == "OPEN_SESSION_MENU")
        {
            showSessionMenu();
            return;
        }
        if (msg == "START_SESSION_FLOW")
        {
            if (llGetInventoryType("TC_SessionObject") != INVENTORY_OBJECT)
            {
                llOwnerSay("[Error] TC_SessionObject not in HUD inventory.");
                return;
            }
            llMessageLinked(LINK_SET, CHAN_COMMS, "ARM_SESSION_REZ", NULL_KEY);
            vector pos = llGetPos() + llRot2Fwd(llGetRot()) * 1.2 + <0,0,0.1>;
            llRezObject("TC_SessionObject", pos, ZERO_VECTOR, ZERO_ROTATION, 0);
            return;
        }

        list parts = llParseString2List(msg, ["|"], []);
        string cmd = llList2String(parts, 0);

        if (cmd == "SYNC_SESSION_STATE")
        {
            g_inSession     = (integer)llList2String(parts, 1);
            g_sessionObjKey = (key)llList2String(parts, 2);
            g_sessionHost   = llList2String(parts, 3);
        }
        else if (cmd == "SESSION_OBJECT_READY")
        {
            g_pendingSessionObjKey = (key)llList2String(parts, 1);
            llMessageLinked(LINK_SET, CHAN_INVENTORY,
                "REQUEST_RAW_INVENTORY|all|ui_session", NULL_KEY);
        }
        else if (cmd == "SESSION_INVITE")
        {
            if (g_inSession) return;
            g_inviteHostName = llList2String(parts, 1);
            g_inviteSessKey  = (key)llList2String(parts, 2);
            g_inviteStrain   = llList2String(parts, 3);
            g_inviteQuality  = llList2String(parts, 4);
            string inviteBrand = llList2String(parts, 5);

            if (g_lisSessionInvite) llListenRemove(g_lisSessionInvite);
            g_lisSessionInvite = llListen(DCHAN_SESSION_INVITE, "", g_ownerKey, "");
            string brandDisplay = g_inviteHostName;
            if (inviteBrand != "" && inviteBrand != g_inviteHostName)
                brandDisplay = inviteBrand + " (" + g_inviteHostName + ")";
            llDialog(g_ownerKey,
                "? " + brandDisplay + " is sparking a session!\n" +
                g_inviteQuality + " " + g_inviteStrain + "\nJoin the circle?",
                ["Join!", "No Thanks"],
                DCHAN_SESSION_INVITE);
            llSetTimerEvent(30.0);
        }
        else if (cmd == "SESSION_RAW_INVENTORY")
        {
            string rawData = llList2String(parts, 1);
            list sparkTypes = ["joint","blunt","spliff","flower_raw"];
            list parsed;
            list slots = llParseString2List(rawData, ["^"], []);
            integer n = llGetListLength(slots);
            integer i;
            for (i = 0; i < n; i++)
            {
                string slot = llList2String(slots, i);

                integer t1 = llSubStringIndex(slot, "~");
                if (t1 < 0) jump skip_s;
                string iType = llGetSubString(slot, 0, t1 - 1);
                if (llListFindList(sparkTypes, [iType]) == -1) jump skip_s;

                slot = llDeleteSubString(slot, 0, t1);

                integer t2 = llSubStringIndex(slot, "~");
                if (t2 < 0) jump skip_s;
                string strain = llGetSubString(slot, 0, t2 - 1);
                slot = llDeleteSubString(slot, 0, t2);

                integer t3 = llSubStringIndex(slot, "~");
                if (t3 < 0) jump skip_s;
                string quality = llGetSubString(slot, 0, t3 - 1);
                slot = llDeleteSubString(slot, 0, t3);

                integer t4 = llSubStringIndex(slot, "~");
                if (t4 < 0) jump skip_s;
                string qty      = llGetSubString(slot, 0, t4 - 1);
                string packager = llDeleteSubString(slot, 0, t4);

                parsed += [iType, strain, quality, (integer)qty, packager];
                @skip_s;
            }
            g_availableItems = parsed;
            if (g_pendingSessionObjKey != NULL_KEY)
                showSessionItemMenu();
        }
    }
}
