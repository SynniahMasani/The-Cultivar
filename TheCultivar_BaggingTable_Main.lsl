// ================================================================
// THE CULTIVAR  -  Bagging Table Main Script
// Version: 1.0
// Handles: Touch input, HUD registration, flower inventory display,
//          bag size selection, consuming flower from HUD inventory,
//          and giving physical bag objects to the player.
//
// FLOW:
//   1. Player touches table
//   2. Table pings on TC_OBJECT_PING_CHAN  -> HUD responds with TC_REGISTER
//   3. Table now has owner's private channel
//   4. Table requests flower inventory via TC_INVENTORY_REQUEST
//   5. HUD sends back TC_INVENTORY_DATA with serialized flower slots
//   6. Table builds a menu from available flower
//   7. Player picks strain  -> picks bag size
//   8. Table checks they have enough flower
//   9. Table sends TC_REMOVE_ITEM to HUD  -> waits for TC_REMOVE_OK
//  10. Table gives player the appropriate bag object from its inventory
//      with strain/quality/packager/weight data written into it
//
// BAG SIZES AND FLOWER COST:
//   Dime    =  1g
//   Eighth  =  4g   (rounded for clean numbers)
//   Quarter =  7g
//   Half    = 14g
//   Oz      = 28g
//
// BAG OBJECTS STORED IN TABLE INVENTORY (must be copy/transfer):
//   TC_Bag_Dime
//   TC_Bag_Eighth
//   TC_Bag_Quarter
//   TC_Bag_Half
//   TC_Bag_Oz
//
// Each bag object contains TheCultivar_BaggingTable_Bag.lsl
// The table stamps strain/quality/packager/weight into the bag's
// description before giving it so the bag script can read it.
// ================================================================

// Public ping channel  -  table broadcasts here when touched
// HUD_Comms listens on this channel for world object pings
integer TC_OBJECT_PING_CHAN = -111222333;
integer HOVER_FADE_SECS = 30;

// Dialog channels
integer DCHAN_MAIN    = -66001;
integer DCHAN_STRAIN  = -66002;
integer DCHAN_SIZE    = -66003;
integer DCHAN_CONFIRM = -66004;

integer g_listenRegister;
integer g_replyChannel  = 0;   // random private channel used for TC_REGISTER reply
integer g_listenMain;
integer g_listenStrain;
integer g_listenSize;
integer g_listenConfirm;
integer g_listenHUD;
integer g_listenBagConfig = 0;  // listen for TC_BAG_READY from freshly rezzed bag
integer g_bagConfigChan   = 0;  // random channel used to configure rezzed bag

// State
key     g_ownerKey      = NULL_KEY;
string  g_ownerName     = "";
string  g_brandName     = "";   // brand name received from HUD (used as packager)
integer g_hudChannel    = 0;
integer g_registered    = FALSE;
integer g_busy          = FALSE; // prevents double-touch mid-transaction

// Available flower parsed from HUD inventory response
// Each entry: strainName ~ quality ~ quantity ~ packager (stride 4)
list    g_availableFlower;
integer FLOWER_STRIDE = 4;

// Current transaction state
string  g_selectedStrain   = "";
string  g_selectedQuality  = "";
string  g_selectedPackager = "";
integer g_selectedQty      = 0;
string  g_selectedSize     = "";
integer g_selectedCost     = 0;

// Bag size costs in grams
list BAG_SIZES  = ["Dime", "Eighth", "Quarter", "Half", "Oz"];
list BAG_COSTS  = [1,       4,        7,         14,     28];
list BAG_ASSETS = ["TC_Bag_Dime", "TC_Bag_Eighth",
                   "TC_Bag_Quarter", "TC_Bag_Half", "TC_Bag_Oz"];

// ----------------------------------------------------------------
// Close all open dialog listens
// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenMain)      { llListenRemove(g_listenMain);      g_listenMain      = 0; }
    if (g_listenStrain)    { llListenRemove(g_listenStrain);    g_listenStrain    = 0; }
    if (g_listenSize)      { llListenRemove(g_listenSize);      g_listenSize      = 0; }
    if (g_listenConfirm)   { llListenRemove(g_listenConfirm);   g_listenConfirm   = 0; }
    if (g_listenBagConfig) { llListenRemove(g_listenBagConfig); g_listenBagConfig = 0; }
}

// ----------------------------------------------------------------
// Ping the HUD  -  broadcasts table key on public ping channel
// HUD_Comms hears this and sends TC_REGISTER back on channel 0
// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    // Generate a random private reply channel so TC_REGISTER arrives reliably.
    // llRegionSayTo(objectKey, 0, ...) to world objects is unreliable in SL.
    g_replyChannel   = (integer)(llFrand(1000000.0) + 1000000) * -1;
    g_listenRegister = llListen(g_replyChannel, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|bagging_table|" +
        (string)g_replyChannel);
    llSetTimerEvent(10.0);
}

// ----------------------------------------------------------------
// Parse raw inventory string from HUD into usable flower list
// Only keeps flower_raw items
// Format from HUD: itemType~strainName~quality~qty~packager^...
// ----------------------------------------------------------------
parseFlowerInventory(string rawData)
{
    g_availableFlower = [];
    if (rawData == "") return;

    list slots = llParseString2List(rawData, ["^"], []);
    integer i;
    for (i = 0; i < llGetListLength(slots); i++)
    {
        list fields = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(fields) == 5)
        {
            if (llList2String(fields, 0) == "flower_raw")
            {
                // Store: strainName, quality, qty, packager
                g_availableFlower += [
                    llList2String(fields, 1),  // strainName
                    llList2String(fields, 2),  // quality
                    llList2String(fields, 3),  // qty
                    llList2String(fields, 4)   // packager
                ];
            }
        }
    }
}

// ----------------------------------------------------------------
// Build the main flower selection menu
// Shows available strains with quantity
// ----------------------------------------------------------------
showFlowerMenu()
{
    closeAllListens();

    if (llGetListLength(g_availableFlower) == 0)
    {
        llDialog(g_ownerKey,
            "=== BAGGING TABLE ===\n\nYou have no flower to bag.\nHarvest a plant first.",
            ["Close"], DCHAN_MAIN);
        g_listenMain = llListen(DCHAN_MAIN, "", g_ownerKey, "");
        return;
    }

    list buttons;
    string menuText = "=== SELECT FLOWER ===\nChoose a strain to bag:\n\n";
    list qualLabels = ["[R]", "[M]", "[L]", "[E]"]; // Reggie/Mids/Loud/Exotic
    list qualNames  = ["reggie", "mids", "loud", "exotic"];

    integer i;
    for (i = 0; i < llGetListLength(g_availableFlower) && i < FLOWER_STRIDE * 9;
         i += FLOWER_STRIDE)
    {
        string strain  = llList2String(g_availableFlower, i);
        string quality = llList2String(g_availableFlower, i + 1);
        string qty     = llList2String(g_availableFlower, i + 2);
        integer qIdx   = llListFindList(qualNames, [quality]);
        string  qLabel = llList2String(qualLabels, qIdx);

        string btnLabel = llGetSubString(strain, 0, 10); // truncate for button
        buttons += [btnLabel];
        menuText += qLabel + " " + strain + "  -  " + qty + "g\n";
    }
    buttons += ["Cancel"];

    g_listenStrain = llListen(DCHAN_STRAIN, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_STRAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Build the bag size menu for a chosen strain
// Only shows sizes the player has enough flower for
// ----------------------------------------------------------------
showSizeMenu()
{
    closeAllListens();

    list buttons;
    string menuText = "=== BAG SIZE ===\n" +
                      g_selectedQuality + " " + g_selectedStrain +
                      " (" + (string)g_selectedQty + "g available)\n\n";

    integer i;
    for (i = 0; i < llGetListLength(BAG_SIZES); i++)
    {
        integer cost = llList2Integer(BAG_COSTS, i);
        if (g_selectedQty >= cost)
        {
            string sizeName = llList2String(BAG_SIZES, i);
            buttons += [sizeName + " (" + (string)cost + "g)"];
            menuText += sizeName + "  -  " + (string)cost + "g\n";
        }
    }

    if (llGetListLength(buttons) == 0)
    {
        llDialog(g_ownerKey,
            "Not enough flower for even a dime bag.\nYou need at least 1g.",
            ["OK"], DCHAN_SIZE);
        g_listenSize = llListen(DCHAN_SIZE, "", g_ownerKey, "");
        return;
    }

    buttons += ["Back", "Cancel"];
    g_listenSize = llListen(DCHAN_SIZE, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_SIZE);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Show confirmation before bagging
// ----------------------------------------------------------------
showConfirm()
{
    closeAllListens();
    g_listenConfirm = llListen(DCHAN_CONFIRM, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== CONFIRM BAG ===\n\n" +
        "Bagging: " + g_selectedSize + "\n" +
        "Strain:  " + g_selectedQuality + " " + g_selectedStrain + "\n" +
        "Cost:    " + (string)g_selectedCost + "g of flower\n" +
        "Your tag will be on the bag.",
        ["Bag It!", "Cancel"], DCHAN_CONFIRM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Send REMOVE_ITEM to HUD then wait for TC_REMOVE_OK confirmation
// ----------------------------------------------------------------
requestRemoveFlower()
{
    g_busy = TRUE;
    // Format: TC_REMOVE_ITEM|itemType|strainName|quality|qty|packager
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_REMOVE_ITEM|flower_raw|" + g_selectedStrain + "|" +
        g_selectedQuality + "|" + (string)g_selectedCost + "|" +
        g_selectedPackager);
    // Listen for confirmation on our private listen
    llSetTimerEvent(10.0); // timeout if HUD doesn't respond
}

// ----------------------------------------------------------------
// Give the player their bag object
// Stamps strain data into the object description before giving
// ----------------------------------------------------------------
giveBag()
{
    // Find the right bag asset for the chosen size
    integer sIdx    = llListFindList(BAG_SIZES, [g_selectedSize]);
    string  bagName = llList2String(BAG_ASSETS, sIdx);

    if (llGetInventoryType(bagName) != INVENTORY_OBJECT)
    {
        llRegionSayTo(g_ownerKey, 0,
            "[TC BaggingTable] Bag template '" + bagName + "' is missing from " +
            "the table's inventory. This usually means the template was no-copy " +
            "and got consumed on a previous use. Re-add the bag templates and " +
            "make sure they have COPY permission before placing them in the table.");
        g_busy = FALSE;
        return;
    }

    // Rez the bag in-world and configure it via a private channel.
    // llGiveInventory() gives a blank template  -  the bag script reads
    // its data from llGetObjectDesc(), which we can only set AFTER rez.
    // The bag sends TC_BAG_READY on start_param, we reply with TC_BAG_CONFIG.

    g_bagConfigChan = (integer)(llFrand(999999.0) + 100000) * -1;
    if (g_listenBagConfig) llListenRemove(g_listenBagConfig);
    g_listenBagConfig = llListen(g_bagConfigChan, "", NULL_KEY, "");

    vector rezPos = llGetPos() + <0.0, 0.0, 0.7>;
    llRezObject(bagName, rezPos, ZERO_VECTOR, ZERO_ROTATION, g_bagConfigChan);

    llSetTimerEvent(8.0); // wait for TC_BAG_READY, or timeout
}

// ----------------------------------------------------------------
// Clear transaction state
// ----------------------------------------------------------------
resetTransaction()
{
    g_selectedStrain   = "";
    g_selectedQuality  = "";
    g_selectedPackager = "";
    g_selectedQty      = 0;
    g_selectedSize     = "";
    g_selectedCost     = 0;
}

// ----------------------------------------------------------------
// Check that all bag templates are present and have COPY permission.
// Called at startup so the owner knows immediately if something is wrong.
// llRezObject() silently consumes a no-copy object from inventory, so
// bag templates MUST be copy-permissioned or they deplete after each use.
// ----------------------------------------------------------------
checkBagInventory()
{
    string warn = "";
    integer i;
    for (i = 0; i < llGetListLength(BAG_ASSETS); i++)
    {
        string bagName = llList2String(BAG_ASSETS, i);
        if (llGetInventoryType(bagName) != INVENTORY_OBJECT)
        {
            warn += "\n  MISSING: " + bagName;
        }
        else if (!(llGetInventoryPermMask(bagName, MASK_NEXT) & PERM_COPY))
        {
            // Check next-owner (recipient) copy permission — the buyer receives
            // the bag, so what matters is whether THEY can copy it, not the table.
            warn += "\n  NO-COPY for recipient (will deplete on use!): " + bagName;
        }
    }
    if (warn != "")
    {
        llRegionSayTo(llGetOwner(), 0,
            "[TC BaggingTable] Setup problem detected:" + warn +
            "\nAll bag templates must be inside the table AND set to COPY permission.");
    }
}

// ----------------------------------------------------------------
// Update hover text based on registration state
// ----------------------------------------------------------------
updateHoverText()
{
    if (g_registered)
        llSetText("THE CULTIVAR\nBagging Table\nTouch to bag your flower",
                  <0.4, 0.9, 0.4>, 1.0);
    else
        llSetText("THE CULTIVAR\nBagging Table\nTouch to begin",
                  <0.6, 0.6, 0.6>, 1.0);
}

// ================================================================
default
{
    state_entry()
    {
        // Registration listener is opened in pingHUD() on a random reply channel.
        // No persistent channel-0 listen needed.
        updateHoverText();
        checkBagInventory();
        llSetTimerEvent(HOVER_FADE_SECS);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    touch_start(integer nd)
    {
        updateHoverText();
        key toucher = llDetectedKey(0);

        // Only owner can use this table
        if (toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0,
                "This bagging table belongs to " +
                llGetDisplayName(llGetOwner()) + ".");
            return;
        }

        if (g_busy)
        {
            llRegionSayTo(toucher, 0, "Hold on  -  finishing previous action...");
            return;
        }

        g_ownerKey  = toucher;
        g_ownerName = llGetDisplayName(toucher);

        // Re-register each touch to make sure channel is fresh
        pingHUD();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- HUD Registration response (private reply channel) ----
        if (channel == g_replyChannel && cmd == "TC_REGISTER")
        {
            // TC_REGISTER|ownerKey|privateChannel|ownerName
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return; // not our owner

            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);
            g_brandName  = llList2String(parts, 4);
            if (g_brandName == "") g_brandName = g_ownerName;
            g_registered = TRUE;

            if (g_listenRegister) llListenRemove(g_listenRegister);
            // Set up persistent listen on HUD's private channel
            if (g_listenHUD) llListenRemove(g_listenHUD);
            g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");

            llSetTimerEvent(0.0);
            updateHoverText();

            // Request flower inventory from HUD
            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_INVENTORY_REQUEST|flower_raw|" + (string)llGetKey());
        }

        // ---- HUD sends back inventory data ----
        else if (channel == g_hudChannel && cmd == "TC_INVENTORY_DATA")
        {
            // TC_INVENTORY_DATA|rawSerializedInventory
            string rawData = llList2String(parts, 1);
            parseFlowerInventory(rawData);
            llSetTimerEvent(0.0);
            showFlowerMenu();
        }

        // ---- HUD confirms item removed successfully ----
        else if (channel == g_hudChannel && cmd == "TC_REMOVE_OK")
        {
            llSetTimerEvent(0.0);
            giveBag();
        }

        // ---- HUD says removal failed (not enough) ----
        else if (channel == g_hudChannel && cmd == "TC_REMOVE_FAIL")
        {
            llSetTimerEvent(0.0);
            g_busy = FALSE;
            llRegionSayTo(g_ownerKey, 0,
                "Not enough flower for that bag size. Try a smaller size.");
            resetTransaction();
        }

        // ---- Bag configuration handshake ----
        // Bag rezzes, fires on_rez(configChan), listens, and sends TC_BAG_READY.
        // We reply with TC_BAG_CONFIG so the bag can write its description.
        else if (channel == g_bagConfigChan && cmd == "TC_BAG_READY")
        {
            if (g_listenBagConfig) { llListenRemove(g_listenBagConfig); g_listenBagConfig = 0; }
            llSetTimerEvent(0.0);

            // Send full strain data to the bag on its config channel
            llRegionSay(g_bagConfigChan,
                "TC_BAG_CONFIG|" + g_selectedStrain + "|" +
                g_selectedQuality + "|" + g_ownerName + "|" +
                (string)g_selectedCost);

            // Tell HUD to record the bag in virtual inventory
            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_ADD_ITEM|bag_" + llToLower(g_selectedSize) + "|" +
                g_selectedStrain + "|" + g_selectedQuality + "|1|" + g_brandName);

            // Notify player
            llRegionSayTo(g_ownerKey, 0,
                "Bagged: " + g_selectedSize + " of " +
                g_selectedQuality + " " + g_selectedStrain +
                " (" + (string)g_selectedCost + "g used)");

            // Visual feedback
            llParticleSystem([
                PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK | PSYS_PART_EMISSIVE_MASK,
                PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
                PSYS_PART_START_COLOR,     <0.4, 0.9, 0.4>,
                PSYS_PART_END_COLOR,       <0.2, 0.6, 0.2>,
                PSYS_PART_START_ALPHA,     0.9,
                PSYS_PART_END_ALPHA,       0.0,
                PSYS_PART_START_SCALE,     <0.05, 0.05, 0.0>,
                PSYS_PART_END_SCALE,       <0.02, 0.02, 0.0>,
                PSYS_PART_MAX_AGE,         1.5,
                PSYS_SRC_BURST_RATE,       0.1,
                PSYS_SRC_BURST_PART_COUNT, 10,
                PSYS_SRC_MAX_AGE,          0.3
            ]);
            llPlaySound("bag_rustle", 0.6);

            g_busy = FALSE;
            resetTransaction();
        }

        // ---- Dialog responses ----

        // Strain selection
        else if (channel == DCHAN_STRAIN)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);

            if (msg == "Cancel") { resetTransaction(); return; }

            // Match button label back to full strain name in our list
            integer i;
            for (i = 0; i < llGetListLength(g_availableFlower); i += FLOWER_STRIDE)
            {
                string strain = llList2String(g_availableFlower, i);
                if (llGetSubString(strain, 0, 10) == msg)
                {
                    g_selectedStrain   = strain;
                    g_selectedQuality  = llList2String(g_availableFlower, i + 1);
                    g_selectedQty      = (integer)llList2String(g_availableFlower, i + 2);
                    g_selectedPackager = llList2String(g_availableFlower, i + 3);
                    jump found_strain;
                }
            }
            llRegionSayTo(g_ownerKey, 0, "Couldn't find that strain. Please try again.");
            showFlowerMenu();
            return;
            @found_strain;
            showSizeMenu();
        }

        // Bag size selection
        else if (channel == DCHAN_SIZE)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);

            if (msg == "Cancel") { resetTransaction(); return; }
            if (msg == "Back")   { showFlowerMenu(); return; }

            // Parse the size name from "Dime (1g)" style button
            list sizeParts = llParseString2List(msg, [" "], []);
            string sizeName = llList2String(sizeParts, 0);
            integer sIdx    = llListFindList(BAG_SIZES, [sizeName]);
            if (sIdx == -1)
            {
                llRegionSayTo(g_ownerKey, 0, "Unknown size. Try again.");
                showSizeMenu();
                return;
            }

            g_selectedSize = sizeName;
            g_selectedCost = llList2Integer(BAG_COSTS, sIdx);
            showConfirm();
        }

        // Confirmation
        else if (channel == DCHAN_CONFIRM)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);

            if (msg == "Cancel") { resetTransaction(); return; }
            if (msg == "Bag It!")
                requestRemoveFlower();
        }

        // Main fallback (empty flower close button)
        else if (channel == DCHAN_MAIN)
        {
            // Just closes  -  nothing to do
        }
    }

    timer()
    {
        // Idle fade: no active transaction — fade hover text and stop timer
        if (!g_busy)
        {
            if (g_registered)
                llSetText("THE CULTIVAR\nBagging Table\nTouch to bag your flower",
                          <0.4, 0.9, 0.4>, 0.0);
            else
                llSetText("THE CULTIVAR\nBagging Table\nTouch to begin",
                          <0.6, 0.6, 0.6>, 0.0);
            llSetTimerEvent(0.0);
            return;
        }

        // Timeout  -  clean up and reset
        closeAllListens();
        g_busy = FALSE;

        if (!g_registered)
        {
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't connect to your HUD. Make sure your Cultivar HUD is worn.");
            g_ownerKey = NULL_KEY;
        }
        else
        {
            // Transaction timeout
            if (g_selectedStrain != "")
            {
                llRegionSayTo(g_ownerKey, 0, "Bagging session timed out.");
                resetTransaction();
            }
        }
        llSetTimerEvent(HOVER_FADE_SECS);
    }
}
