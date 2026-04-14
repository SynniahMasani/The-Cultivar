// ================================================================
// THE CULTIVAR  -  HUD Pass Script
// Handles nearby-pass and session-turn pass flow to reduce HUD_UI memory.
// ================================================================

integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_SESSION   = 600;

integer DCHAN_PASS_MODE   = -11023;
integer DCHAN_PASS_PLAYER = -11024;
integer DCHAN_PASS_ITEM   = -11025;

integer g_lisPassMode;
integer g_lisPassPlayer;
integer g_lisPassItem;

key     g_ownerKey = NULL_KEY;
integer g_inSession = FALSE;
key     g_sessionObjKey = NULL_KEY;

list g_passItems;
integer ITEM_STRIDE = 5;
key g_passTarget = NULL_KEY;
string g_passTargetName = "";

closePassListens()
{
    if (g_lisPassMode)   { llListenRemove(g_lisPassMode);   g_lisPassMode = 0; }
    if (g_lisPassPlayer) { llListenRemove(g_lisPassPlayer); g_lisPassPlayer = 0; }
    if (g_lisPassItem)   { llListenRemove(g_lisPassItem);   g_lisPassItem = 0; }
}

showNearbyPlayerMenu()
{
    closePassListens();
    list agents = llGetAgentList(AGENT_LIST_PARCEL, []);
    list buttons;
    string menuText = "=== PASS ===\nChoose a nearby player:";
    integer i;
    for (i = 0; i < llGetListLength(agents) && llGetListLength(buttons) < 9; ++i)
    {
        key a = llList2Key(agents, i);
        if (a == g_ownerKey) jump skip;
        string n = llGetDisplayName(a);
        buttons += [llGetSubString(n, 0, 11)];
        menuText += "\n" + n;
        @skip;
    }
    if (llGetListLength(buttons) == 0)
    {
        llOwnerSay("Nobody else nearby to pass to.");
        return;
    }
    buttons += ["Back"];
    g_lisPassPlayer = llListen(DCHAN_PASS_PLAYER, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_PASS_PLAYER);
    llSetTimerEvent(30.0);
}

showPassModeMenu()
{
    closePassListens();
    g_lisPassMode = llListen(DCHAN_PASS_MODE, "", g_ownerKey, "");
    if (g_inSession)
    {
        llDialog(g_ownerKey,
            "=== PASS ===\nChoose pass mode:",
            ["Session Turn", "Nearby Pass", "Close"],
            DCHAN_PASS_MODE);
    }
    else
    {
        llDialog(g_ownerKey,
            "=== PASS ===\nChoose pass mode:",
            ["Nearby Pass", "Close"],
            DCHAN_PASS_MODE);
    }
    llSetTimerEvent(30.0);
}

showPassItemMenu()
{
    closePassListens();
    integer count = llGetListLength(g_passItems) / ITEM_STRIDE;
    if (count == 0)
    {
        llOwnerSay("No passable items available.");
        return;
    }

    list buttons;
    string menuText = "=== PASS ITEM ===\nTo: " + g_passTargetName + "\n";
    integer i;
    for (i = 0; i < count && llGetListLength(buttons) < 9; ++i)
    {
        string strain = llList2String(g_passItems, i * ITEM_STRIDE + 1);
        string quality = llList2String(g_passItems, i * ITEM_STRIDE + 2);
        integer qty = llList2Integer(g_passItems, i * ITEM_STRIDE + 3);
        string label = llGetSubString(strain, 0, 9) + " x" + (string)qty;
        buttons += [label];
        menuText += quality + " " + strain + " x" + (string)qty + "\n";
    }
    buttons += ["Back"];
    g_lisPassItem = llListen(DCHAN_PASS_ITEM, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_PASS_ITEM);
    llSetTimerEvent(30.0);
}

parsePassItems(string rawData)
{
    g_passItems = [];
    if (rawData == "" || rawData == "EMPTY") return;
    list slots = llParseString2List(rawData, ["^"], []);
    list ok = ["joint","blunt","spliff","flower_raw","concentrate",
               "edible_brownie","edible_gummy","edible_drink"];
    integer i;
    for (i = 0; i < llGetListLength(slots); ++i)
    {
        if (llGetListLength(g_passItems) >= 45) return;
        string slot = llList2String(slots, i);
        list f = llParseStringKeepNulls(slot, ["~"], []);
        if (llGetListLength(f) < 5) jump skip;
        string iType = llList2String(f, 0);
        if (llListFindList(ok, [iType]) == -1) jump skip;
        g_passItems += [
            iType,
            llList2String(f, 1),
            llList2String(f, 2),
            (integer)llList2String(f, 3),
            llList2String(f, 4)
        ];
        @skip;
    }
}

default
{
    state_entry()
    {
        g_ownerKey = llGetOwner();
    }

    on_rez(integer s) { llResetScript(); }
    changed(integer c) { if (c & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        closePassListens();
        llSetTimerEvent(0.0);
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (id != g_ownerKey) return;
        closePassListens();
        llSetTimerEvent(0.0);

        if (channel == DCHAN_PASS_MODE)
        {
            if (msg == "Session Turn")
            {
                if (g_sessionObjKey != NULL_KEY)
                    llRegionSayTo(g_sessionObjKey, 0, "TC_PASS_REQUEST|" + (string)g_ownerKey);
                else
                    llOwnerSay("No active session object found.");
                return;
            }
            if (msg == "Nearby Pass")
            {
                showNearbyPlayerMenu();
                return;
            }
            return;
        }

        if (channel == DCHAN_PASS_PLAYER)
        {
            if (msg == "Back") return;
            list agents = llGetAgentList(AGENT_LIST_PARCEL, []);
            integer i;
            for (i = 0; i < llGetListLength(agents); ++i)
            {
                key a = llList2Key(agents, i);
                string n = llGetDisplayName(a);
                if (llGetSubString(n, 0, 11) == msg)
                {
                    g_passTarget = a;
                    g_passTargetName = n;
                    llMessageLinked(LINK_SET, CHAN_INVENTORY,
                        "REQUEST_RAW_INVENTORY|all|ui_pass", NULL_KEY);
                    return;
                }
            }
            llOwnerSay("Couldn't find that player. They may have moved.");
            return;
        }

        if (channel == DCHAN_PASS_ITEM)
        {
            if (msg == "Back")
            {
                showNearbyPlayerMenu();
                return;
            }

            integer count = llGetListLength(g_passItems) / ITEM_STRIDE;
            integer i;
            for (i = 0; i < count; ++i)
            {
                string strain = llList2String(g_passItems, i * ITEM_STRIDE + 1);
                integer qty = llList2Integer(g_passItems, i * ITEM_STRIDE + 3);
                string label = llGetSubString(strain, 0, 9) + " x" + (string)qty;
                if (label == msg)
                {
                    string iType = llList2String(g_passItems, i * ITEM_STRIDE);
                    string quality = llList2String(g_passItems, i * ITEM_STRIDE + 2);
                    string packager = llList2String(g_passItems, i * ITEM_STRIDE + 4);
                    llMessageLinked(LINK_SET, CHAN_COMMS,
                        "PASS_TO_PLAYER|" + (string)g_passTarget + "|" +
                        iType + "|" + strain + "|" + quality + "|1|" + packager,
                        NULL_KEY);
                    llOwnerSay("Passed to " + g_passTargetName + ".");
                    return;
                }
            }
            return;
        }
    }

    link_message(integer sender, integer num, string msg, key id)
    {
        if (num == CHAN_SESSION)
        {
            if (msg == "OPEN_PASS_MENU")
            {
                showPassModeMenu();
                return;
            }
            list p = llParseString2List(msg, ["|"], []);
            if (llList2String(p, 0) == "PASS_RAW_INVENTORY")
            {
                parsePassItems(llList2String(p, 1));
                showPassItemMenu();
                return;
            }
            if (llList2String(p, 0) == "SYNC_SESSION_STATE")
            {
                g_inSession = (integer)llList2String(p, 1);
                g_sessionObjKey = (key)llList2String(p, 2);
                return;
            }
        }
        if (num == CHAN_COMMS)
        {
            list p2 = llParseString2List(msg, ["|"], []);
            if (llList2String(p2, 0) == "RAW_INVENTORY" && llList2String(p2, 3) == "ui_pass")
            {
                parsePassItems(llList2String(p2, 1));
                showPassItemMenu();
            }
        }
    }
}
