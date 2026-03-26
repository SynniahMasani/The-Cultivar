// ================================================================
// THE CULTIVAR  -  Plant Interaction Script
// Version: 1.0
// Handles: All touch input, dialog menus, action validation,
//          and communicating player choices to the grow script.
//
// This script is the face of the plant  -  it's what players
// actually interact with. It validates actions before passing
// them to the grow script, and handles access control so
// random strangers can't harvest your crop.
// ================================================================

integer PCHAN_GROW    = 1000;
integer PCHAN_PERSIST = 1100;

// Dialog channels
integer DCHAN_MAIN     = -33001;
integer DCHAN_PLANT    = -33002;
integer DCHAN_STRAIN   = -33003;
integer DCHAN_CONFIRM  = -33004;
integer DCHAN_ACCESS   = -33005;
integer DCHAN_ADD_AUTH = -33006;
integer DCHAN_REM_AUTH = -33007;

integer g_listenMain;
integer g_listenPlant;
integer g_listenStrain;
integer g_listenConfirm;
integer g_listenHUD;      // HUD inventory response channel
integer g_listenVisitor;  // visitor "Close" dialog
integer g_listenAccess;
integer g_listenAddAuth;
integer g_listenRemAuth;

key     g_ownerKey;
string  g_ownerName;
key     g_toucher    = NULL_KEY;
integer g_hudChannel = 0;        // derived from owner key, used for seed queries

// Cached seed list from HUD (stride 2: strainName, qualityStr)
list    g_availableSeeds = [];
// Selected tier while waiting for seed data from HUD
integer g_pendingPlantTier = -1;

// Access control
integer g_plantLocked    = FALSE;  // if TRUE, only owner can interact
integer g_toucherInGroup = FALSE;  // set in touch_start via llDetectedGroup(0)

// Cached status from grow script
string  g_strainName    = "";
integer g_qualityTier   = 0;
integer g_stage         = 0;
integer g_isWatered     = FALSE;
integer g_fertApplied   = FALSE;
integer g_potType_basic = TRUE;
integer g_potUsesLeft   = 5;
integer g_potSpent      = FALSE;

// Pending action waiting for confirmation
string g_pendingAction = "";

// ----------------------------------------------------------------
// Derive HUD private channel from owner UUID (must match HUD_Comms)
// ----------------------------------------------------------------
integer deriveHUDChannel(key ownerID)
{
    string h = llGetSubString((string)ownerID, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

// ----------------------------------------------------------------
// Close all open listens
// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenMain)     { llListenRemove(g_listenMain);     g_listenMain    = 0; }
    if (g_listenPlant)    { llListenRemove(g_listenPlant);    g_listenPlant   = 0; }
    if (g_listenStrain)   { llListenRemove(g_listenStrain);   g_listenStrain  = 0; }
    if (g_listenConfirm)  { llListenRemove(g_listenConfirm);  g_listenConfirm = 0; }
    if (g_listenHUD)      { llListenRemove(g_listenHUD);      g_listenHUD     = 0; }
    if (g_listenVisitor)  { llListenRemove(g_listenVisitor);  g_listenVisitor = 0; }
    if (g_listenAccess)   { llListenRemove(g_listenAccess);   g_listenAccess  = 0; }
    if (g_listenAddAuth)  { llListenRemove(g_listenAddAuth);  g_listenAddAuth = 0; }
    if (g_listenRemAuth)  { llListenRemove(g_listenRemAuth);  g_listenRemAuth = 0; }
}

// ----------------------------------------------------------------
// Access check  -  owner always authorized; others via auth list or group
// g_toucherInGroup must be set before calling (touch_start only)
// ----------------------------------------------------------------
integer isOwner(key who)
{
    return (who == g_ownerKey);
}

integer isAuthorized(key who)
{
    if (who == g_ownerKey) return TRUE;
    if (g_plantLocked) return FALSE;
    // Check explicit auth list
    string authData = llLinksetDataRead("auth_list");
    if (authData != "" &&
        llListFindList(llParseString2List(authData, [","], []),
                       [(string)who]) != -1)
        return TRUE;
    // Check same group as the object
    if (g_toucherInGroup) return TRUE;
    return FALSE;
}

// ----------------------------------------------------------------
// ACCESS MANAGEMENT MENUS
// ----------------------------------------------------------------
showAccessMenu()
{
    closeAllListens();
    string authData  = llLinksetDataRead("auth_list");
    integer authCount = 0;
    if (authData != "")
        authCount = llGetListLength(llParseString2List(authData, [","], []));
    string lockBtn = "Lock Plant";
    if (g_plantLocked) lockBtn = "Unlock Plant";
    string lockStatus = "Open (group + auth list)";
    if (g_plantLocked) lockStatus = "LOCKED (owner only)";
    g_listenAccess = llListen(DCHAN_ACCESS, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== ACCESS CONTROL ===\n" +
        "Authorized: " + (string)authCount + " player(s)\n" +
        "Status: " + lockStatus,
        ["Add Player", "Remove Player", lockBtn, "Back"],
        DCHAN_ACCESS);
    llSetTimerEvent(30.0);
}

showAddPlayerMenu()
{
    closeAllListens();
    list   agents  = llGetAgentList(AGENT_LIST_PARCEL, []);
    list   buttons;
    string menuText = "=== ADD PLAYER ===\nGrant access to:\n\n";
    integer i;
    for (i = 0; i < llGetListLength(agents); i++)
    {
        key    a = llList2Key(agents, i);
        if (a == g_ownerKey) jump skip_self;
        string n = llKey2Name(a);
        buttons += [llGetSubString(n, 0, 11)];
        menuText += n + "\n";
        @skip_self;
    }
    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(g_ownerKey, 0, "No other players nearby to add.");
        showAccessMenu();
        return;
    }
    buttons += ["Back"];
    g_listenAddAuth = llListen(DCHAN_ADD_AUTH, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_ADD_AUTH);
    llSetTimerEvent(30.0);
}

showRemovePlayerMenu()
{
    closeAllListens();
    string authData = llLinksetDataRead("auth_list");
    list   authList = llParseString2List(authData, [","], []);
    integer n = llGetListLength(authList);
    if (n == 0)
    {
        llRegionSayTo(g_ownerKey, 0, "Auth list is empty.");
        showAccessMenu();
        return;
    }
    list   buttons;
    string menuText = "=== REMOVE PLAYER ===\nRemove access from:\n\n";
    integer i;
    for (i = 0; i < n && llGetListLength(buttons) < 9; i++)
    {
        string k     = llList2String(authList, i);
        string pName = llKey2Name((key)k);
        if (pName == "") pName = llGetSubString(k, 0, 7) + "...";
        buttons  += [llGetSubString(pName, 0, 11)];
        menuText += pName + "\n";
    }
    buttons += ["Back"];
    g_listenRemAuth = llListen(DCHAN_REM_AUTH, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_REM_AUTH);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Build the status string shown in menus
// ----------------------------------------------------------------
string buildStatusString()
{
    if (g_potSpent)
        return "? This pot is cracked and spent.\nReplace it with a new pot.";

    if (g_stage == 0)
        return "Pot is empty.\nPlant a seed to begin growing.";

    list stageNames  = ["", "Seedling ?", "Vegetative ?", "Flowering ?", "? READY ?"];
    list qualNames   = ["Reggie", "Mids", "Loud", "Exotic"];
    string stageName = llList2String(stageNames, g_stage);
    string qualName  = llList2String(qualNames, g_qualityTier);

    string status = g_strainName + " [" + qualName + "]\n";
    status += "Stage: " + stageName + "\n";

    if (g_stage < 4)
    {
        if (g_isWatered)  status += "? Watered\n";
        else              status += "? Needs water\n";
        if (g_fertApplied) status += "? Fertilized\n";
    }

    string potLabel = "Premium pot";
    if (g_potType_basic) potLabel = "Basic pot";
    if (g_potType_basic)
        potLabel += " (" + (string)g_potUsesLeft + " uses left)";
    status += potLabel;

    return status;
}

// ----------------------------------------------------------------
// MAIN MENU  -  shown to owner on touch
// ----------------------------------------------------------------
showMainMenu()
{
    closeAllListens();
    string statusStr = buildStatusString();
    list buttons;

    if (g_potSpent)
    {
        buttons = ["Replace Pot", "Close"];
    }
    else if (g_stage == 0)
    {
        buttons = ["Plant Seed", "Close"];
    }
    else if (g_stage == 4)
    {
        buttons = ["Harvest!", "Check Status", "Close"];
    }
    else
    {
        buttons = ["Water", "Fertilize", "Check Status", "Close"];
        // Only show fertilize during veg stage and if not already applied
        if (g_stage != 2 || g_fertApplied)
            buttons = llDeleteSubList(buttons, llListFindList(buttons, ["Fertilize"]),
                                     llListFindList(buttons, ["Fertilize"]));
    }

    // Owner gets an Access button for managing the auth list
    if (isOwner(g_toucher))
    {
        integer closeIdx = llListFindList(buttons, ["Close"]);
        if (closeIdx != -1)
            buttons = llListInsertList(buttons, ["Access"], closeIdx);
    }

    g_listenMain = llListen(DCHAN_MAIN, "", g_toucher, "");
    llDialog(g_toucher,
        "=== YOUR PLANT ===\n" + statusStr,
        buttons, DCHAN_MAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// VISITOR MENU  -  limited view for non-owners
// ----------------------------------------------------------------
showVisitorMenu()
{
    string statusStr = buildStatusString();
    if (g_listenVisitor) llListenRemove(g_listenVisitor);
    g_listenVisitor = llListen(-44001, "", g_toucher, "Close");
    llDialog(g_toucher,
        "=== PLANT (Owner: " + g_ownerName + ") ===\n" + statusStr,
        ["Close"], -44001);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STRAIN SELECTION MENU  -  built from player's actual HUD seed inventory
// ----------------------------------------------------------------
showStrainMenu(integer qualityTier)
{
    closeAllListens();
    list qualStrings = ["reggie", "mids", "loud", "exotic"];
    string tierQual  = llList2String(qualStrings, qualityTier);

    list buttons;
    integer i;
    for (i = 0; i < llGetListLength(g_availableSeeds); i += 2)
    {
        if (llList2String(g_availableSeeds, i+1) == tierQual)
        {
            string sn = llList2String(g_availableSeeds, i);
            if (llListFindList(buttons, [sn]) == -1) // no dupes
                buttons += [sn];
        }
    }

    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(g_toucher, 0,
            "You don't have any " + llList2String(["Reggie","Mids","Loud","Exotic"], qualityTier) +
            " seeds in your HUD inventory.");
        showPotMenu();
        return;
    }
    buttons += ["Back"];

    list qualNames = ["Reggie", "Mids", "Loud", "Exotic"];
    g_listenStrain = llListen(DCHAN_STRAIN, "", g_toucher, "");
    llDialog(g_toucher,
        "=== CHOOSE STRAIN ===\n" +
        llList2String(qualNames, qualityTier) + " tier. Select a strain:",
        buttons, DCHAN_STRAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// POT TYPE MENU  -  only shows tiers the player has seeds for
// ----------------------------------------------------------------
showPotMenu()
{
    closeAllListens();
    list qualStrings  = ["reggie", "mids", "loud", "exotic"];
    list qualBtnNames = ["Reggie Seed", "Mids Seed", "Loud Seed", "Exotic Seed"];
    list buttons;
    integer t;
    for (t = 0; t < 4; t++)
    {
        string q = llList2String(qualStrings, t);
        integer i;
        for (i = 0; i < llGetListLength(g_availableSeeds); i += 2)
        {
            if (llList2String(g_availableSeeds, i+1) == q)
            {
                buttons += [llList2String(qualBtnNames, t)];
                jump next_tier;
            }
        }
        @next_tier;
    }
    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(g_toucher, 0,
            "You don't have any seeds in your HUD inventory. " +
            "Open a seed pack or earn seeds to start growing.");
        return;
    }
    buttons += ["Back"];
    g_listenPlant = llListen(DCHAN_PLANT, "", g_toucher, "");
    llDialog(g_toucher,
        "=== SELECT SEED TIER ===\nWhat are you planting?",
        buttons, DCHAN_PLANT);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// CONFIRM HARVEST  -  safety check before taking the goods
// ----------------------------------------------------------------
showHarvestConfirm()
{
    closeAllListens();
    g_listenConfirm = llListen(DCHAN_CONFIRM, "", g_toucher, "");
    llDialog(g_toucher,
        "=== HARVEST ===\nReady to harvest your " + g_strainName + "?\n" +
        "The plant will reset after harvest.",
        ["Harvest Now!", "Cancel"], DCHAN_CONFIRM);
}

// ----------------------------------------------------------------
// WATER ACTION  -  check inventory via HUD, apply if available
// ----------------------------------------------------------------
doWater()
{
    if (g_isWatered)
    {
        llRegionSayTo(g_toucher, 0, "Already watered this stage.");
        return;
    }
    // Signal grow script  -  inventory check happens via HUD
    // (Water can is a consumable tracked on the HUD)
    // We message the grow script directly since it trusts the interaction script
    // The full inventory-check flow would be:
    // 1. Send CHECK_QTY to HUD inventory via comms channel
    // 2. Wait for QTY_RESULT
    // 3. If sufficient, send WATER_APPLIED to grow script
    // For v1.0 we do a simplified trust-based approach and
    // let the HUD's water can tracking handle the rest via a separate listen
    llMessageLinked(LINK_SET, PCHAN_GROW, "WATER_APPLIED", NULL_KEY);
}

// ----------------------------------------------------------------
// FERTILIZE ACTION  -  validate stage and apply
// ----------------------------------------------------------------
doFertilize(integer fertTier)
{
    if (g_fertApplied)
    {
        llRegionSayTo(g_toucher, 0, "Already fertilized this cycle.");
        return;
    }
    if (g_stage != 2)
    {
        llRegionSayTo(g_toucher, 0,
            "Fertilizer can only be used during the vegetative stage.");
        return;
    }
    llMessageLinked(LINK_SET, PCHAN_GROW,
        "FERT_APPLIED|" + (string)fertTier, NULL_KEY);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey    = llGetOwner();
        g_ownerName   = llKey2Name(g_ownerKey);
        g_hudChannel  = deriveHUDChannel(g_ownerKey);
        g_plantLocked = (integer)llLinksetDataRead("plant_locked");
        llMessageLinked(LINK_SET, PCHAN_GROW, "REQUEST_STATUS", NULL_KEY);
    }

    on_rez(integer start_param)
    {
        g_ownerKey    = llGetOwner();
        g_ownerName   = llKey2Name(g_ownerKey);
        g_hudChannel  = deriveHUDChannel(g_ownerKey);
        g_plantLocked = (integer)llLinksetDataRead("plant_locked");
        llMessageLinked(LINK_SET, PCHAN_GROW, "REQUEST_STATUS", NULL_KEY);
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            // Plant stays with the land  -  if it's transferred, reset and clear auth
            llLinksetDataDelete("auth_list");
            llLinksetDataDelete("plant_locked");
            llMessageLinked(LINK_SET, PCHAN_GROW, "DO_RESET", NULL_KEY);
            llResetScript();
        }
    }

    timer()
    {
        closeAllListens();
        llSetTimerEvent(0.0);
    }

    touch_start(integer nd)
    {
        g_toucher        = llDetectedKey(0);
        g_toucherInGroup = llDetectedGroup(0); // must read here, in touch_start event
        closeAllListens();
        llSetTimerEvent(0.0);

        // Request fresh status before showing menu.
        // Note: llSleep() is not used here  -  it would block the event queue
        // and prevent the STATUS link_message from arriving anyway.
        // The menu builds from cached status values which are updated whenever
        // the grow script sends a STATUS reply (including after each action).
        llMessageLinked(LINK_SET, PCHAN_GROW, "REQUEST_STATUS", NULL_KEY);

        if (isAuthorized(g_toucher))
            showMainMenu();
        else
        {
            if (g_plantLocked)
                llRegionSayTo(g_toucher, 0,
                    g_ownerName + "'s plant is locked  -  owner access only.");
            else
                showVisitorMenu();
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        // HUD seed inventory response  -  arrives from HUD object, not from g_toucher
        if (channel == g_hudChannel && g_listenHUD != 0)
        {
            list   parts2 = llParseString2List(msg, ["|"], []);
            string cmd2   = llList2String(parts2, 0);
            if (cmd2 == "TC_INVENTORY_DATA")
            {
                if (g_listenHUD) { llListenRemove(g_listenHUD); g_listenHUD = 0; }
                string rawData = llList2String(parts2, 1);
                g_availableSeeds = [];
                if (rawData != "")
                {
                    list entries = llParseString2List(rawData, ["^"], []);
                    integer ei;
                    for (ei = 0; ei < llGetListLength(entries); ei++)
                    {
                        list fields = llParseString2List(llList2String(entries, ei), ["~"], []);
                        // fields: itemType ~ strainName ~ quality ~ qty ~ packager
                        if (llGetListLength(fields) >= 3)
                            g_availableSeeds += [llList2String(fields, 1),
                                                 llList2String(fields, 2)];
                    }
                }
                showPotMenu();
            }
            return;
        }

        if (id != g_toucher) return;
        closeAllListens();
        llSetTimerEvent(0.0);

        // MAIN MENU response
        if (channel == DCHAN_MAIN)
        {
            if (msg == "Close") return;

            else if (msg == "Plant Seed")
            {
                // Request seed inventory from HUD, then show filtered menus
                g_availableSeeds = [];
                if (g_listenHUD) llListenRemove(g_listenHUD);
                g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");
                llRegionSayTo(g_ownerKey, g_hudChannel,
                    "TC_INVENTORY_REQUEST|seed_raw|" + (string)llGetKey());
                llSetTimerEvent(10.0); // short timeout for HUD response
            }

            else if (msg == "Water")
                doWater();

            else if (msg == "Fertilize")
                doFertilize(0); // basic fertilizer, applied directly like water

            else if (msg == "Harvest!")
                showHarvestConfirm();

            else if (msg == "Check Status")
            {
                llRegionSayTo(g_toucher, 0, buildStatusString());
            }

            else if (msg == "Replace Pot")
            {
                llRegionSayTo(g_toucher, 0,
                    "Rez a new pot from your inventory to replace this one.");
            }

            else if (msg == "Access" && isOwner(g_toucher))
                showAccessMenu();
        }

        // ACCESS CONTROL MENU  -  owner only
        else if (channel == DCHAN_ACCESS && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenAccess) { llListenRemove(g_listenAccess); g_listenAccess = 0; }

            if      (msg == "Back")           showMainMenu();
            else if (msg == "Add Player")     showAddPlayerMenu();
            else if (msg == "Remove Player")  showRemovePlayerMenu();
            else if (msg == "Lock Plant" || msg == "Unlock Plant")
            {
                g_plantLocked = !g_plantLocked;
                llLinksetDataWrite("plant_locked", (string)g_plantLocked);
                string lockState = "unlocked (group members and auth list can interact)";
                if (g_plantLocked) lockState = "LOCKED (owner only)";
                llRegionSayTo(g_ownerKey, 0, "Plant " + lockState + ".");
                showAccessMenu();
            }
        }

        // ADD AUTH  -  pick a nearby player to grant access
        else if (channel == DCHAN_ADD_AUTH && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenAddAuth) { llListenRemove(g_listenAddAuth); g_listenAddAuth = 0; }

            if (msg == "Back") { showAccessMenu(); return; }

            // Resolve truncated name to agent key
            list agents = llGetAgentList(AGENT_LIST_PARCEL, []);
            integer i;
            for (i = 0; i < llGetListLength(agents); i++)
            {
                key    a = llList2Key(agents, i);
                if (a == g_ownerKey) jump skip_ao;
                string n = llKey2Name(a);
                if (llGetSubString(n, 0, 11) == msg)
                {
                    string authData = llLinksetDataRead("auth_list");
                    list   authList = llParseString2List(authData, [","], []);
                    if (llListFindList(authList, [(string)a]) == -1)
                    {
                        if (authData == "") authData = (string)a;
                        else authData += "," + (string)a;
                        llLinksetDataWrite("auth_list", authData);
                        llRegionSayTo(g_ownerKey, 0, "Added " + n + " to plant access list.");
                    }
                    else
                        llRegionSayTo(g_ownerKey, 0, n + " is already authorized.");
                    showAccessMenu();
                    return;
                }
                @skip_ao;
            }
            llRegionSayTo(g_ownerKey, 0, "Couldn't find that player nearby.");
            showAccessMenu();
        }

        // REMOVE AUTH  -  remove a player from the auth list
        else if (channel == DCHAN_REM_AUTH && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenRemAuth) { llListenRemove(g_listenRemAuth); g_listenRemAuth = 0; }

            if (msg == "Back") { showAccessMenu(); return; }

            string authData = llLinksetDataRead("auth_list");
            list   authList = llParseString2List(authData, [","], []);
            integer n = llGetListLength(authList);
            integer i;
            for (i = 0; i < n; i++)
            {
                string k     = llList2String(authList, i);
                string pName = llKey2Name((key)k);
                if (pName == "") pName = llGetSubString(k, 0, 7) + "...";
                if (llGetSubString(pName, 0, 11) == msg)
                {
                    authList = llDeleteSubList(authList, i, i);
                    llLinksetDataWrite("auth_list", llDumpList2String(authList, ","));
                    llRegionSayTo(g_ownerKey, 0, "Removed " + pName + " from access list.");
                    showAccessMenu();
                    return;
                }
            }
            llRegionSayTo(g_ownerKey, 0, "Player not found in auth list.");
            showAccessMenu();
        }

        // SEED TIER SELECTION
        else if (channel == DCHAN_PLANT)
        {
            if (msg == "Back") { showMainMenu(); return; }
            integer tier = 0;
            if      (msg == "Reggie Seed") tier = 0;
            else if (msg == "Mids Seed")   tier = 1;
            else if (msg == "Loud Seed")   tier = 2;
            else if (msg == "Exotic Seed") tier = 3;
            g_pendingPlantTier = tier;
            showStrainMenu(tier);
        }

        // STRAIN SELECTION
        else if (channel == DCHAN_STRAIN)
        {
            if (msg == "Back") { showPotMenu(); return; }
            // Consume one seed from HUD inventory
            list qualStrings = ["reggie", "mids", "loud", "exotic"];
            string qualStr   = llList2String(qualStrings, g_pendingPlantTier);
            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_REMOVE_ITEM|seed_raw|" + msg + "|" + qualStr + "|1|");
            // Tell grow script to start growing
            string potType = "premium";
            if (g_potType_basic) potType = "basic";
            llMessageLinked(LINK_SET, PCHAN_GROW,
                "PLANT_SEED|" + msg + "|" + potType + "|" + (string)g_potUsesLeft,
                NULL_KEY);
        }

        // HARVEST CONFIRM
        else if (channel == DCHAN_CONFIRM)
        {
            if (msg == "Harvest Now!")
                llMessageLinked(LINK_SET, PCHAN_GROW, "DO_HARVEST", NULL_KEY);
            // Cancel just closes
        }

    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != PCHAN_GROW) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Grow script sent back current status
        if (cmd == "STATUS")
        {
            g_strainName  = llList2String(parts, 1);
            g_qualityTier = (integer)llList2String(parts, 2);
            g_stage       = (integer)llList2String(parts, 3);
            // parts 4 and 5 are timing, skip for display
            g_isWatered   = (integer)llList2String(parts, 6);
            g_fertApplied = (integer)llList2String(parts, 7);
            // parts 8 is fert tier
            string potType    = llList2String(parts, 9);
            g_potType_basic   = (potType == "basic");
            g_potUsesLeft     = (integer)llList2String(parts, 10);
            g_potSpent        = (integer)llList2String(parts, 11);
        }

        // Grow script says pot is spent
        else if (cmd == "POT_SPENT")
        {
            g_potSpent = TRUE;
        }

        // Grow script confirms plant was reset
        else if (cmd == "PLANT_RESET")
        {
            g_strainName  = "";
            g_stage       = 0;
            g_isWatered   = FALSE;
            g_fertApplied = FALSE;
            // g_potSpent is NOT cleared here  -  it is set by POT_SPENT just before
            // PLANT_RESET fires and must persist until the player replaces the pot
        }
    }
}
