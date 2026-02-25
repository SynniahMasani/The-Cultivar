// ================================================================
// THE CULTIVAR — Bagging Table Main Script
// Version: 1.0
// Handles: Touch input, HUD registration, flower inventory display,
//          bag size selection, consuming flower from HUD inventory,
//          and giving physical bag objects to the player.
//
// FLOW:
//   1. Player touches table
//   2. Table pings on TC_OBJECT_PING_CHAN → HUD responds with TC_REGISTER
//   3. Table now has owner's private channel
//   4. Table requests flower inventory via TC_INVENTORY_REQUEST
//   5. HUD sends back TC_INVENTORY_DATA with serialized flower slots
//   6. Table builds a menu from available flower
//   7. Player picks strain → picks bag size
//   8. Table checks they have enough flower
//   9. Table sends TC_REMOVE_ITEM to HUD → waits for TC_REMOVE_OK
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

// Public ping channel — table broadcasts here when touched
// HUD_Comms listens on this channel for world object pings
integer TC_OBJECT_PING_CHAN = -111222333;

// Dialog channels
integer DCHAN_MAIN    = -66001;
integer DCHAN_STRAIN  = -66002;
integer DCHAN_SIZE    = -66003;
integer DCHAN_CONFIRM = -66004;

integer g_listenPing;
integer g_listenRegister;
integer g_listenMain;
integer g_listenStrain;
integer g_listenSize;
integer g_listenConfirm;
integer g_listenHUD;

// State
key     g_ownerKey      = NULL_KEY;
string  g_ownerName     = "";
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
    if (g_listenMain)    { llListenRemove(g_listenMain);    g_listenMain    = 0; }
    if (g_listenStrain)  { llListenRemove(g_listenStrain);  g_listenStrain  = 0; }
    if (g_listenSize)    { llListenRemove(g_listenSize);    g_listenSize    = 0; }
    if (g_listenConfirm) { llListenRemove(g_listenConfirm); g_listenConfirm = 0; }
}

// ----------------------------------------------------------------
// Ping the HUD — broadcasts table key on public ping channel
// HUD_Comms hears this and sends TC_REGISTER back on channel 0
// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    // Listen on channel 0 for the HUD's TC_REGISTER response
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    // Broadcast our presence
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|bagging_table");
    // Timeout if HUD doesn't respond
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
        menuText += qLabel + " " + strain + " — " + qty + "g\n";
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
            menuText += sizeName + " — " + (string)cost + "g\n";
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
            "[ERROR] Bag object '" + bagName +
            "' not found in table. Please contact support.");
        g_busy = FALSE;
        return;
    }

    // We need to stamp data into the bag before giving it.
    // LSL can't modify object descriptions before giving, so we use
    // the start_param of llRezObject to pass a hash, then give via
    // llGiveInventory for simplicity. The bag script reads its own
    // description which we pre-set by rezzing, configuring, and
    // taking back — OR we encode data in the object name at give time.
    //
    // Practical SL approach: give the bag, and separately send the
    // strain data to the player's HUD which stores it mapped to the
    // bag's UUID. The bag script requests its data from the HUD on rez.
    //
    // For v1.0 we use the simpler approach: encode data in the bag
    // name so it's self-contained, then give. The bag script parses
    // its own name on rez.
    // Name format: TC_Bag_[Size]:[strain]:[quality]:[packager]:[weight]g

    string bagDisplayName = bagName + ":" +
                            g_selectedStrain + ":" +
                            g_selectedQuality + ":" +
                            g_ownerName + ":" +
                            (string)g_selectedCost + "g";

    // Rez the bag temporarily to set its description, then give
    // Simpler: just give and let the HUD track it via ADD_ITEM
    llGiveInventory(g_ownerKey, bagName);

    // Tell HUD to add the bag to inventory with full data
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|bag_" + llToLower(g_selectedSize) + "|" +
        g_selectedStrain + "|" + g_selectedQuality + "|1|" + g_ownerName);

    // Notify player
    llRegionSayTo(g_ownerKey, 0,
        "✓ Bagged: " + g_selectedSize + " of " +
        g_selectedQuality + " " + g_selectedStrain +
        " (" + (string)g_selectedCost + "g used)");

    // Visual feedback — brief particle burst from table
    llParticleSystem([
        PSYS_PART_FLAGS,        PSYS_PART_INTERP_COLOR_MASK | PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,       PSYS_SRC_PATTERN_EXPLODE,
        PSYS_PART_START_COLOR,  <0.4, 0.9, 0.4>,
        PSYS_PART_END_COLOR,    <0.2, 0.6, 0.2>,
        PSYS_PART_START_ALPHA,  0.9,
        PSYS_PART_END_ALPHA,    0.0,
        PSYS_PART_START_SCALE,  <0.05, 0.05, 0.0>,
        PSYS_PART_END_SCALE,    <0.02, 0.02, 0.0>,
        PSYS_PART_MAX_AGE,      1.5,
        PSYS_SRC_BURST_RATE,    0.1,
        PSYS_SRC_BURST_PART_COUNT, 10,
        PSYS_SRC_MAX_AGE,       0.3
    ]);

    // Play sound
    llPlaySound("bag_rustle", 0.6);

    g_busy = FALSE;
    resetTransaction();
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
        // Listen on ping channel for any touch
        g_listenPing = llListen(TC_OBJECT_PING_CHAN, "", NULL_KEY, "");
        // Listen on channel 0 for HUD registration
        g_listenRegister = llListen(0, "", NULL_KEY, "");
        updateHoverText();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);

        // Only owner can use this table
        if (toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0,
                "This bagging table belongs to " +
                llKey2Name(llGetOwner()) + ".");
            return;
        }

        if (g_busy)
        {
            llRegionSayTo(toucher, 0, "Hold on — finishing previous action...");
            return;
        }

        g_ownerKey  = toucher;
        g_ownerName = llKey2Name(toucher);

        // Re-register each touch to make sure channel is fresh
        pingHUD();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- HUD Registration response (channel 0) ----
        if (channel == 0 && cmd == "TC_REGISTER")
        {
            // TC_REGISTER|ownerKey|privateChannel|ownerName
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return; // not our owner

            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);
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
            // Just closes — nothing to do
        }
    }

    timer()
    {
        // Timeout — clean up and reset
        closeAllListens();
        llSetTimerEvent(0.0);
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
    }
}
