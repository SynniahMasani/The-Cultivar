// ================================================================
// THE CULTIVAR  -  HUD UI Script
// Version: 2.0  (complete rewrite  -  replaces broken v1.0)
// Handles: All touch input, dialog menus, button glow states,
//          and display updates.
//
// HUD PRIM STRUCTURE  -  name each prim exactly as shown:
//   Root prim    : HUD background  -  touch opens main menu
//   Link 2       : "btn_smoke"     lights up while smoking
//   Link 3       : "btn_inventory"
//   Link 4       : "btn_grow"
//   Link 5       : "btn_session"   lights up while in a session
//   Link 6       : "btn_pass"
//   Link 7       : "btn_stats"
//   Link 8       : "btn_store"
//
// WHAT WAS BROKEN IN v1.0 AND IS NOW FIXED:
//   1. Smoke flow never triggered animation after item was consumed
//   2. Pass flow had a TODO  -  target player key was dropped
//   3. Session invite "Join!" created a listen but nothing handled it
//   4. setButtonGlow() existed but was never called anywhere
//   5. g_passItemType was reused as temp storage for both smoke
//      and pass, causing collisions if both ran
//   6. Session spark asked for quality tier instead of picking
//      from actual inventory items
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_IDENTITY  = 400;
integer CHAN_ANIMATION = 500;

// ---- Button link numbers ----
integer LINK_BTN_SMOKE     = 2;
integer LINK_BTN_INVENTORY = 3;
integer LINK_BTN_GROW      = 4;
integer LINK_BTN_SESSION   = 5;
integer LINK_BTN_PASS      = 6;
integer LINK_BTN_STATS     = 7;
integer LINK_BTN_STORE     = 8;

// ---- Dialog channels (all negative to avoid chat collision) ----
integer DCHAN_MAIN           = -11000;
integer DCHAN_SMOKE_TYPE     = -11001;
integer DCHAN_ITEM_PICK      = -11002;
integer DCHAN_EDIBLE_TYPE    = -11003;
integer DCHAN_PASS_PLAYER    = -11004;
integer DCHAN_SESSION_MENU   = -11006;
integer DCHAN_SESSION_INVITE = -11007;
integer DCHAN_SESSION_ITEM   = -11008;
integer DCHAN_INVENTORY      = -11009;
integer DCHAN_STATS_MENU     = -11010;
integer DCHAN_BRAND_NAME     = -11011;

// ---- Listener handles ----
integer g_lisMain;
integer g_lisSmokeType;
integer g_lisItemPick;
integer g_lisEdibleType;
integer g_lisPassPlayer;
integer g_lisSessionMenu;
integer g_lisSessionInvite;
integer g_lisSessionItem;
integer g_lisInv;
integer g_lisStatsMenu;
integer g_lisBrandName;

// ---- Owner info ----
key     g_ownerKey  = NULL_KEY;
string  g_ownerName = "";

// ---- Cached from identity script ----
string  g_playerName     = "";
integer g_repScore       = 0;
integer g_totalSmoked    = 0;
string  g_favoriteStrain = "";
string  g_brandName      = "";
string  g_playerTitle    = "Seedling";
string  g_inventoryDisplay = "Loading...";

// ---- Current state ----
integer g_isSmoking     = FALSE;
string  g_smokeStrain   = "";
string  g_smokeQuality  = "";
integer g_inSession     = FALSE;
key     g_sessionObjKey = NULL_KEY;
string  g_sessionHost   = "";

// ---- Pending invite from another player ----
key     g_inviteSessKey  = NULL_KEY;
string  g_inviteHostName = "";
string  g_inviteStrain   = "";
string  g_inviteQuality  = "";

// ---- Flow context: what multi-step sequence are we in?
//   "none" | "smoke" | "pass" | "session_spark"
string  g_flowContext = "none";

// ---- Pending item selection (shared across menu steps) ----
string  g_pendingItemType = "";
string  g_pendingStrain   = "";
string  g_pendingQuality  = "";
string  g_pendingPackager = "";

// ---- Pending pass target ----
key     g_passTarget     = NULL_KEY;
string  g_passTargetName = "";

// ---- Available items populated by inventory response ----
// Stride 5: [itemType, strain, quality, qty, packager]
list    g_availableItems;
integer ITEM_STRIDE = 5;

// ---- Session object waiting for spark selection ----
key     g_pendingSessionObjKey = NULL_KEY;


// ================================================================
//  UTILITY
// ================================================================

closeAllListens()
{
    if (g_lisMain)          { llListenRemove(g_lisMain);          g_lisMain          = 0; }
    if (g_lisSmokeType)     { llListenRemove(g_lisSmokeType);     g_lisSmokeType     = 0; }
    if (g_lisItemPick)      { llListenRemove(g_lisItemPick);      g_lisItemPick      = 0; }
    if (g_lisEdibleType)    { llListenRemove(g_lisEdibleType);    g_lisEdibleType    = 0; }
    if (g_lisPassPlayer)    { llListenRemove(g_lisPassPlayer);    g_lisPassPlayer    = 0; }
    if (g_lisSessionMenu)   { llListenRemove(g_lisSessionMenu);   g_lisSessionMenu   = 0; }
    if (g_lisSessionInvite) { llListenRemove(g_lisSessionInvite); g_lisSessionInvite = 0; }
    if (g_lisSessionItem)   { llListenRemove(g_lisSessionItem);   g_lisSessionItem   = 0; }
    if (g_lisInv)           { llListenRemove(g_lisInv);           g_lisInv           = 0; }
    if (g_lisStatsMenu)     { llListenRemove(g_lisStatsMenu);     g_lisStatsMenu     = 0; }
    if (g_lisBrandName)     { llListenRemove(g_lisBrandName);     g_lisBrandName     = 0; }
}

setButtonGlow(integer link, float glow)
{
    llSetLinkPrimitiveParamsFast(link, [PRIM_GLOW, ALL_SIDES, glow]);
}

refreshAllGlows()
{
    setButtonGlow(LINK_BTN_SMOKE,   g_isSmoking * 0.1);
    setButtonGlow(LINK_BTN_SESSION, g_inSession * 0.1);
    // All other buttons stay dim
    setButtonGlow(LINK_BTN_INVENTORY, 0.0);
    setButtonGlow(LINK_BTN_GROW,      0.0);
    setButtonGlow(LINK_BTN_PASS,      0.0);
    setButtonGlow(LINK_BTN_STATS,     0.0);
    setButtonGlow(LINK_BTN_STORE,     0.0);
}

string qualLabel(string q)
{
    if (q == "mids")   return "Mids ?";
    if (q == "loud")   return "Loud ??";
    if (q == "exotic") return "Exotic ?";
    return "Reggie";
}

// Convert smoke menu button label to inventory item type
string menuToItemType(string sel)
{
    string s = llToLower(sel);
    if (s == "joint")   return "joint";
    if (s == "blunt")   return "blunt";
    if (s == "spliff")  return "spliff";
    if (s == "bowl" || s == "pipe") return "flower_raw";
    if (s == "bong")    return "flower_raw";
    if (s == "dab")     return "concentrate";
    return s;
}

// Parse raw serialized inventory (from REQUEST_RAW_INVENTORY response)
// and populate g_availableItems, optionally filtered by item type prefix
parseItems(string rawData, string filterPrefix)
{
    g_availableItems = [];
    if (rawData == "" || rawData == "EMPTY") return;
    list slots = llParseString2List(rawData, ["^"], []);
    integer i;
    for (i = 0; i < llGetListLength(slots); i++)
    {
        list f = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(f) < 5) jump skip;
        string iType = llList2String(f, 0);
        integer match = (filterPrefix == "" || filterPrefix == "all");
        if (!match)
            match = (iType == filterPrefix ||
                     llSubStringIndex(iType, filterPrefix) == 0);
        if (match)
        {
            g_availableItems += [
                iType,
                llList2String(f, 1),
                llList2String(f, 2),
                (integer)llList2String(f, 3),
                llList2String(f, 4)
            ];
        }
        @skip;
    }
}


// ================================================================
//  MENUS
// ================================================================

showMainMenu()
{
    closeAllListens();
    string line1 = "Not smoking";
    if (g_isSmoking) line1 = "Smoking: " + g_smokeQuality + " " + g_smokeStrain;
    string line2 = "No active session";
    if (g_inSession) line2 = "Session: " + g_sessionHost;

    g_lisMain = llListen(DCHAN_MAIN, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== THE CULTIVAR ===\n" +
        g_playerName + "  ?  Rep: " + (string)g_repScore + "\n" +
        line1 + "\n" + line2,
        ["Smoke", "Inventory", "Grow",
         "Session", "Pass", "Stats",
         "Store", "Close"],
        DCHAN_MAIN);
    llSetTimerEvent(30.0);
}

// SMOKE  -  Step 1: what type?
showSmokeTypeMenu()
{
    closeAllListens();
    g_flowContext = "smoke";
    g_lisSmokeType = llListen(DCHAN_SMOKE_TYPE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== SMOKE ===\nWhat are you smoking?\n\n" +
        "Joint / Blunt / Spliff  -  rolled items\n" +
        "Bowl / Bong  -  flower raw through a piece\n" +
        "Edible  -  brownies, gummies, drinks\n" +
        "Dab  -  concentrate",
        ["Joint", "Blunt", "Spliff",
         "Bowl", "Bong", "Edible",
         "Dab", "Back"],
        DCHAN_SMOKE_TYPE);
    llSetTimerEvent(30.0);
}

showEdibleTypeMenu()
{
    closeAllListens();
    g_lisEdibleType = llListen(DCHAN_EDIBLE_TYPE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== EDIBLE ===\nChoose type:",
        ["Brownie", "Gummies", "Drink", "Back"],
        DCHAN_EDIBLE_TYPE);
    llSetTimerEvent(30.0);
}

// SMOKE  -  Step 2: which strain?  (also used for pass flow)
showItemPickMenu()
{
    closeAllListens();
    integer count = llGetListLength(g_availableItems) / ITEM_STRIDE;
    if (count == 0)
    {
        llOwnerSay("No " + g_pendingItemType +
                   " in your inventory. Check your stash.");
        g_flowContext     = "none";
        g_pendingItemType = "";
        return;
    }

    list   buttons;
    string menuText = "=== PICK " +
                      llToUpper(g_pendingItemType) + " ===\n";
    list qualNames  = ["reggie","mids","loud","exotic"];
    list qualIcons  = ["[R]","[M]","[L]","[E]"];
    integer i;
    for (i = 0; i < count && llGetListLength(buttons) < 9; i++)
    {
        string strain  = llList2String(g_availableItems, i * ITEM_STRIDE + 1);
        string quality = llList2String(g_availableItems, i * ITEM_STRIDE + 2);
        integer qty    = llList2Integer(g_availableItems, i * ITEM_STRIDE + 3);
        integer qi     = llListFindList(qualNames, [quality]);
        string  icon   = llList2String(qualIcons, qi);
        string  label  = llGetSubString(strain, 0, 9) + " x" + (string)qty;
        buttons  += [label];
        menuText += icon + " " + strain + "  x" + (string)qty + "\n";
    }
    buttons += ["Back"];

    g_lisItemPick = llListen(DCHAN_ITEM_PICK, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_ITEM_PICK);
    llSetTimerEvent(30.0);
}

// PASS  -  Step 1: pick a nearby player
showPassPlayerMenu()
{
    closeAllListens();
    list   agents  = llGetAgentList(AGENT_LIST_PARCEL, []);
    list   buttons;
    string menuText = "=== PASS ===\nWho are you passing to?\n\n";
    integer i;
    for (i = 0; i < llGetListLength(agents) &&
                llGetListLength(buttons) < 9; i++)
    {
        key    a = llList2Key(agents, i);
        if (a == g_ownerKey) jump skip_self;
        string n = llGetDisplayName(a);
        buttons  += [llGetSubString(n, 0, 11)];
        menuText += n + "\n";
        @skip_self;
    }
    if (llGetListLength(buttons) == 0)
    {
        llOwnerSay("Nobody else nearby to pass to.");
        g_flowContext = "none";
        return;
    }
    buttons += ["Back"];
    g_lisPassPlayer = llListen(DCHAN_PASS_PLAYER, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_PASS_PLAYER);
    llSetTimerEvent(30.0);
}

// SESSION menu  -  different layout depending on whether in session
showSessionMenu()
{
    closeAllListens();
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
            "=== SESSION ===\nSpark a circle and invite nearby players.\n" +
            "Everyone shares the same smoke.",
            ["Spark Session", "Close"],
            DCHAN_SESSION_MENU);
    }
    llSetTimerEvent(30.0);
}

// SESSION  -  Step 2: pick what to spark (shown after session object rezzes)
showSessionItemMenu()
{
    closeAllListens();
    integer count = llGetListLength(g_availableItems) / ITEM_STRIDE;
    if (count == 0)
    {
        llOwnerSay("Nothing to spark. Roll something first.");
        if (g_pendingSessionObjKey != NULL_KEY)
        {
            llRegionSayTo(g_pendingSessionObjKey, 0, "TC_SESSION_CANCEL");
            g_pendingSessionObjKey = NULL_KEY;
        }
        g_flowContext = "none";
        return;
    }

    list   buttons;
    string menuText = "=== SPARK SESSION ===\n" +
                      "What are you putting in the circle?\n\n";
    integer i;
    for (i = 0; i < count && llGetListLength(buttons) < 9; i++)
    {
        string iType   = llList2String(g_availableItems, i * ITEM_STRIDE);
        string strain  = llList2String(g_availableItems, i * ITEM_STRIDE + 1);
        string quality = llList2String(g_availableItems, i * ITEM_STRIDE + 2);
        integer qty    = llList2Integer(g_availableItems, i * ITEM_STRIDE + 3);

        string typeLabel = iType;
        if (iType == "joint")      typeLabel = "Joint";
        else if (iType == "blunt") typeLabel = "Blunt";
        else if (iType == "spliff") typeLabel = "Spliff";
        else if (iType == "flower_raw") typeLabel = "Flower";

        string label = llGetSubString(quality + " " + strain, 0, 11);
        buttons  += [label];
        menuText += typeLabel + "  " + quality + " " + strain +
                    "  x" + (string)qty + "\n";
    }
    buttons += ["Cancel"];
    g_lisSessionItem = llListen(DCHAN_SESSION_ITEM, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_SESSION_ITEM);
    llSetTimerEvent(30.0);
}

showInventoryMenu()
{
    closeAllListens();
    llMessageLinked(LINK_SET, CHAN_INVENTORY, "REQUEST_INVENTORY", NULL_KEY);
    g_lisInv = llListen(DCHAN_INVENTORY, "", g_ownerKey, "");
    string invMsg = "=== INVENTORY ===\n" + g_inventoryDisplay + "\n\n" +
        "Load Jar   -  touch a weed jar to fill it\n" +
        "Fill Bag   -  touch a bagging table";
    if (llStringLength(invMsg) > 480)
        invMsg = llGetSubString(invMsg, 0, 477) + "...";
    llDialog(g_ownerKey, invMsg, ["Load Jar", "Fill Bag", "Back"], DCHAN_INVENTORY);
    llSetTimerEvent(30.0);
}

showStats()
{
    closeAllListens();
    g_lisStatsMenu = llListen(DCHAN_STATS_MENU, "", g_ownerKey, "");
    string brandInfo = "";
    if (g_brandName != "" && g_brandName != g_playerName)
        brandInfo = "\nBrand: " + g_brandName;
    llDialog(g_ownerKey,
        "=== STATS ===\n" + g_playerName + "\nTitle: " + g_playerTitle + brandInfo,
        ["View Stats", "Achievements", "Set Brand Name", "Close"],
        DCHAN_STATS_MENU);
    llSetTimerEvent(30.0);
}

showBrandNameTextBox()
{
    closeAllListens();
    g_lisBrandName = llListen(DCHAN_BRAND_NAME, "", g_ownerKey, "");
    llTextBox(g_ownerKey,
        "Enter your brand name (max 24 chars):\nAvoid | ~ ^ : characters\n\nCurrent: " +
        g_brandName,
        DCHAN_BRAND_NAME);
    llSetTimerEvent(60.0);
}


// ================================================================
//  SESSION OBJECT REZ
// ================================================================

startSession()
{
    if (llGetInventoryType("TC_SessionObject") != INVENTORY_OBJECT)
    {
        llOwnerSay("[Error] TC_SessionObject not in HUD inventory.");
        return;
    }
    vector pos = llGetPos() + llRot2Fwd(llGetRot()) * 1.2 + <0,0,0.1>;
    llRezObject("TC_SessionObject", pos, ZERO_VECTOR, ZERO_ROTATION, 0);
    g_flowContext = "session_spark";
}


// ================================================================
//  ITEM REMOVAL  -  called once strain/quality confirmed
// ================================================================

executeRemove()
{
    llMessageLinked(LINK_SET, CHAN_INVENTORY,
        "REMOVE_ITEM|" + g_pendingItemType + "|" +
        g_pendingStrain   + "|" +
        g_pendingQuality  + "|1|" +
        g_pendingPackager, NULL_KEY);
}


// ================================================================
//  AFTER REMOVAL SUCCEEDS OR FAILS
// ================================================================

onRemoveSuccess()
{
    if (g_flowContext == "smoke")
    {
        // Start animation
        llMessageLinked(LINK_SET, CHAN_ANIMATION,
            "START_SMOKE_ANIM|" + g_pendingStrain + "|" +
            g_pendingQuality + "|" + g_pendingItemType, NULL_KEY);

        // Log it
        llMessageLinked(LINK_SET, CHAN_IDENTITY,
            "UPDATE_SMOKED|" + g_pendingStrain, NULL_KEY);

        llOwnerSay("? Enjoying " + qualLabel(g_pendingQuality) +
                   " " + g_pendingStrain + ".");

        g_isSmoking    = TRUE;
        g_smokeStrain  = g_pendingStrain;
        g_smokeQuality = g_pendingQuality;
        setButtonGlow(LINK_BTN_SMOKE, 0.1);
    }
    else if (g_flowContext == "pass")
    {
        // Send item to target player
        llMessageLinked(LINK_SET, CHAN_COMMS,
            "PASS_TO_PLAYER|" + (string)g_passTarget + "|" +
            g_pendingItemType + "|" + g_pendingStrain + "|" +
            g_pendingQuality  + "|1|" + g_pendingPackager, NULL_KEY);

        // Give animation
        llMessageLinked(LINK_SET, CHAN_ANIMATION, "PLAY_PASS_GIVE", NULL_KEY);

        llOwnerSay("Passed " + g_pendingQuality + " " +
                   g_pendingStrain + " to " + g_passTargetName + ". ?");
    }

    // Clear flow state
    g_flowContext     = "none";
    g_pendingItemType = "";
    g_pendingStrain   = "";
    g_pendingQuality  = "";
    g_pendingPackager = "";
    g_passTarget      = NULL_KEY;
    g_passTargetName  = "";
}

onRemoveFail()
{
    llOwnerSay("Not enough " + g_pendingItemType + ". Check your inventory.");
    g_flowContext     = "none";
    g_pendingItemType = "";
    g_pendingStrain   = "";
    g_pendingQuality  = "";
}


// ================================================================
//  DEFAULT STATE
// ================================================================

default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llGetDisplayName(g_ownerKey);
        llMessageLinked(LINK_SET, CHAN_IDENTITY, "REQUEST_IDENTITY", NULL_KEY);
        llMessageLinked(LINK_SET, CHAN_INVENTORY, "REQUEST_INVENTORY", NULL_KEY);
        refreshAllGlows();
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer c)          { if (c & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        closeAllListens();
        llSetTimerEvent(0.0);
        // Cancel any orphaned session object
        if (g_flowContext == "session_spark" &&
            g_pendingSessionObjKey != NULL_KEY)
        {
            llRegionSayTo(g_pendingSessionObjKey, 0, "TC_SESSION_CANCEL");
            g_pendingSessionObjKey = NULL_KEY;
        }
        if (g_flowContext != "none") g_flowContext = "none";
    }

    // ----------------------------------------------------------------
    // TOUCH  -  route each named button
    // ----------------------------------------------------------------
    touch_start(integer nd)
    {
        if (llDetectedKey(0) != g_ownerKey) return;
        string primName = llGetLinkName(llDetectedLinkNumber(0));

        if      (primName == "btn_smoke")     showSmokeTypeMenu();
        else if (primName == "btn_inventory") showInventoryMenu();
        else if (primName == "btn_grow")
            llOwnerSay("Touch any plant or pot on your land to check its status.");
        else if (primName == "btn_session")   showSessionMenu();
        else if (primName == "btn_pass")
            { g_flowContext = "pass"; showPassPlayerMenu(); }
        else if (primName == "btn_stats")     showStats();
        else if (primName == "btn_store")
            llLoadURL(g_ownerKey, "The Cultivar Store",
                      "https://marketplace.secondlife.com");
        else showMainMenu();
    }


    // ----------------------------------------------------------------
    // DIALOG RESPONSES
    // ----------------------------------------------------------------
    listen(integer channel, string name, key id, string msg)
    {
        if (id != g_ownerKey) return;
        closeAllListens();
        llSetTimerEvent(0.0);

        // ---- MAIN MENU ----
        if (channel == DCHAN_MAIN)
        {
            if      (msg == "Smoke")     showSmokeTypeMenu();
            else if (msg == "Inventory") showInventoryMenu();
            else if (msg == "Grow")
                llOwnerSay("Touch a plant to check its grow status.");
            else if (msg == "Session") showSessionMenu();
            else if (msg == "Pass")    { g_flowContext = "pass"; showPassPlayerMenu(); }
            else if (msg == "Stats")   showStats();
            else if (msg == "Store")
                llLoadURL(g_ownerKey, "The Cultivar Store",
                          "https://marketplace.secondlife.com");
            // "Close"  -  do nothing
        }

        // ---- SMOKE TYPE ----
        else if (channel == DCHAN_SMOKE_TYPE)
        {
            if (msg == "Back") { g_flowContext = "none"; showMainMenu(); return; }
            if (msg == "Edible") { showEdibleTypeMenu(); return; }

            g_pendingItemType = menuToItemType(msg);
            // Request matching inventory  -  response handled in link_message
            llMessageLinked(LINK_SET, CHAN_INVENTORY,
                "REQUEST_RAW_INVENTORY|" + g_pendingItemType + "|ui_smoke",
                NULL_KEY);
        }

        // ---- EDIBLE TYPE ----
        else if (channel == DCHAN_EDIBLE_TYPE)
        {
            if (msg == "Back") { showSmokeTypeMenu(); return; }
            if (msg == "Brownie")  g_pendingItemType = "edible_brownie";
            else if (msg == "Gummies") g_pendingItemType = "edible_gummy";
            else if (msg == "Drink")   g_pendingItemType = "edible_drink";
            llMessageLinked(LINK_SET, CHAN_INVENTORY,
                "REQUEST_RAW_INVENTORY|" + g_pendingItemType + "|ui_smoke",
                NULL_KEY);
        }

        // ---- ITEM PICKER (smoke or pass) ----
        else if (channel == DCHAN_ITEM_PICK)
        {
            if (msg == "Back")
            {
                if (g_flowContext == "pass") showPassPlayerMenu();
                else showSmokeTypeMenu();
                return;
            }
            // Match button label back to full item data
            integer count = llGetListLength(g_availableItems) / ITEM_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string strain  = llList2String(g_availableItems, i * ITEM_STRIDE + 1);
                string quality = llList2String(g_availableItems, i * ITEM_STRIDE + 2);
                integer qty    = llList2Integer(g_availableItems, i * ITEM_STRIDE + 3);
                string  packager = llList2String(g_availableItems, i * ITEM_STRIDE + 4);
                string  label  = llGetSubString(strain, 0, 9) + " x" + (string)qty;
                if (label == msg)
                {
                    g_pendingStrain   = strain;
                    g_pendingQuality  = quality;
                    g_pendingPackager = packager;
                    executeRemove();
                    return;
                }
            }
            // No match (label collision)  -  redisplay
            showItemPickMenu();
        }

        // ---- PASS PLAYER SELECTION ----
        else if (channel == DCHAN_PASS_PLAYER)
        {
            if (msg == "Back") { g_flowContext = "none"; showMainMenu(); return; }
            // Resolve truncated name back to full key
            list agents = llGetAgentList(AGENT_LIST_PARCEL, []);
            integer i;
            for (i = 0; i < llGetListLength(agents); i++)
            {
                key    a = llList2Key(agents, i);
                string n = llGetDisplayName(a);
                if (llGetSubString(n, 0, 11) == msg)
                {
                    g_passTarget     = a;
                    g_passTargetName = n;
                    jump found_target;
                }
            }
            llOwnerSay("Couldn't find that player. They may have moved.");
            g_flowContext = "none";
            return;
            @found_target;

            // Now pick what to pass  -  request all passable inventory types
            llMessageLinked(LINK_SET, CHAN_INVENTORY,
                "REQUEST_RAW_INVENTORY|all|ui_pass", NULL_KEY);
        }

        // ---- SESSION MENU ----
        else if (channel == DCHAN_SESSION_MENU)
        {
            if (msg == "Spark Session")
            {
                startSession();
                // Item menu shown when SESSION_OBJECT_READY comes back
            }
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
            // "Close"  -  do nothing
        }

        // ---- SESSION ITEM SELECTION (what to spark) ----
        else if (channel == DCHAN_SESSION_ITEM)
        {
            if (msg == "Cancel")
            {
                if (g_pendingSessionObjKey != NULL_KEY)
                    llRegionSayTo(g_pendingSessionObjKey, 0, "TC_SESSION_CANCEL");
                g_pendingSessionObjKey = NULL_KEY;
                g_flowContext = "none";
                return;
            }
            // Match label to item
            integer count = llGetListLength(g_availableItems) / ITEM_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string quality = llList2String(g_availableItems, i * ITEM_STRIDE + 2);
                string strain  = llList2String(g_availableItems, i * ITEM_STRIDE + 1);
                string label   = llGetSubString(quality + " " + strain, 0, 11);
                if (label == msg)
                {
                    // Fire TC_SESSION_START to the session object
                    string hudChanStr = llLinksetDataRead("hud_private_chan");
                    integer hudChan   = (integer)hudChanStr;
                    llRegionSayTo(g_pendingSessionObjKey, 0,
                        "TC_SESSION_START|" + (string)g_ownerKey + "|" +
                        (string)hudChan + "|" + g_ownerName + "|" +
                        strain + "|" + quality + "|" + g_brandName);
                    llMessageLinked(LINK_SET, CHAN_COMMS,
                        "START_SESSION|" + (string)g_pendingSessionObjKey,
                        NULL_KEY);
                    g_pendingSessionObjKey = NULL_KEY;
                    g_flowContext = "none";
                    return;
                }
            }
        }

        // ---- SESSION INVITE RESPONSE (from another player's session) ----
        else if (channel == DCHAN_SESSION_INVITE)
        {
            if (msg == "Join!")
            {
                // Tell Comms to broadcast our join
                llMessageLinked(LINK_SET, CHAN_COMMS,
                    "JOIN_SESSION|" + (string)g_inviteSessKey + "|" +
                    g_inviteHostName, NULL_KEY);
            }
            // "No Thanks"  -  just clear state
            g_inviteSessKey  = NULL_KEY;
            g_inviteHostName = "";
            g_inviteStrain   = "";
            g_inviteQuality  = "";
        }

        // ---- INVENTORY MENU ----
        else if (channel == DCHAN_INVENTORY)
        {
            if (msg == "Back") showMainMenu();
            else if (msg == "Load Jar")
                llOwnerSay("Touch your weed jar to load flower from your inventory.");
            else if (msg == "Fill Bag")
                llOwnerSay("Touch your bagging table to package flower into bags.");
        }

        // ---- STATS SUB-MENU ----
        else if (channel == DCHAN_STATS_MENU)
        {
            if (msg == "View Stats")
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "REQUEST_STATS_CARD", NULL_KEY);
            else if (msg == "Achievements")
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "REQUEST_ACHIEVEMENTS", NULL_KEY);
            else if (msg == "Set Brand Name")
                showBrandNameTextBox();
            // "Close"  -  do nothing
        }

        // ---- BRAND NAME TEXTBOX RESPONSE ----
        else if (channel == DCHAN_BRAND_NAME)
        {
            string cleaned = llStringTrim(msg, STRING_TRIM);
            if (llStringLength(cleaned) > 24) cleaned = llGetSubString(cleaned, 0, 23);
            cleaned = llDumpList2String(
                llParseString2List(cleaned, ["|","~","^",":"], []), "");
            if (cleaned == "") { llOwnerSay("Brand name not changed (invalid input)."); return; }
            g_brandName = cleaned;
            llMessageLinked(LINK_SET, CHAN_IDENTITY,
                "SET_BRAND_NAME|" + g_brandName, NULL_KEY);
            llOwnerSay("Brand name set to: " + g_brandName);
        }
    }


    // ----------------------------------------------------------------
    // LINK MESSAGES  -  updates from sibling scripts
    // ----------------------------------------------------------------
    link_message(integer sender, integer num, string msg, key id)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- Messages addressed to CHAN_UI ----
        if (num == CHAN_UI)
        {
            // Identity data  -  cache for menus
            // Payload format: IDENTITY_DATA|name|uuid|smoked|grown|passed|sold|fav|rep|joinDate
            if (cmd == "IDENTITY_DATA")
            {
                // parts[0]=cmd, parts[1]=name, parts[2]=uuid, parts[3]=smoked,
                // parts[4]=grown, parts[5]=passed, parts[6]=sold, parts[7]=fav,
                // parts[8]=rep, parts[9]=joinDate
                g_playerName     = llList2String(parts, 1);
                g_totalSmoked    = (integer)llList2String(parts, 3);
                g_favoriteStrain = llList2String(parts, 7);
                g_repScore       = (integer)llList2String(parts, 8);
                g_brandName      = llList2String(parts, 10);
                if (llGetListLength(parts) > 14)
                    g_playerTitle = llList2String(parts, 14);
            }

            // Inventory summary string for display
            else if (cmd == "UPDATE_INVENTORY_DISPLAY")
                g_inventoryDisplay = llList2String(parts, 1);

            // Stats card  -  output to owner chat
            else if (cmd == "SHOW_STATS")
                llOwnerSay(llList2String(parts, 1));

            // Item consumed successfully  -  trigger animation (HUD-menu smoke flow)
            else if (cmd == "ITEM_USED")
                onRemoveSuccess();

            // Item consumption failed
            else if (cmd == "ITEM_FAILED")
                onRemoveFail();

            // World object (jar, weed piece, session) fired TC_SMOKED  - 
            // Comms already started the animation, we just update state + glow
            else if (cmd == "SMOKE_STARTED")
            {
                g_isSmoking    = TRUE;
                g_smokeStrain  = llList2String(parts, 1);
                g_smokeQuality = llList2String(parts, 2);
                setButtonGlow(LINK_BTN_SMOKE, 0.1);
            }

            // Smoke animation stopped (duration expired)
            else if (cmd == "SMOKE_STOPPED")
            {
                g_isSmoking    = FALSE;
                g_smokeStrain  = "";
                g_smokeQuality = "";
                setButtonGlow(LINK_BTN_SMOKE, 0.0);
            }

            // ---- SESSION EVENTS ----

            // Session object rezzed  -  show item picker
            else if (cmd == "SESSION_OBJECT_READY")
            {
                g_pendingSessionObjKey = (key)llList2String(parts, 1);
                // Request spark-able inventory (joints, blunts, spliffs, flower)
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "REQUEST_RAW_INVENTORY|all|ui_session", NULL_KEY);
            }

            // We joined someone else's session as a participant
            else if (cmd == "SESSION_JOINED")
            {
                g_sessionHost   = llList2String(parts, 1);
                g_sessionObjKey = (key)llList2String(parts, 2);
                g_inSession     = TRUE;
                setButtonGlow(LINK_BTN_SESSION, 0.1);
                llOwnerSay("Joined " + g_sessionHost + "'s circle. ?");
            }

            // We started a session as host
            else if (cmd == "SESSION_STARTED")
            {
                g_inSession     = TRUE;
                g_sessionHost   = g_ownerName;
                g_sessionObjKey = (key)llList2String(parts, 1);
                setButtonGlow(LINK_BTN_SESSION, 0.1);
            }

            // Session ended
            else if (cmd == "SESSION_ENDED")
            {
                g_inSession     = FALSE;
                g_sessionObjKey = NULL_KEY;
                g_sessionHost   = "";
                g_isSmoking     = FALSE;
                g_smokeStrain   = "";
                g_smokeQuality  = "";
                refreshAllGlows();
                llOwnerSay("Session ended.");
            }

            // Someone joined our circle
            else if (cmd == "SESSION_MEMBER_JOIN")
                llOwnerSay(llList2String(parts, 1) + " joined the circle.");

            // Someone left our circle
            else if (cmd == "SESSION_MEMBER_LEAVE")
                llOwnerSay(llList2String(parts, 1) + " left the circle.");

            // Another player's session is inviting us
            else if (cmd == "SHOW_SESSION_INVITE")
            {
                if (g_inSession) return; // already in one
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
            }

            // We received a pass from another player
            else if (cmd == "PASS_RECEIVED_NOTIFY")
            {
                string fromName = llList2String(parts, 1);
                string strain   = llList2String(parts, 2);
                string quality  = llList2String(parts, 3);
                llOwnerSay(fromName + " passed you " + quality +
                           " " + strain + ". ?");
            }

            // Cypher mode: it's our turn with X seconds remaining
            // YOUR_TURN_COUNTDOWN|secondsRemaining|strain
            else if (cmd == "YOUR_TURN_COUNTDOWN")
            {
                integer remaining = (integer)llList2String(parts, 1);
                string  strain    = llList2String(parts, 2);
                llOwnerSay("? " + strain + "  -  " + (string)remaining + "s remaining!");
            }

            // Cypher mode toggled on/off
            // CYPHER_MODE_CHANGE|active|turnSeconds
            else if (cmd == "CYPHER_MODE_CHANGE")
            {
                if (llList2String(parts, 1) == "1")
                    llOwnerSay("? Cypher mode ON  -  " +
                        llList2String(parts, 2) + "s per turn. Pass it quick!");
                else
                    llOwnerSay("Cypher mode OFF  -  back to free flow.");
            }

        }

        // ---- RAW_INVENTORY data coming back via CHAN_COMMS ----
        // Comms relays inventory responses  -  we filter by the reqKey tag
        else if (num == CHAN_COMMS && cmd == "RAW_INVENTORY")
        {
            string rawData = llList2String(parts, 1);
            // filterType is parts[2], reqKey is parts[3]
            string reqKey  = llList2String(parts, 3);

            // Only handle requests we sent
            if (llSubStringIndex(reqKey, "ui_") != 0) return;

            if (reqKey == "ui_smoke")
            {
                parseItems(rawData, g_pendingItemType);
                showItemPickMenu();
            }
            else if (reqKey == "ui_pass")
            {
                // Show all items that make sense to pass
                parseItems(rawData, "");
                list passable;
                list ok = ["joint","blunt","spliff","flower_raw",
                           "concentrate","edible_brownie",
                           "edible_gummy","edible_drink"];
                integer len = llGetListLength(g_availableItems) / ITEM_STRIDE;
                integer i;
                for (i = 0; i < len; i++)
                {
                    string iType = llList2String(g_availableItems,
                                                 i * ITEM_STRIDE);
                    if (llListFindList(ok, [iType]) != -1)
                        passable += llList2List(g_availableItems,
                            i * ITEM_STRIDE,
                            i * ITEM_STRIDE + ITEM_STRIDE - 1);
                }
                g_availableItems = passable;
                // Re-set pending item type to first available type for picker
                if (llGetListLength(g_availableItems) > 0)
                    g_pendingItemType = llList2String(g_availableItems, 0);
                showItemPickMenu();
            }
            else if (reqKey == "ui_session")
            {
                // Filter to spark-able items
                list sparkTypes = ["joint","blunt","spliff","flower_raw"];
                list parsed;
                list slots = llParseString2List(rawData, ["^"], []);
                integer i;
                for (i = 0; i < llGetListLength(slots); i++)
                {
                    list f = llParseString2List(llList2String(slots, i), ["~"], []);
                    if (llGetListLength(f) < 5) jump skip_s;
                    string iType = llList2String(f, 0);
                    if (llListFindList(sparkTypes, [iType]) != -1)
                        parsed += [iType,
                            llList2String(f, 1),
                            llList2String(f, 2),
                            (integer)llList2String(f, 3),
                            llList2String(f, 4)];
                    @skip_s;
                }
                g_availableItems = parsed;
                if (g_pendingSessionObjKey != NULL_KEY)
                    showSessionItemMenu();
            }
        }
    }
}
