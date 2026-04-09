// ================================================================
// THE CULTIVAR  -  HUD UI Script
// Version: 2.0-glowpatch
// Full HUD UI with smoke/session glow patch.
//
// Glow patch:
//   - Lower smoke/session glow from 0.1 to 0.04 to avoid the washed-
//     out translucent look on the textured buttons.
//   - Keep all other behavior the same as the current working UI.
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
integer DCHAN_PASS_PLAYER    = -11004;
integer DCHAN_INVENTORY      = -11009;
integer DCHAN_STATS_MENU     = -11010;
integer DCHAN_BRAND_NAME     = -11011;
integer DCHAN_SMOKE_ACTIVE   = -11020;
integer DCHAN_SMOKE_RESUME   = -11021;

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

integer g_pendingResumeSecs = 0;

key     g_ownerKey  = NULL_KEY;
string  g_ownerName = "";

string  g_playerName     = "";
integer g_repScore       = 0;
integer g_totalSmoked    = 0;
string  g_favoriteStrain = "";
string  g_brandName      = "";
string  g_playerTitle    = "Seedling";
string  g_inventoryDisplay = "Loading...";

integer g_isSmoking          = FALSE;
string  g_smokeStrain        = "";
string  g_smokeQuality       = "";
integer g_smokeTimeRemaining = 0;
integer g_inSession     = FALSE;
key     g_sessionObjKey = NULL_KEY;
string  g_sessionHost   = "";

string  g_flowContext = "none";

string  g_pendingItemType = "";
string  g_pendingStrain   = "";
string  g_pendingQuality  = "";
string  g_pendingPackager = "";

key     g_passTarget     = NULL_KEY;
string  g_passTargetName = "";

list    g_availableItems;
integer ITEM_STRIDE = 5;

integer g_hydratedIdentity         = FALSE;
integer g_hydratedInventory        = FALSE;
integer g_hydrationFallbackPending = FALSE;
float   HYDRATION_FALLBACK_SEC     = 3.0;

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
    setButtonGlow(LINK_BTN_SMOKE,   g_isSmoking * 0.04);
    setButtonGlow(LINK_BTN_SESSION, g_inSession * 0.04);
    setButtonGlow(LINK_BTN_INVENTORY, 0.0);
    setButtonGlow(LINK_BTN_GROW,      0.0);
    setButtonGlow(LINK_BTN_PASS,      0.0);
    setButtonGlow(LINK_BTN_STATS,     0.0);
    setButtonGlow(LINK_BTN_STORE,     0.0);
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
    integer i;
    for (i = 0; i < n; i++)
    {
        string slot = llList2String(slots, i);
        integer t1 = llSubStringIndex(slot, "~");
        if (t1 < 0) jump skip;
        string iType = llGetSubString(slot, 0, t1 - 1);
        integer match = all;
        if (!match)
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

default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llGetDisplayName(g_ownerKey);
        g_hydratedIdentity         = FALSE;
        g_hydratedInventory        = FALSE;
        g_hydrationFallbackPending = TRUE;
        llSetTimerEvent(HYDRATION_FALLBACK_SEC);
        refreshAllGlows();
        llOwnerSay("[HUD_UI] mem used=" + (string)llGetUsedMemory() + " free=" + (string)llGetFreeMemory());
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
        closeAllListens();
        llSetTimerEvent(0.0);
        if (g_flowContext != "none") g_flowContext = "none";
    }

    link_message(integer sender, integer num, string msg, key id)
    {
        if (num != CHAN_UI && num != CHAN_COMMS) return;

        if (num == CHAN_UI)
        {
            if (llSubStringIndex(msg, "UPDATE_INVENTORY_DISPLAY|") == 0)
            {
                g_inventoryDisplay  = llDeleteSubString(msg, 0, 24);
                g_hydratedInventory = TRUE;
                return;
            }
            if (llSubStringIndex(msg, "SHOW_STATS|") == 0)
            {
                llOwnerSay(llDeleteSubString(msg, 0, 10));
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
                if (g_lisSmokeActive) { llListenRemove(g_lisSmokeActive); g_lisSmokeActive = 0; }
                if (g_lisSmokeResume) { llListenRemove(g_lisSmokeResume); g_lisSmokeResume = 0; }
                setButtonGlow(LINK_BTN_SMOKE, 0.0);
                return;
            }
            if (llSubStringIndex(msg, "ITEM_USED|") == 0 || msg == "ITEM_USED")
            {
                return;
            }
            if (llSubStringIndex(msg, "ITEM_FAILED|") == 0 || msg == "ITEM_FAILED")
            {
                return;
            }
        }

        list parts = llParseString2List(msg, ["|"], []);
        string cmd = llList2String(parts, 0);

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
                    setButtonGlow(LINK_BTN_SMOKE, 0.04);
                }
                g_smokeTimeRemaining = (integer)llList2String(parts, 3);
            }
            else if (cmd == "SESSION_JOINED")
            {
                g_sessionHost   = llList2String(parts, 1);
                g_sessionObjKey = (key)llList2String(parts, 2);
                g_inSession     = TRUE;
                setButtonGlow(LINK_BTN_SESSION, 0.04);
            }
            else if (cmd == "SESSION_STARTED")
            {
                g_inSession     = TRUE;
                g_sessionHost   = g_ownerName;
                g_sessionObjKey = (key)llList2String(parts, 1);
                setButtonGlow(LINK_BTN_SESSION, 0.04);
            }
            else if (cmd == "SESSION_ENDED")
            {
                g_inSession     = FALSE;
                g_sessionObjKey = NULL_KEY;
                g_sessionHost   = "";
                refreshAllGlows();
            }
        }
    }
}
