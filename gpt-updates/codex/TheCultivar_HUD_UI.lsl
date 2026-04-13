// ================================================================
// THE CULTIVAR  -  HUD UI Script
// Version: 2.4
// Full preserved HUD UI with smoke lifecycle cleanup:
//   - removes optimistic START_SMOKE_ANIM on item remove success
//   - leaves actual smoke start authority to HUD_Comms on attach-ready
//   - preserves resume prompt
//   - preserves full menu / inventory / session logic
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_IDENTITY  = 400;
integer CHAN_ANIMATION = 500;
integer CHAN_SESSION   = 600;

integer LINK_BTN_SMOKE     = 2;
integer LINK_BTN_INVENTORY = 3;
integer LINK_BTN_GROW      = 4;
integer LINK_BTN_SESSION   = 5;
integer LINK_BTN_PASS      = 6;
integer LINK_BTN_STATS     = 7;
integer LINK_BTN_STORE     = 8;

integer DCHAN_MAIN           = -11000;
integer DCHAN_SMOKE_TYPE     = -11001;
integer DCHAN_ITEM_PICK      = -11002;
integer DCHAN_EDIBLE_TYPE    = -11003;
integer DCHAN_INVENTORY      = -11009;
integer DCHAN_STATS_MENU     = -11010;
integer DCHAN_BRAND_NAME     = -11011;
integer DCHAN_SMOKE_ACTIVE   = -11020;
integer DCHAN_SMOKE_RESUME   = -11021;

integer g_lisMain;
integer g_lisSmokeType;
integer g_lisItemPick;
integer g_lisEdibleType;
integer g_lisInv;
integer g_lisStatsMenu;
integer g_lisBrandName;
integer g_lisSmokeActive;
integer g_lisSmokeResume;

integer g_pendingResumeSecs = 0;

key     g_ownerKey  = NULL_KEY;
string  g_ownerName = "";

string  g_playerName       = "";
integer g_repScore         = 0;
integer g_totalSmoked      = 0;
string  g_favoriteStrain   = "";
string  g_brandName        = "";
string  g_playerTitle      = "Seedling";
string  g_inventoryDisplay = "Loading...";
integer g_inventoryPage    = 0;

integer g_isSmoking          = FALSE;
string  g_smokeStrain        = "";
string  g_smokeQuality       = "";
integer g_smokeTimeRemaining = 0;
integer g_inSession          = FALSE;
key     g_sessionObjKey      = NULL_KEY;
string  g_sessionHost        = "";

string  g_flowContext = "none";

string  g_pendingItemType = "";
string  g_pendingStrain   = "";
string  g_pendingQuality  = "";
string  g_pendingPackager = "";

list    g_availableItems;
integer ITEM_STRIDE = 5;

integer g_hydratedIdentity         = FALSE;
integer g_hydratedInventory        = FALSE;
integer g_hydrationFallbackPending = FALSE;
float   HYDRATION_FALLBACK_SEC     = 3.0;

integer g_growStatusChan   = 0;
integer g_lisGrowStatus    = 0;
integer g_growScanPending  = FALSE;
integer g_growScanDeadline = 0;
list    g_growStatusLines  = [];

closeAllListens()
{
    if (g_lisMain)          { llListenRemove(g_lisMain);          g_lisMain          = 0; }
    if (g_lisSmokeType)     { llListenRemove(g_lisSmokeType);     g_lisSmokeType     = 0; }
    if (g_lisItemPick)      { llListenRemove(g_lisItemPick);      g_lisItemPick      = 0; }
    if (g_lisEdibleType)    { llListenRemove(g_lisEdibleType);    g_lisEdibleType    = 0; }
    if (g_lisInv)           { llListenRemove(g_lisInv);           g_lisInv           = 0; }
    if (g_lisStatsMenu)     { llListenRemove(g_lisStatsMenu);     g_lisStatsMenu     = 0; }
    if (g_lisBrandName)     { llListenRemove(g_lisBrandName);     g_lisBrandName     = 0; }
    if (g_lisSmokeActive)   { llListenRemove(g_lisSmokeActive);   g_lisSmokeActive   = 0; }
    if (g_lisSmokeResume)   { llListenRemove(g_lisSmokeResume);   g_lisSmokeResume   = 0; }
    if (g_lisGrowStatus)    { llListenRemove(g_lisGrowStatus);    g_lisGrowStatus    = 0; }
}

refreshAllGlows()
{
    // Intentionally disabled.
}

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

integer deriveHUDChannel(key ownerID)
{
    string h = llGetSubString((string)ownerID, 0, 6);
    h = llDumpList2String(llParseString2List(h,["-"],[]),"");
    return (integer)("0x" + h) * -1;
}

string stageLabel(integer stage)
{
    if (stage == 1) return "Seedling";
    if (stage == 2) return "Vegetative";
    if (stage == 3) return "Flowering";
    if (stage == 4) return "Harvest Ready";
    return "Empty";
}

integer inventoryPageCount()
{
    integer maxLen = 420;
    integer len = llStringLength(g_inventoryDisplay);
    if (len <= 0) return 1;
    integer pages = len / maxLen;
    if ((len % maxLen) != 0) pages++;
    if (pages < 1) pages = 1;
    return pages;
}

string inventoryPageText(integer page)
{
    integer maxLen = 420;
    integer len = llStringLength(g_inventoryDisplay);
    if (len <= maxLen) return g_inventoryDisplay;
    integer start = page * maxLen;
    if (start < 0) start = 0;
    if (start > len - 1) start = len - 1;
    integer end = start + maxLen - 1;
    if (end > len - 1) end = len - 1;
    return llGetSubString(g_inventoryDisplay, start, end);
}

showGrowOverview()
{
    g_growScanPending = FALSE;
    if (g_lisGrowStatus) { llListenRemove(g_lisGrowStatus); g_lisGrowStatus = 0; }
    integer count = llGetListLength(g_growStatusLines);
    if (count == 0)
    {
        llOwnerSay("No active plants reported nearby. Touch a pot/plant directly if needed.");
        return;
    }
    llOwnerSay("=== Grow Overview ===");
    integer i;
    for (i = 0; i < count; ++i)
        llOwnerSay(llList2String(g_growStatusLines, i));
}

requestGrowOverview()
{
    g_growStatusLines = [];
    g_growScanPending = TRUE;
    g_growScanDeadline = llGetUnixTime() + 2;
    if (g_lisGrowStatus) llListenRemove(g_lisGrowStatus);
    g_lisGrowStatus = llListen(g_growStatusChan, "", NULL_KEY, "");
    llRegionSay(0, "TC_GROW_STATUS_REQUEST|" + (string)g_ownerKey + "|" + (string)g_growStatusChan);
    llSetTimerEvent(2.2);
}

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

parseItems(string rawData, string filterPrefix)
{
    g_availableItems = [];
    if (rawData == "" || rawData == "EMPTY") return;
    list slots = llParseString2List(rawData, ["^"], []);
    integer n   = llGetListLength(slots);
    integer all = (filterPrefix == "" || filterPrefix == "all");
    list passableTypes = ["joint","blunt","spliff","flower_raw",
                          "concentrate","edible_brownie",
                          "edible_gummy","edible_drink"];
    integer passableOnly = (filterPrefix == "passable");
    integer i;
    for (i = 0; i < n; i++)
    {
        if (llGetListLength(g_availableItems) >= (9 * ITEM_STRIDE))
            return;
        string slot = llList2String(slots, i);
        integer t1 = llSubStringIndex(slot, "~");
        if (t1 < 0) jump skip;
        string iType = llGetSubString(slot, 0, t1 - 1);
        integer match = all;
        if (passableOnly)
            match = (llListFindList(passableTypes, [iType]) != -1);
        else if (!match)
            match = (iType == filterPrefix || llSubStringIndex(iType, filterPrefix) == 0);
        if (!match) jump skip;
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

showSmokeTypeMenu()
{
    closeAllListens();
    g_flowContext = "smoke";
    g_lisSmokeType = llListen(DCHAN_SMOKE_TYPE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== SMOKE ===\nWhat are you smoking?\n\n" +
        "Joint / Blunt / Spliff - rolled items\n" +
        "Bowl / Bong - flower raw through a piece\n" +
        "Edible - brownies, gummies, drinks\n" +
        "Dab - concentrate",
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

showPassPlayerMenu()
{
    // Nearby/session pass flow moved to HUD_Pass script.
    llMessageLinked(LINK_SET, CHAN_SESSION, "OPEN_PASS_MENU", NULL_KEY);
}

showPassModeMenu()
{
    // Nearby/session pass flow moved to HUD_Pass script.
    llMessageLinked(LINK_SET, CHAN_SESSION, "OPEN_PASS_MENU", NULL_KEY);
}

showInventoryMenu()
{
    closeAllListens();
    llMessageLinked(LINK_SET, CHAN_INVENTORY, "REQUEST_INVENTORY", NULL_KEY);
    g_lisInv = llListen(DCHAN_INVENTORY, "", g_ownerKey, "");
    integer pages = inventoryPageCount();
    if (g_inventoryPage >= pages) g_inventoryPage = pages - 1;
    if (g_inventoryPage < 0) g_inventoryPage = 0;
    string invMsg = "=== INVENTORY ===\n" +
                    "(Page " + (string)(g_inventoryPage + 1) + "/" + (string)pages + ")\n" +
                    inventoryPageText(g_inventoryPage);
    if (llStringLength(invMsg) > 480)
        invMsg = llGetSubString(invMsg, 0, 477) + "...";
    list buttons = ["Load Jar", "Fill Bag", "Back"];
    if (pages > 1)
    {
        buttons += ["Prev Page", "Next Page"];
    }
    llDialog(g_ownerKey, invMsg, buttons, DCHAN_INVENTORY);
    llSetTimerEvent(30.0);
}

showStats()
{
    closeAllListens();
    g_lisStatsMenu = llListen(DCHAN_STATS_MENU, "", g_ownerKey, "");
    string brandInfo = "";
    if (g_brandName != "" && g_brandName != g_playerName)
        brandInfo = "\nBrand: " + g_brandName;

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

executeRemove()
{
    llMessageLinked(LINK_SET, CHAN_INVENTORY,
        "REMOVE_ITEM|" + g_pendingItemType + "|" +
        g_pendingStrain   + "|" +
        g_pendingQuality  + "|1|" +
        g_pendingPackager, NULL_KEY);
}

resetPendingFlow()
{
    g_flowContext     = "none";
    g_pendingItemType = "";
    g_pendingStrain   = "";
    g_pendingQuality  = "";
    g_pendingPackager = "";
    g_availableItems  = [];
}

onRemoveSuccess()
{
    if (g_flowContext == "smoke")
    {
        llMessageLinked(LINK_SET, CHAN_IDENTITY,
            "UPDATE_SMOKED|" + g_pendingStrain, NULL_KEY);

        llOwnerSay("You lit up that " + qualLabel(g_pendingQuality) +
                   " " + g_pendingStrain + ". Stay faded fr.");

        g_isSmoking    = TRUE;
        g_smokeStrain  = g_pendingStrain;
        g_smokeQuality = g_pendingQuality;

        if (g_pendingItemType == "joint" || g_pendingItemType == "blunt" ||
            g_pendingItemType == "spliff")
        {
            llMessageLinked(LINK_SET, CHAN_COMMS,
                "TC_SMOKE_START|" + g_pendingItemType + "|" +
                g_pendingQuality + "|" + g_pendingStrain, NULL_KEY);
        }
        else
        {
            // Non-attach item types can still use animation immediately if needed.
            llMessageLinked(LINK_SET, CHAN_ANIMATION,
                "START_SMOKE_ANIM|" + g_pendingStrain + "|" +
                g_pendingQuality + "|" + g_pendingItemType, NULL_KEY);
        }
    }
    resetPendingFlow();
}

onRemoveFail()
{
    llOwnerSay("Not enough " + g_pendingItemType + ". Check your inventory.");
    g_flowContext     = "none";
    g_pendingItemType = "";
    g_pendingStrain   = "";
    g_pendingQuality  = "";
}

default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llGetDisplayName(g_ownerKey);
        g_growStatusChan = deriveHUDChannel(g_ownerKey);
        g_hydratedIdentity         = FALSE;
        g_hydratedInventory        = FALSE;
        g_hydrationFallbackPending = TRUE;
        llSetTimerEvent(HYDRATION_FALLBACK_SEC);
        refreshAllGlows();
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer c)          { if (c & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        if (g_hydrationFallbackPending)
        {
            runHydrationFallback();
            return;
        }
        if (g_growScanPending)
        {
            showGrowOverview();
            return;
        }
        closeAllListens();
        llSetTimerEvent(0.0);
        if (g_flowContext != "none") g_flowContext = "none";
    }

    touch_start(integer nd)
    {
        if (llDetectedKey(0) != g_ownerKey) return;
        if (g_hydrationFallbackPending) runHydrationFallback();
        string primName = llGetLinkName(llDetectedLinkNumber(0));

        if      (primName == "btn_smoke")
        {
            if (g_isSmoking) showActiveSmokeMenu();
            else             showSmokeTypeMenu();
        }
        else if (primName == "btn_inventory") showInventoryMenu();
        else if (primName == "btn_grow")
            requestGrowOverview();
        else if (primName == "btn_session")
            llMessageLinked(LINK_SET, CHAN_SESSION, "OPEN_SESSION_MENU", NULL_KEY);
        else if (primName == "btn_pass")
            showPassModeMenu();
        else if (primName == "btn_stats")     showStats();
        else if (primName == "btn_store")
            llLoadURL(g_ownerKey, "The Cultivar Store",
                      "https://marketplace.secondlife.com");
        else showMainMenu();
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel == g_growStatusChan)
        {
            list p = llParseString2List(msg, ["|"], []);
            if (llList2String(p, 0) == "TC_GROW_STATUS")
            {
                string strain = llList2String(p, 2);
                integer stage = (integer)llList2String(p, 3);
                integer rem   = (integer)llList2String(p, 4);
                string need   = llList2String(p, 5);
                string line = strain + " - " + stageLabel(stage);
                if (stage > 0 && stage < 4)
                    line += " - " + (string)(rem / 60) + "m left";
                if (need != "" && need != "none")
                    line += " - needs " + need;
                if (llGetListLength(g_growStatusLines) < 20)
                    g_growStatusLines += [line];
            }
            return;
        }

        if (id != g_ownerKey) return;
        closeAllListens();
        llSetTimerEvent(0.0);

        if (channel == DCHAN_MAIN)
        {
            if      (msg == "Smoke")
            {
                if (g_isSmoking) showActiveSmokeMenu();
                else             showSmokeTypeMenu();
            }
            else if (msg == "Inventory") showInventoryMenu();
            else if (msg == "Grow")
                requestGrowOverview();
            else if (msg == "Session")
                llMessageLinked(LINK_SET, CHAN_SESSION, "OPEN_SESSION_MENU", NULL_KEY);
            else if (msg == "Pass")
                showPassModeMenu();
            else if (msg == "Stats")   showStats();
            else if (msg == "Store")
                llLoadURL(g_ownerKey, "The Cultivar Store",
                          "https://marketplace.secondlife.com");
        }
        else if (channel == DCHAN_SMOKE_TYPE)
        {
            if (msg == "Back") { g_flowContext = "none"; showMainMenu(); return; }
            if (msg == "Edible") { showEdibleTypeMenu(); return; }

            g_pendingItemType = menuToItemType(msg);
            llMessageLinked(LINK_SET, CHAN_INVENTORY,
                "REQUEST_RAW_INVENTORY|" + g_pendingItemType + "|ui_smoke",
                NULL_KEY);
        }
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
        else if (channel == DCHAN_ITEM_PICK)
        {
            if (msg == "Back")
            {
                if (g_flowContext == "pass") showPassPlayerMenu();
                else showSmokeTypeMenu();
                return;
            }
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

                    if (g_flowContext == "smoke" &&
                        (g_pendingItemType == "joint"  ||
                         g_pendingItemType == "blunt"  ||
                         g_pendingItemType == "spliff"))
                    {
                        string pausedKey = "smoke_paused_" + g_pendingItemType +
                                           "_" + g_pendingQuality +
                                           "_" + g_pendingStrain;
                        integer pausedRem = (integer)llLinksetDataRead(pausedKey);
                        if (pausedRem <= 0)
                        {
                            string pausedFallback = "smoke_paused_" + g_pendingItemType +
                                                    "_" + g_pendingQuality + "_*";
                            pausedRem = (integer)llLinksetDataRead(pausedFallback);
                        }
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
            showItemPickMenu();
        }
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
                llOwnerSay("You spark that " + qualLabel(g_pendingQuality) +
                           " " + g_pendingStrain + " right back up.");

                g_isSmoking    = TRUE;
                g_smokeStrain  = g_pendingStrain;
                g_smokeQuality = g_pendingQuality;

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
                llLinksetDataDelete("smoke_paused_" + g_pendingItemType +
                                    "_" + g_pendingQuality +
                                    "_" + g_pendingStrain);
                g_pendingResumeSecs = 0;
                executeRemove();
                return;
            }
        }
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
            }
            else if (msg == "Take a Puff")
            {
                llOwnerSay("You take a puff. Stay elevated.");
            }
            else if (msg == "Pass It")
                showPassModeMenu();
        }
        else if (channel == DCHAN_INVENTORY)
        {
            if (msg == "Prev Page")
            {
                g_inventoryPage--;
                if (g_inventoryPage < 0) g_inventoryPage = 0;
                showInventoryMenu();
            }
            else if (msg == "Next Page")
            {
                g_inventoryPage++;
                integer pages = inventoryPageCount();
                if (g_inventoryPage >= pages) g_inventoryPage = pages - 1;
                showInventoryMenu();
            }
            else if (msg == "Back") showMainMenu();
            else if (msg == "Load Jar")
                llOwnerSay("Touch your weed jar to load flower from your inventory.");
            else if (msg == "Fill Bag")
                llOwnerSay("Touch your bagging table to package flower into bags.");
        }
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
                if (llLinksetDataRead("hud_fx_enabled") == "1")
                {
                    llLinksetDataWrite("hud_fx_enabled", "0");
                    llOwnerSay("Visual high effects disabled.");
                    llMessageLinked(LINK_SET, CHAN_ANIMATION, "FX_CLEAR", NULL_KEY);
                }
                else
                {
                    llLinksetDataWrite("hud_fx_enabled", "1");
                    llOwnerSay("Visual high effects enabled. Requires RLV-compatible viewer.");
                    if (g_isSmoking)
                        llMessageLinked(LINK_SET, CHAN_ANIMATION,
                            "FX_START|" + g_smokeQuality, NULL_KEY);
                }
                showStats();
                return;
            }
        }
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

    link_message(integer sender, integer num, string msg, key id)
    {
        if (num != CHAN_UI && num != CHAN_COMMS) return;

        if (num == CHAN_UI)
        {
            if (llSubStringIndex(msg, "UPDATE_INVENTORY_DISPLAY|") == 0)
            {
                string newDisplay = llDeleteSubString(msg, 0, 24);
                if (llStringLength(newDisplay) > 1260)
                    newDisplay = llGetSubString(newDisplay, 0, 1259) + "\n[...truncated]";
                g_inventoryDisplay  = newDisplay;
                g_inventoryPage     = 0;
                g_hydratedInventory = TRUE;
                return;
            }
            if (msg == "SMOKE_STOPPED")
            {
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
                return;
            }
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

        if (num == CHAN_UI)
        {
            if (cmd == "IDENTITY_DATA")
            {
                g_playerName     = llList2String(parts, 1);
                g_totalSmoked    = (integer)llList2String(parts, 3);
                g_favoriteStrain = llList2String(parts, 7);
                g_repScore       = (integer)llList2String(parts, 8);
                g_brandName      = llList2String(parts, 10);
                if (llGetListLength(parts) > 14)
                    g_playerTitle = llList2String(parts, 14);
                g_hydratedIdentity = TRUE;
            }
            else if (cmd == "SMOKE_STARTED")
            {
                if (!g_isSmoking)
                {
                    g_isSmoking    = TRUE;
                    g_smokeStrain  = llList2String(parts, 1);
                    g_smokeQuality = llList2String(parts, 2);
                }
                g_smokeTimeRemaining = (integer)llList2String(parts, 3);
            }
            else if (cmd == "SESSION_OBJECT_READY")
            {
                if (g_flowContext != "session_spark") return;
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SESSION_OBJECT_READY|" + llList2String(parts, 1), NULL_KEY);
            }
            else if (cmd == "SESSION_JOINED")
            {
                g_sessionHost   = llList2String(parts, 1);
                g_sessionObjKey = (key)llList2String(parts, 2);
                g_inSession     = TRUE;
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|" + (string)g_inSession + "|" +
                    (string)g_sessionObjKey + "|" + g_sessionHost, NULL_KEY);
                llOwnerSay("Joined " + g_sessionHost + "'s circle.");
            }
            else if (cmd == "SESSION_STARTED")
            {
                g_inSession     = TRUE;
                g_sessionHost   = g_ownerName;
                g_sessionObjKey = (key)llList2String(parts, 1);
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SYNC_SESSION_STATE|" + (string)g_inSession + "|" +
                    (string)g_sessionObjKey + "|" + g_sessionHost, NULL_KEY);
            }
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
                llOwnerSay("Session ended.");
            }
            else if (cmd == "SESSION_MEMBER_JOIN")
                llOwnerSay(llList2String(parts, 1) + " joined the circle.");
            else if (cmd == "SESSION_MEMBER_LEAVE")
                llOwnerSay(llList2String(parts, 1) + " left the circle.");
            else if (cmd == "SHOW_SESSION_INVITE")
            {
                if (g_inSession) return;
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SESSION_INVITE|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2) + "|" +
                    llList2String(parts, 3) + "|" +
                    llList2String(parts, 4) + "|" +
                    llList2String(parts, 5), NULL_KEY);
            }
            else if (cmd == "PASS_RECEIVED_NOTIFY")
            {
                string fromName = llList2String(parts, 1);
                string strain   = llList2String(parts, 2);
                string quality  = llList2String(parts, 3);
                llOwnerSay(fromName + " passed you " + quality +
                           " " + strain + ".");
            }
            else if (cmd == "YOUR_TURN_COUNTDOWN")
            {
                integer remaining = (integer)llList2String(parts, 1);
                string  strain    = llList2String(parts, 2);
                llOwnerSay(strain + " - " + (string)remaining + "s remaining!");
            }
            else if (cmd == "CYPHER_MODE_CHANGE")
            {
                if (llList2String(parts, 1) == "1")
                    llOwnerSay("Cypher mode ON - " +
                        llList2String(parts, 2) + "s per turn. Pass it quick!");
                else
                    llOwnerSay("Cypher mode OFF - back to free flow.");
            }
            else if (cmd == "SESSION_OVERHEAD")
            {
                return;
            }
        }
        else if (num == CHAN_COMMS && cmd == "RAW_INVENTORY")
        {
            string rawData = llList2String(parts, 1);
            string reqKey  = llList2String(parts, 3);

            if (llSubStringIndex(reqKey, "ui_") != 0) return;

            if (reqKey == "ui_smoke")
            {
                parseItems(rawData, g_pendingItemType);
                showItemPickMenu();
            }
            else if (reqKey == "ui_pass")
            {
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "PASS_RAW_INVENTORY|" + rawData, NULL_KEY);
            }
            else if (reqKey == "ui_session")
            {
                llMessageLinked(LINK_SET, CHAN_SESSION,
                    "SESSION_RAW_INVENTORY|" + rawData, NULL_KEY);
            }
        }
    }
}
