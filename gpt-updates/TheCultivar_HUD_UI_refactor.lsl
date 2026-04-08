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
integer CHAN_SESSION   = 600;

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
integer DCHAN_INVENTORY      = -11009;
integer DCHAN_STATS_MENU     = -11010;
integer DCHAN_BRAND_NAME     = -11011;
integer DCHAN_SMOKE_ACTIVE   = -11020;
integer DCHAN_SMOKE_RESUME   = -11021;

// ---- Listener handles ----
integer g_lisMain;
integer g_lisSmokeType;
integer g_lisItemPick;
integer g_lisEdibleType;
integer g_lisPassPlayer;
integer g_lisInv;
integer g_lisStatsMenu;
integer g_lisBrandName;
integer g_lisSmokeActive;
integer g_lisSmokeResume;

// ---- Resume dialog state (set when offering Resume/Start Fresh) ----
integer g_pendingResumeSecs = 0;

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
integer g_isSmoking          = FALSE;
string  g_smokeStrain        = "";
string  g_smokeQuality       = "";
integer g_smokeTimeRemaining = 0;
integer g_inSession     = FALSE;
key     g_sessionObjKey = NULL_KEY;
string  g_sessionHost   = "";

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

// ---- Attach-time hydration tracking ----
// HUD_Identity and HUD_Inventory broadcast IDENTITY_DATA and
// UPDATE_INVENTORY_DISPLAY automatically from their own state_entry
// and on_rez handlers. We rely on those sibling startup broadcasts as
// the PRIMARY attach hydration path so we don't have to fire duplicate
// REQUEST_IDENTITY / REQUEST_INVENTORY messages on every HUD attach
// (which used to race the sibling broadcasts and cause double
// hydration). The fallback timer below only re-requests data that
// hasn't arrived within HYDRATION_FALLBACK_SEC.
integer g_hydratedIdentity         = FALSE;
integer g_hydratedInventory        = FALSE;
integer g_hydrationFallbackPending = FALSE;
float   HYDRATION_FALLBACK_SEC     = 3.0;


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
    if (g_lisInv)           { llListenRemove(g_lisInv);           g_lisInv           = 0; }
    if (g_lisStatsMenu)     { llListenRemove(g_lisStatsMenu);     g_lisStatsMenu     = 0; }
    if (g_lisBrandName)     { llListenRemove(g_lisBrandName);     g_lisBrandName     = 0; }
    if (g_lisSmokeActive)   { llListenRemove(g_lisSmokeActive);   g_lisSmokeActive   = 0; }
    if (g_lisSmokeResume)   { llListenRemove(g_lisSmokeResume);   g_lisSmokeResume   = 0; }
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

// Re-request only the hydration payloads that didn't arrive via the
// sibling startup broadcasts. Called from the timer fallback and
// inline from touch_start so a dialog timer overwriting the fallback
// timer can't strand us with empty identity/inventory caches.
runHydrationFallback()
{
    g_hydrationFallbackPending = FALSE;
    llSetTimerEvent(0.0);
    if (!g_hydratedIdentity)
        llMessageLinked(LINK_SET, CHAN_IDENTITY,  "REQUEST_IDENTITY",  NULL_KEY);
    if (!g_hydratedInventory)
        llMessageLinked(LINK_SET, CHAN_INVENTORY, "REQUEST_INVENTORY", NULL_KEY);
}

string qualLabel(string q)
{
    if (q == "mids")   return "Mid Pack";
    if (q == "loud")   return "Loud Pack";
    if (q == "exotic") return "Exotic";
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
// and populate g_availableItems, optionally filtered by item type prefix.
//
// Hot path: called on every smoke/pass flow right before showing the
// item-pick dialog, so it has to be cheap. The previous implementation
// called llParseString2List once per slot to break the ~-delimited
// fields, which meant N+1 list allocations per refresh and was the
// dominant heap-churn source feeding the Stack-Heap Collision on the
// smoke flow. This version allocates ONE list (the slots split) and
// then walks each slot via llSubStringIndex / llGetSubString, which
// are allocation-free string ops. It also checks the filter BEFORE
// extracting the remaining fields, so non-matching slots skip four
// llGetSubString calls instead of still running a full inner parse.
parseItems(string rawData, string filterPrefix)
{
    g_availableItems = [];
    if (rawData == "" || rawData == "EMPTY") return;
    list slots = llParseString2List(rawData, ["^"], []);
    integer n   = llGetListLength(slots);
    integer all = (filterPrefix == "" || filterPrefix == "all");
    integer i;
    for (i = 0; i < n; i++)
    {
        string slot = llList2String(slots, i);

        // Extract iType (everything up to first ~).
        integer t1 = llSubStringIndex(slot, "~");
        if (t1 < 0) jump skip;
        string iType = llGetSubString(slot, 0, t1 - 1);

        // Filter BEFORE parsing the rest. This is the big win for
        // type-filtered flows (e.g. "joint") where most inventory
        // slots don't match and we can skip all remaining work.
        integer match = all;
        if (!match)
            match = (iType == filterPrefix ||
                     llSubStringIndex(iType, filterPrefix) == 0);
        if (!match) jump skip;

        // Walk the remaining four fields. Reuse `slot` as a shrinking
        // cursor so we don't hold multiple intermediate substrings.
        slot = llDeleteSubString(slot, 0, t1);

        integer t2 = llSubStringIndex(slot, "~");
        if (t2 < 0) jump skip;
        string strain = llGetSubString(slot, 0, t2 - 1);
        slot = llDeleteSubString(slot, 0, t2);

        integer t3 = llSubStringIndex(slot, "~");
        if (t3 < 0) jump skip;
        string quality = llGetSubString(slot, 0, t3 - 1);
        slot = llDeleteSubString(slot, 0, t3);

        integer t4 = llSubStringIndex(slot, "~");
        if (t4 < 0) jump skip;
        string qty      = llGetSubString(slot, 0, t4 - 1);
        string packager = llDeleteSubString(slot, 0, t4);

        g_availableItems += [iType, strain, quality, (integer)qty, packager];
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
        g_playerName + " Current Rep: " + (string)g_repScore + "\n" +
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

// ----------------------------------------------------------------
// Shown when the player picks a smokeable for which they already
// have a paused (put-out) session saved with time remaining.
// Lets them resume the old one (no new item consumed) or start
// a fresh one (consumes another from inventory and discards the
// saved pause). Uses g_pendingItemType/Strain/Quality as context.
// ----------------------------------------------------------------
showSmokeResumeMenu(integer remainingSecs)
{
    closeAllListens();
    g_pendingResumeSecs = remainingSecs;
    integer mins = remainingSecs / 60;
    string timeStr;
    if (mins > 0) timeStr = "~" + (string)mins + " min left";
    else          timeStr = (string)remainingSecs + "s left";
    g_lisSmokeResume = llListen(DCHAN_SMOKE_RESUME, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== RESUME ===\nYou already put out a " +
        g_pendingQuality + " " + g_pendingStrain + " " +
        g_pendingItemType + ".\n" + timeStr +
        "\n\nResume that one or light a fresh one?",
        ["Resume", "Start Fresh", "Cancel"],
        DCHAN_SMOKE_RESUME);
    llSetTimerEvent(30.0);
}

// Active smoke HUD menu  -  shown when already smoking and btn_smoke is touched
showActiveSmokeMenu()
{
    closeAllListens();
    integer minsLeft = g_smokeTimeRemaining / 60;
    string timeStr;
    if (minsLeft > 0) timeStr = "~" + (string)minsLeft + " min left";
    else              timeStr = "almost done";
    g_lisSmokeActive = llListen(DCHAN_SMOKE_ACTIVE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== SMOKING ===\n" +
        g_smokeQuality + " " + g_smokeStrain + "\n" + timeStr,
        ["Take a Puff", "Put It Out", "Pass It", "Close"],
        DCHAN_SMOKE_ACTIVE);
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

showInventoryMenu()
{
    closeAllListens();
    llMessageLinked(LINK_SET, CHAN_INVENTORY, "REQUEST_INVENTORY", NULL_KEY);
    g_lisInv = llListen(DCHAN_INVENTORY, "", g_ownerKey, "");
    string invMsg = "=== INVENTORY ===\n" + g_inventoryDisplay;
    if (llStringLength(invMsg) > 480)
        invMsg = llGetSubString(invMsg, 0, 477) + "...";
    llDialog(g_ownerKey, invMsg, ["Load Jar", "Fill Bag", "Back"], DCHAN_INVENTORY);
    invMsg = ""; // release temp
    llSetTimerEvent(30.0);
}

showStats()
{
    closeAllListens();
    g_lisStatsMenu = llListen(DCHAN_STATS_MENU, "", g_ownerKey, "");
    string brandInfo = "";
    if (g_brandName != "" && g_brandName != g_playerName)
        brandInfo = "\nBrand: " + g_brandName;

    // Read RLV high-effects toggle (default off)
    string fxLabel = "FX: Off";
    if (llLinksetDataRead("hud_fx_enabled") == "1")
        fxLabel = "FX: On";

    llDialog(g_ownerKey,
        "=== STATS ===\n" + g_playerName + "\nTitle: " + g_playerTitle + brandInfo +
        "\n\nFX = on-screen visual effects while high (RLV).",
        ["View Stats", "Achievements", "Set Brand Name",
         "Reset Brand", fxLabel, "Close"],
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

        llOwnerSay("You lit up that " + qualLabel(g_pendingQuality) +
                   " " + g_pendingStrain + ". Stay faded fr.");

        g_isSmoking    = TRUE;
        g_smokeStrain  = g_pendingStrain;
        g_smokeQuality = g_pendingQuality;
        setButtonGlow(LINK_BTN_SMOKE, 0.1);

        // Tell Comms to rez the smoke prop and attach it (joint/blunt/spliff only)
        if (g_pendingItemType == "joint" || g_pendingItemType == "blunt" ||
            g_pendingItemType == "spliff")
        {
            llMessageLinked(LINK_SET, CHAN_COMMS,
                "TC_SMOKE_START|" + g_pendingItemType + "|" +
                g_pendingQuality + "|" + g_pendingStrain, NULL_KEY);
        }
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

        llOwnerSay("Slid that " + qualLabel(g_pendingQuality) + " " +
                   g_pendingStrain + " to " + g_passTargetName + ". Pass it real.");
    }

    // Clear flow state (including g_availableItems so the parsed
    // inventory snapshot doesn't linger in heap after a smoke/pass
    // flow completes — important for HUD memory pressure).
    g_flowContext     = "none";
    g_pendingItemType = "";
    g_pendingStrain   = "";
    g_pendingQuality  = "";
    g_pendingPackager = "";
    g_passTarget      = NULL_KEY;
    g_passTargetName  = "";
    g_availableItems  = [];
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
        // Sibling startup broadcasts (HUD_Identity.broadcastIdentity and
        // HUD_Inventory.broadcastInventorySummary, both fired from their
        // own state_entry / on_rez) are the primary attach hydration
        // path. We no longer fire REQUEST_IDENTITY / REQUEST_INVENTORY
        // here -- that was racing the sibling broadcasts and producing
        // duplicate hydration on every HUD attach. Instead we arm a
        // one-shot fallback timer that re-requests only the payloads
        // that haven't arrived within HYDRATION_FALLBACK_SEC.
        g_hydratedIdentity         = FALSE;
        g_hydratedInventory        = FALSE;
        g_hydrationFallbackPending = TRUE;
        llSetTimerEvent(HYDRATION_FALLBACK_SEC);
        refreshAllGlows();
        // Print initial memory headroom so we can spot regressions early.
        llOwnerSay("[HUD_UI] mem used=" + (string)llGetUsedMemory() +
                   " free=" + (string)llGetFreeMemory());
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer c)          { if (c & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        // Hydration fallback wins over the dialog cleanup branch: if
        // either sibling broadcast didn't land within the window, ask
        // for it now and exit without disturbing dialog state.
        if (g_hydrationFallbackPending)
        {
            runHydrationFallback();
            return;
        }
        closeAllListens();
        llSetTimerEvent(0.0);
        if (g_flowContext != "none") g_flowContext = "none";
    }

    // ----------------------------------------------------------------
    // TOUCH  -  route each named button
    // ----------------------------------------------------------------
    touch_start(integer nd)
    {
        if (llDetectedKey(0) != g_ownerKey) return;
        // The first menu open will overwrite the hydration fallback
        // timer with its own 30s dialog timer, so run the fallback
        // inline now if the sibling broadcasts haven't landed yet.
        if (g_hydrationFallbackPending) runHydrationFallback();
        string primName = llGetLinkName(llDetectedLinkNumber(0));

        if      (primName == "btn_smoke")
        {
            if (g_isSmoking) showActiveSmokeMenu();
            else             showSmokeTypeMenu();
        }
        else if (primName == "btn_inventory") showInventoryMenu();
        else if (primName == "btn_grow")
            llOwnerSay("Touch any plant or pot on your land to check its status.");
        else if (primName == "btn_session")
            llMessageLinked(LINK_SET, CHAN_SESSION, "OPEN_SESSION_MENU", NULL_KEY);
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
            if      (msg == "Smoke")
            {
                if (g_isSmoking) showActiveSmokeMenu();
                else             showSmokeTypeMenu();
            }
            else if (msg == "Inventory") showInventoryMenu();
            else if (msg == "Grow")
                llOwnerSay("Touch a plant to check its grow status.");
            else if (msg == "Session")
                llMessageLinked(LINK_SET, CHAN_SESSION, "OPEN_SESSION_MENU", NULL_KEY);
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

                    // If this is a smoke flow for a joint/blunt/spliff and
                    // the player has a paused session of the same
                    // type+quality+strain, offer Resume / Start Fresh
                    // before consuming another inventory item.
                    if (g_flowContext == "smoke" &&
                        (g_pendingItemType == "joint"  ||
                         g_pendingItemType == "blunt"  ||
                         g_pendingItemType == "spliff"))
                    {
                        string pausedKey = "smoke_paused_" + g_pendingItemType +
                                           "_" + g_pendingQuality +
                                           "_" + g_pendingStrain;
                        integer pausedRem = (integer)llLinksetDataRead(pausedKey);
                        if (pausedRem > 0)
                        {
                            showSmokeResumeMenu(pausedRem);
                            return;
                        }
                    }

                    executeRemove();
                    return;
                }
            }
            // No match (label collision)  -  redisplay
            showItemPickMenu();
        }

        // ---- RESUME / START FRESH for a paused smoke ----
        else if (channel == DCHAN_SMOKE_RESUME)
        {
            if (msg == "Cancel")
            {
                g_pendingResumeSecs = 0;
                showItemPickMenu();
                return;
            }
            if (msg == "Resume")
            {
                // Resume the saved smoke  -  do NOT consume another
                // inventory item. Fire SMOKE_STARTED flow directly with
                // the remaining time baked into TC_SMOKE_START so the
                // prop rezzes with start_param = pendingResumeSecs.
                llMessageLinked(LINK_SET, CHAN_ANIMATION,
                    "START_SMOKE_ANIM|" + g_pendingStrain + "|" +
                    g_pendingQuality + "|" + g_pendingItemType, NULL_KEY);

                llOwnerSay("You spark that " + qualLabel(g_pendingQuality) +
                           " " + g_pendingStrain + " right back up.");

                g_isSmoking    = TRUE;
                g_smokeStrain  = g_pendingStrain;
                g_smokeQuality = g_pendingQuality;
                setButtonGlow(LINK_BTN_SMOKE, 0.1);

                llMessageLinked(LINK_SET, CHAN_COMMS,
                    "TC_SMOKE_START|" + g_pendingItemType + "|" +
                    g_pendingQuality + "|" + g_pendingStrain + "|" +
                    (string)g_pendingResumeSecs, NULL_KEY);

                g_pendingResumeSecs = 0;
                g_flowContext       = "none";
                g_availableItems    = [];
                return;
            }
            if (msg == "Start Fresh")
            {
                // Discard saved pause and consume a fresh item normally.
                llLinksetDataDelete("smoke_paused_" + g_pendingItemType +
                                    "_" + g_pendingQuality +
                                    "_" + g_pendingStrain);
                g_pendingResumeSecs = 0;
                executeRemove();
                return;
            }
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

        // ---- ACTIVE SMOKE MENU ----
        else if (channel == DCHAN_SMOKE_ACTIVE)
        {
            if (msg == "Put It Out")
            {
                llMessageLinked(LINK_SET, CHAN_COMMS, "END_SMOKE_EARLY", NULL_KEY);
                g_isSmoking          = FALSE;
                g_smokeStrain        = "";
                g_smokeQuality       = "";
                g_smokeTimeRemaining = 0;
                g_availableItems     = [];
                g_flowContext        = "none";
                g_pendingItemType    = "";
                g_pendingStrain      = "";
                g_pendingQuality     = "";
                g_pendingPackager    = "";
                g_pendingResumeSecs  = 0;
                // closeAllListens already ran at listen() entry so
                // g_lisSmokeActive is already 0 here — no extra
                // surgical cleanup needed on this path.
                setButtonGlow(LINK_BTN_SMOKE, 0.0);
            }
            else if (msg == "Take a Puff")
            {
                llOwnerSay("You take a puff. Stay elevated.");
            }
            else if (msg == "Pass It")
            {
                g_flowContext = "pass";
                showPassPlayerMenu();
            }
            // "Close"  -  do nothing
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
            else if (msg == "Reset Brand")
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "RESET_BRAND_NAME", NULL_KEY);
            else if (msg == "FX: On" || msg == "FX: Off")
            {
                // Toggle RLV high-effects setting
                if (llLinksetDataRead("hud_fx_enabled") == "1")
                {
                    llLinksetDataWrite("hud_fx_enabled", "0");
                    llOwnerSay("Visual high effects disabled.");
                    // If currently smoking, clear effects immediately
                    llMessageLinked(LINK_SET, CHAN_ANIMATION, "FX_CLEAR", NULL_KEY);
                }
                else
                {
                    llLinksetDataWrite("hud_fx_enabled", "1");
                    llOwnerSay("Visual high effects enabled. Requires RLV-compatible viewer.");
                    // If currently smoking, start effects immediately
                    if (g_isSmoking)
                        llMessageLinked(LINK_SET, CHAN_ANIMATION,
                            "FX_START|" + g_smokeQuality, NULL_KEY);
                }
                showStats(); // re-show with updated label
                return;
            }
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
        // Early bail-out: this script only cares about CHAN_UI and
        // CHAN_COMMS (RAW_INVENTORY relay). Skipping the llParseString
        // allocation for every other channel keeps heap churn down.
        if (num != CHAN_UI && num != CHAN_COMMS) return;

        // Fast-path the two big-payload commands BEFORE allocating a
        // parts list. UPDATE_INVENTORY_DISPLAY and SHOW_STATS can each
        // carry several hundred chars; parsing them into a parts list
        // doubles the heap footprint of the message during dispatch
        // and was the main contributor to the smoke-flow stack-heap
        // collision (those messages fire on every inventory mutation,
        // which is exactly when the smoke flow runs).
        if (num == CHAN_UI)
        {
            if (llSubStringIndex(msg, "UPDATE_INVENTORY_DISPLAY|") == 0)
            {
                // Strip the command prefix; store the rest as-is.
                g_inventoryDisplay  = llDeleteSubString(msg, 0, 24);
                g_hydratedInventory = TRUE;
                return;
            }
            if (llSubStringIndex(msg, "SHOW_STATS|") == 0)
            {
                llOwnerSay(llDeleteSubString(msg, 0, 10));
                return;
            }
            // SMOKE_STOPPED is a single token  -  handle WITHOUT
            // allocating a parts list. This is the critical fast path
            // for the Put It Out flow that was blowing the heap.
            if (msg == "SMOKE_STOPPED")
            {
                // Clear active smoke state
                g_isSmoking          = FALSE;
                g_smokeStrain        = "";
                g_smokeQuality       = "";
                g_smokeTimeRemaining = 0;
                g_availableItems     = [];
                g_flowContext        = "none";
                // Clear pending fields too — otherwise a stale strain
                // from the last flow can leak into the next smoke.
                g_pendingItemType    = "";
                g_pendingStrain      = "";
                g_pendingQuality     = "";
                g_pendingPackager    = "";
                g_pendingResumeSecs  = 0;
                // Surgical listen cleanup: the smoke active / resume
                // dialogs might still be on screen when SMOKE_STOPPED
                // arrives via link_message (e.g. prop expired naturally
                // or remote put-out). Close ONLY those two listens so
                // unrelated menus (inventory, session, etc.) are not
                // disturbed. Without this, a stale button press on the
                // old smoke dialog routes through cleared state and
                // the HUD feels locked until the dialog auto-closes.
                if (g_lisSmokeActive)
                {
                    llListenRemove(g_lisSmokeActive);
                    g_lisSmokeActive = 0;
                }
                if (g_lisSmokeResume)
                {
                    llListenRemove(g_lisSmokeResume);
                    g_lisSmokeResume = 0;
                }
                setButtonGlow(LINK_BTN_SMOKE, 0.0);
                return;
            }
            // ITEM_USED / ITEM_FAILED carry an item-name suffix but the
            // dispatch only cares about the command. Detect with prefix
            // match and skip the parts allocation.
            if (llSubStringIndex(msg, "ITEM_USED|") == 0 || msg == "ITEM_USED")
            {
                onRemoveSuccess();
                return;
            }
            if (llSubStringIndex(msg, "ITEM_FAILED|") == 0 || msg == "ITEM_FAILED")
            {
                onRemoveFail();
                return;
            }
        }

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
                g_hydratedIdentity = TRUE;
            }

            // (UPDATE_INVENTORY_DISPLAY, SHOW_STATS, SMOKE_STOPPED,
            // ITEM_USED and ITEM_FAILED are fast-pathed above the parts
            // allocation to keep heap usage down on the smoke flow.)

            // World object (jar, weed piece, session) fired TC_SMOKED  -
            // Comms already started the animation, we just update state + glow.
            // SMOKE_STARTED|strain|quality|duration
            // Minimal work: only touch what onRemoveSuccess didn't already set.
            else if (cmd == "SMOKE_STARTED")
            {
                if (!g_isSmoking)
                {
                    g_isSmoking    = TRUE;
                    g_smokeStrain  = llList2String(parts, 1);
                    g_smokeQuality = llList2String(parts, 2);
                    setButtonGlow(LINK_BTN_SMOKE, 0.1);
                }
                g_smokeTimeRemaining = (integer)llList2String(parts, 3);
            }

            // ---- SESSION EVENTS ----

            // Session object rezzed  -  show item picker.
            // GUARD: only honour this when the player explicitly asked
            // for a session via Spark Session. Without the gate, ANY
            // nearby session-object rez (or replay of an old TC_SESSION_REZZED
            // ping) would auto-open the spark menu.
            else if (cmd == "SESSION_OBJECT_READY")
            {
                if (g_flowContext != "session_spark") return;
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SESSION_OBJECT_READY|" + llList2String(parts, 1), NULL_KEY);
            }

            // We joined someone else's session as a participant
            else if (cmd == "SESSION_JOINED")
            {
                g_sessionHost   = llList2String(parts, 1);
                g_sessionObjKey = (key)llList2String(parts, 2);
                g_inSession     = TRUE;
                setButtonGlow(LINK_BTN_SESSION, 0.1);
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|" + (string)g_inSession + "|" +
                    (string)g_sessionObjKey + "|" + g_sessionHost, NULL_KEY);
                llOwnerSay("Joined " + g_sessionHost + "'s circle. ?");
            }

            // We started a session as host
            else if (cmd == "SESSION_STARTED")
            {
                g_inSession     = TRUE;
                g_sessionHost   = g_ownerName;
                g_sessionObjKey = (key)llList2String(parts, 1);
                setButtonGlow(LINK_BTN_SESSION, 0.1);
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|" + (string)g_inSession + "|" +
                    (string)g_sessionObjKey + "|" + g_sessionHost, NULL_KEY);
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
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|" + (string)g_inSession + "|" +
                    (string)g_sessionObjKey + "|" + g_sessionHost, NULL_KEY);
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
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SESSION_INVITE|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2) + "|" +
                    llList2String(parts, 3) + "|" +
                    llList2String(parts, 4) + "|" +
                    llList2String(parts, 5), NULL_KEY);
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
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SESSION_RAW_INVENTORY|" + rawData, NULL_KEY);
            }
        }
    }
}
