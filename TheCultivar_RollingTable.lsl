// ================================================================
// THE CULTIVAR  -  Rolling Tray Script
// Version: 1.2
// Lives inside: any TC rolling tray variant (all designs, one script)
//
// WHAT IT DOES:
//   Players touch the tray to roll harvested flower into smokeable
//   items. Registers with the player's worn HUD via the standard
//   TC ping/register handshake, then walks through:
//     strain → roll type → quantity → confirm
//   On confirmation, removes flower from HUD inventory and adds the
//   rolled items in return. No physical objects are given.
//
// ROLL COSTS:
//   Joint  : 1g per item
//   Blunt  : 2g per item
//   Spliff : 1g per item
//
// COMMUNICATION:
//   Ping broadcast : TC_OBJECT_PING_CHAN  (-111222333)
//   HUD private    : channel received in TC_REGISTER parts[2]
//
// PING / REGISTER FLOW:
//   1. Touch → pingHUD() → llRegionSay(TC_OBJECT_PING_CHAN,
//        "TC_PING|key|rolling_tray|replyChannel")
//   2. HUD_Comms responds on replyChannel:
//        "TC_REGISTER|ownerKey|hudChannel|ownerName|brandName"
//   3. Tray stores g_hudChannel, opens listen, requests inventory:
//        "TC_INVENTORY_REQUEST|flower_raw|trayKey"
//   4. HUD responds: "TC_INVENTORY_DATA|rawInventory"
//   5. Menus shown → confirm → "TC_REMOVE_ITEM|..." → wait for OK
//   6. "TC_REMOVE_OK" → "TC_ADD_ITEM|..." + particle burst + notify
//
// PARTICLE DISPATCH  (llMessageLinked, num=2000):
//   "HERB_PARTICLES|<quality>"  — green herb-drop effect (steps 0-2)
//   "SMOKE_PARTICLES|<quality>" — quality-colored wisps   (steps 3-4)
//   "BURST_PARTICLES|<quality>" — celebration explode     (finish)
//   "STOP_PARTICLES"            — clear all emitters
//
// DIALOG CHANNELS  (negative, distinct from BaggingTable -66001-66004):
//   DCHAN_STRAIN   = -77001
//   DCHAN_ROLLTYPE = -77002
//   DCHAN_QTY      = -77003
//   DCHAN_CONFIRM  = -77004
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

integer DCHAN_STRAIN   = -77001;
integer DCHAN_ROLLTYPE = -77002;
integer DCHAN_QTY      = -77003;
integer DCHAN_CONFIRM  = -77004;

integer g_replyChannel   = 0;
integer g_listenRegister = 0;
integer g_listenHUD      = 0;
integer g_listenStrain   = 0;
integer g_listenRollType = 0;
integer g_listenQty      = 0;
integer g_listenConfirm  = 0;

key     g_ownerKey    = NULL_KEY;
string  g_ownerName   = "";
string  g_brandName   = "";
integer g_hudChannel  = 0;
integer g_registered  = FALSE;
integer g_busy        = FALSE;
integer g_particleClear     = FALSE; // TRUE while post-craft 3s timer is running
integer g_rollStep          = 0;     // current step of the rolling sequence (0-5)
integer g_inRollingSequence = FALSE; // TRUE while rolling animation is playing

list    g_availableFlower;
integer FLOWER_STRIDE = 4;         // stride: strainName, quality, qty, packager

string  g_selectedStrain   = "";
string  g_selectedQuality  = "";
string  g_selectedPackager = "";
integer g_selectedQty      = 0;   // grams of selected strain available
string  g_selectedRollType = "";  // "joint" | "blunt" | "spliff"
integer g_selectedCount    = 0;   // number of items to roll
integer g_rollCost         = 0;   // grams per item
integer g_totalCost        = 0;   // g_selectedCount * g_rollCost
integer g_papersCount      = 0;   // Var Papers available in inventory
integer g_removingPapers   = FALSE; // TRUE while awaiting papers TC_REMOVE_OK

// ----------------------------------------------------------------
// Ping the HUD using a random private reply channel.
// HUD_Comms listens on TC_OBJECT_PING_CHAN and sends TC_REGISTER
// back on the reply channel.
// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_replyChannel   = (integer)(llFrand(1000000.0) + 1000000) * -1;
    g_listenRegister = llListen(g_replyChannel, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|rolling_tray|" +
        (string)g_replyChannel);
    llSetTimerEvent(10.0);
}

// ----------------------------------------------------------------
// Parse raw HUD inventory string; keep only flower_raw entries.
// Input format per slot: itemType~strainName~quality~qty~packager
// Slots separated by ^
// Stored as stride-4 list: strainName, quality, qty, packager
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
        if (llGetListLength(fields) == 5 &&
            llList2String(fields, 0) == "flower_raw")
        {
            g_availableFlower += [
                llList2String(fields, 1),
                llList2String(fields, 2),
                llList2String(fields, 3),
                llList2String(fields, 4)
            ];
        }
    }
}

// ----------------------------------------------------------------
// Count total Var Papers available from full inventory data.
// ----------------------------------------------------------------
integer parsePapersCount(string rawData)
{
    integer total = 0;
    if (rawData == "") return total;
    list slots = llParseString2List(rawData, ["^"], []);
    integer i;
    for (i = 0; i < llGetListLength(slots); i++)
    {
        list fields = llParseString2List(llList2String(slots, i), ["~"], []);
        if (llGetListLength(fields) == 5 &&
            llList2String(fields, 0) == "papers_raw")
            total += (integer)llList2String(fields, 3);
    }
    return total;
}

// ----------------------------------------------------------------
// Close all active dialog listeners
// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenStrain)   { llListenRemove(g_listenStrain);   g_listenStrain   = 0; }
    if (g_listenRollType) { llListenRemove(g_listenRollType); g_listenRollType = 0; }
    if (g_listenQty)      { llListenRemove(g_listenQty);      g_listenQty      = 0; }
    if (g_listenConfirm)  { llListenRemove(g_listenConfirm);  g_listenConfirm  = 0; }
}

// ----------------------------------------------------------------
// Clear all transaction state variables
// ----------------------------------------------------------------
resetTransaction()
{
    g_selectedStrain   = "";
    g_selectedQuality  = "";
    g_selectedPackager = "";
    g_selectedQty      = 0;
    g_selectedRollType = "";
    g_selectedCount    = 0;
    g_rollCost         = 0;
    g_totalCost        = 0;
    g_removingPapers   = FALSE;
}

// ----------------------------------------------------------------
// STEP 1 — Show the flower (strain) selection menu.
// Lists up to 9 strains with quality label and gram count.
// ----------------------------------------------------------------
showFlowerMenu()
{
    closeAllListens();

    if (llGetListLength(g_availableFlower) == 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "No flower available to roll. Harvest a plant first.");
        g_busy = FALSE;
        return;
    }

    list   qualNames  = ["reggie", "mids", "loud", "exotic"];
    list   qualLabels = ["[R]", "[M]", "[L]", "[E]"];
    list   buttons;
    string menuText = "=== SELECT FLOWER ===\nChoose a strain to roll:\n\n";

    integer i;
    for (i = 0; i < llGetListLength(g_availableFlower) && i < FLOWER_STRIDE * 9;
         i += FLOWER_STRIDE)
    {
        string  strain  = llList2String(g_availableFlower, i);
        string  quality = llList2String(g_availableFlower, i + 1);
        string  qty     = llList2String(g_availableFlower, i + 2);
        integer qIdx    = llListFindList(qualNames, [quality]);
        string  qLabel  = "[R]";
        if (qIdx >= 0) qLabel = llList2String(qualLabels, qIdx);

        buttons  += [llGetSubString(strain, 0, 10)];
        menuText += qLabel + " " + strain + "  -  " + qty + "g\n";
    }
    buttons += ["Cancel"];

    if (llStringLength(menuText) > 480)
        menuText = llGetSubString(menuText, 0, 477) + "...";

    g_listenStrain = llListen(DCHAN_STRAIN, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_STRAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 2 — Show the roll type menu.
// Blunt (2g) button is omitted if the player has less than 2g.
// ----------------------------------------------------------------
showRollTypeMenu()
{
    closeAllListens();

    if (g_selectedQty < 1)
    {
        llRegionSayTo(g_ownerKey, 0,
            "Not enough flower to roll anything. You need at least 1g.");
        g_busy = FALSE;
        resetTransaction();
        return;
    }

    string menuText =
        "=== ROLL TYPE ===\n" +
        "Rolling: " + g_selectedStrain + "\n" +
        "Quality: " + g_selectedQuality + "\n" +
        "Available: " + (string)g_selectedQty + "g\n\n" +
        "Select what to roll:";

    if (g_selectedQty < 2)
        menuText += "\n(Blunt requires 2g — not enough)";

    if (g_papersCount < 1)
        menuText += "\n(Joint/Spliff require Var Papers — none in inventory)";
    else
        menuText += "\nVar Papers: " + (string)g_papersCount;

    // If nothing is rollable at all, bail out early
    if (g_papersCount < 1 && g_selectedQty < 2)
    {
        llRegionSayTo(g_ownerKey, 0,
            "Nothing to roll: need Var Papers for joints/spliffs, and 2g+ for blunts.");
        g_busy = FALSE;
        resetTransaction();
        return;
    }

    list buttons;
    if (g_papersCount >= 1)
        buttons += ["Joint (1g)"];
    if (g_selectedQty >= 2)
        buttons += ["Blunt (2g)"];
    if (g_papersCount >= 1)
        buttons += ["Spliff (1g)"];
    buttons += ["Back", "Cancel"];

    g_listenRollType = llListen(DCHAN_ROLLTYPE, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_ROLLTYPE);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 3 — Show the quantity menu.
// Offers 1 / 2 / 5 / 10, capped by floor(available / cost).
// ----------------------------------------------------------------
showQuantityMenu()
{
    closeAllListens();

    integer maxCount = g_selectedQty / g_rollCost;
    if ((g_selectedRollType == "joint" || g_selectedRollType == "spliff") &&
        g_papersCount < maxCount)
        maxCount = g_papersCount;

    if (maxCount <= 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "Not enough flower. You need " + (string)g_rollCost +
            "g per " + g_selectedRollType + ".");
        g_busy = FALSE;
        resetTransaction();
        return;
    }

    string menuText =
        "=== HOW MANY? ===\n" +
        g_selectedRollType + "  -  " + g_selectedQuality + " " + g_selectedStrain + "\n" +
        "Cost: " + (string)g_rollCost + "g each\n" +
        "Available: " + (string)g_selectedQty + "g\n";

    if (g_selectedRollType == "joint" || g_selectedRollType == "spliff")
        menuText += "Var Papers: " + (string)g_papersCount + "\n";

    menuText += "Max you can roll: " + (string)maxCount + "\n";

    list counts = [1, 2, 5, 10];
    list buttons;
    integer c;
    for (c = 0; c < llGetListLength(counts); c++)
    {
        integer n = llList2Integer(counts, c);
        if (n <= maxCount)
            buttons += [(string)n];
    }
    buttons += ["Cancel"];

    g_listenQty = llListen(DCHAN_QTY, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_QTY);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// STEP 4 — Show confirmation summary before committing.
// ----------------------------------------------------------------
showConfirmMenu()
{
    closeAllListens();

    string confirmMsg =
        "=== CONFIRM ROLL ===\n" +
        (string)g_selectedCount + "x " + g_selectedRollType +
        "  -  " + g_selectedQuality + " " + g_selectedStrain + "\n" +
        "Flower used: " + (string)g_totalCost + "g\n";

    if (g_selectedRollType == "joint" || g_selectedRollType == "spliff")
        confirmMsg += "Papers: " + (string)g_selectedCount + "x Var Papers\n";

    confirmMsg +=
        "Rolled by: " + g_brandName + "\n" +
        "Confirm?";

    g_listenConfirm = llListen(DCHAN_CONFIRM, "", g_ownerKey, "");
    llDialog(g_ownerKey, confirmMsg, ["Roll It!", "Cancel"], DCHAN_CONFIRM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Send TC_REMOVE_ITEM to HUD and wait for TC_REMOVE_OK / FAIL.
// ----------------------------------------------------------------
sendRemoveRequest()
{
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_REMOVE_ITEM|flower_raw|" + g_selectedStrain + "|" +
        g_selectedQuality + "|" + (string)g_totalCost + "|" +
        g_selectedPackager);
    llSetTimerEvent(10.0);
}

// ----------------------------------------------------------------
// Send TC_REMOVE_ITEM for Var Papers to HUD.
// ----------------------------------------------------------------
sendPapersRemoveRequest()
{
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_REMOVE_ITEM|papers_raw|Var Papers|standard|" +
        (string)g_selectedCount + "|Var");
    llSetTimerEvent(10.0);
}

// ----------------------------------------------------------------
// Play a 6-step rolling animation sequence (steps 0-5, 3 s apart).
// Step 0 fires immediately; the timer advances steps 1-5.
// TC_REMOVE_ITEM is sent only after step 5 completes.
// ----------------------------------------------------------------
startRollingSequence()
{
    g_inRollingSequence = TRUE;
    g_busy              = TRUE;
    g_rollStep          = 0;

    // Notify HUD to start rolling idle animation
    llRegionSayTo(g_ownerKey, g_hudChannel, "TC_PLAY_ANIM|rolling_idle");

    // Step 0 message
    if (g_selectedRollType == "blunt")
        llSay(0, g_ownerName + " splits the cigar wrap carefully.");
    else
        llSay(0, g_ownerName + " pulls out a Var Paper and gets to work.");

    // Steps 0-2: green herb particles (flower being packed)
    llMessageLinked(LINK_SET, 2000, "HERB_PARTICLES|" + g_selectedQuality, NULL_KEY);

    llSetTimerEvent(3.0);
}

// ----------------------------------------------------------------
// HUD confirmed the removal — add rolled items, fire effects.
// ----------------------------------------------------------------
finishCraft()
{
    // Add rolled items to HUD inventory
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_ADD_ITEM|" + g_selectedRollType + "|" + g_selectedStrain + "|" +
        g_selectedQuality + "|" + (string)g_selectedCount + "|" +
        g_brandName);

    // Celebration particle burst
    llMessageLinked(LINK_SET, 2000, "BURST_PARTICLES|" + g_selectedQuality, NULL_KEY);
    llPlaySound("roll_complete", 0.6);

    // Announce in nearby chat so others can see the result
    string plural = "";
    if (g_selectedCount > 1) plural = "s";
    llSay(0, g_ownerName + " rolled " + (string)g_selectedCount + "x " +
        g_selectedQuality + " " + g_selectedStrain + " " +
        g_selectedRollType + plural +
        " (" + (string)g_totalCost + "g used).");

    // Mark for particle clear after 3s; reset transaction now
    g_particleClear = TRUE;
    resetTransaction();
    llSetTimerEvent(3.0);
}

// ----------------------------------------------------------------
// Update hover text based on registration state
// ----------------------------------------------------------------
updateHoverText()
{
    if (g_registered)
        llSetText("THE CULTIVAR\nRolling Tray\nTouch to roll your flower",
                  <0.9, 0.85, 0.5>, 1.0);
    else
        llSetText("THE CULTIVAR\nRolling Tray\nTouch to roll",
                  <0.8, 0.7, 0.4>, 1.0);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llGetDisplayName(g_ownerKey);
        updateHoverText();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    timer()
    {
        // ── Rolling sequence: advance one step every 3 s ─────────
        if (g_inRollingSequence)
        {
            g_rollStep++;

            // Per-step owner messages
            if (g_selectedRollType == "blunt")
            {
                if (g_rollStep == 1)
                    llSay(0, g_ownerName + " empties the tobacco and packs in the " +
                               g_selectedStrain + ".");
                else if (g_rollStep == 2)
                    llSay(0, g_ownerName + " loads the wrap with " +
                               g_selectedQuality + " flower.");
                else if (g_rollStep == 3)
                    llSay(0, g_ownerName + " rolls it tight, sealing the edges.");
                else if (g_rollStep == 4)
                    llSay(0, g_ownerName + " licks and presses the seam shut.");
                else if (g_rollStep == 5)
                    llSay(0, g_ownerName + " twists both ends. That's a backwood.");
            }
            else
            {
                if (g_rollStep == 1)
                    llSay(0, g_ownerName + " grinds the " + g_selectedStrain +
                               " and spreads it evenly.");
                else if (g_rollStep == 2)
                    llSay(0, g_ownerName + " tucks the edge and starts the roll.");
                else if (g_rollStep == 3)
                    llSay(0, g_ownerName + " rolls it firm and even.");
                else if (g_rollStep == 4)
                    llSay(0, g_ownerName + " licks the edge and seals it.");
                else if (g_rollStep == 5)
                    llSay(0, g_ownerName + " twists the tip. Perfect.");
            }

            // Switch to quality-colored wisp particles at step 3
            if (g_rollStep == 3)
                llMessageLinked(LINK_SET, 2000, "SMOKE_PARTICLES|" + g_selectedQuality, NULL_KEY);

            // Start tray rotation at step 1
            if (g_rollStep == 1)
            {
                llSetLinkPrimitiveParamsFast(2, [
                    PRIM_OMEGA, <0.0, 0.0, 1.0>, 0.3, 0.5
                ]);
            }

            // Final step: wrap up sequence and send TC_REMOVE_ITEM
            if (g_rollStep >= 5)
            {
                llMessageLinked(LINK_SET, 2000, "STOP_PARTICLES", NULL_KEY);
                llSetLinkPrimitiveParamsFast(2, [
                    PRIM_OMEGA, <0.0, 0.0, 1.0>, 0.0, 0.0
                ]);
                llRegionSayTo(g_ownerKey, g_hudChannel, "TC_STOP_ANIM|rolling_idle");
                g_inRollingSequence = FALSE;
                sendRemoveRequest();
                return;
            }

            llSetTimerEvent(3.0);
            return;
        }

        llSetTimerEvent(0.0);

        // Post-craft particle clear fires 3s after finishCraft()
        if (g_particleClear)
        {
            g_particleClear = FALSE;
            llMessageLinked(LINK_SET, 2000, "STOP_PARTICLES", NULL_KEY);
            g_busy = FALSE;
            return;
        }

        // General timeout: HUD not found, or player abandoned a menu
        closeAllListens();
        g_busy = FALSE;

        if (!g_registered)
        {
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't connect to your HUD. Make sure your Cultivar HUD is worn.");
        }
        else if (g_selectedStrain != "")
        {
            llRegionSayTo(g_ownerKey, 0, "Rolling session timed out.");
            resetTransaction();
        }
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);

        if (toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0,
                "This rolling tray belongs to " + llGetDisplayName(llGetOwner()) + ".");
            return;
        }

        if (g_busy)
        {
            llRegionSayTo(g_ownerKey, 0, "Hold on  -  finishing previous action...");
            return;
        }

        g_busy      = TRUE;
        g_ownerKey  = toucher;
        g_ownerName = llGetDisplayName(toucher);
        pingHUD();
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- HUD registration response (private reply channel) ----
        if (channel == g_replyChannel && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;

            g_hudChannel = (integer)llList2String(parts, 2);
            g_ownerName  = llList2String(parts, 3);
            g_brandName  = llList2String(parts, 4);
            if (g_brandName == "") g_brandName = g_ownerName;
            g_registered = TRUE;

            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            if (g_listenHUD)      { llListenRemove(g_listenHUD);      g_listenHUD      = 0; }
            g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");

            updateHoverText();

            // Request full inventory so we can check both flower and papers.
            // Keep a 15s timeout in case HUD never responds.
            llRegionSayTo(g_ownerKey, g_hudChannel,
                "TC_INVENTORY_REQUEST||" + (string)llGetKey());
            llSetTimerEvent(15.0);
        }

        // ---- HUD sends inventory data ----
        else if (channel == g_hudChannel && cmd == "TC_INVENTORY_DATA")
        {
            string rawInv = llList2String(parts, 1);
            parseFlowerInventory(rawInv);
            g_papersCount = parsePapersCount(rawInv);
            showFlowerMenu();
        }

        // ---- HUD confirmed item removal ----
        else if (channel == g_hudChannel && cmd == "TC_REMOVE_OK")
        {
            llSetTimerEvent(0.0);
            if (!g_removingPapers &&
                (g_selectedRollType == "joint" || g_selectedRollType == "spliff"))
            {
                // Flower removed — now remove papers
                g_removingPapers = TRUE;
                sendPapersRemoveRequest();
            }
            else
            {
                // Either blunt (no papers needed) or papers just confirmed
                finishCraft();
            }
        }

        // ---- HUD refused item removal ----
        else if (channel == g_hudChannel && cmd == "TC_REMOVE_FAIL")
        {
            llSetTimerEvent(0.0);
            if (g_removingPapers)
            {
                // Papers failed — refund the flower already deducted
                llRegionSayTo(g_ownerKey, g_hudChannel,
                    "TC_ADD_ITEM|flower_raw|" + g_selectedStrain + "|" +
                    g_selectedQuality + "|" + (string)g_totalCost + "|" +
                    g_selectedPackager);
                llRegionSayTo(g_ownerKey, 0,
                    "Not enough Var Papers. Your flower has been returned.");
            }
            else
            {
                llRegionSayTo(g_ownerKey, 0,
                    "Not enough flower. Check your inventory and try again.");
            }
            g_busy = FALSE;
            resetTransaction();
        }

        // ---- Strain selection ----
        else if (channel == DCHAN_STRAIN && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; resetTransaction(); return; }

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
            llRegionSayTo(g_ownerKey, 0, "Couldn't match that strain. Please try again.");
            showFlowerMenu();
            return;
            @found_strain;
            showRollTypeMenu();
        }

        // ---- Roll type selection ----
        else if (channel == DCHAN_ROLLTYPE && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; resetTransaction(); return; }
            if (msg == "Back")   { showFlowerMenu(); return; }

            // Button labels are "Joint (1g)", "Blunt (2g)", "Spliff (1g)"
            // Extract the type name before the space
            string typePart = llToLower(llList2String(
                llParseString2List(msg, [" "], []), 0));

            if (typePart == "joint")
            {
                g_selectedRollType = "joint";
                g_rollCost         = 1;
            }
            else if (typePart == "blunt")
            {
                g_selectedRollType = "blunt";
                g_rollCost         = 2;
            }
            else if (typePart == "spliff")
            {
                g_selectedRollType = "spliff";
                g_rollCost         = 1;
            }
            else
            {
                llRegionSayTo(g_ownerKey, 0, "Unknown roll type. Please try again.");
                showRollTypeMenu();
                return;
            }
            showQuantityMenu();
        }

        // ---- Quantity selection ----
        else if (channel == DCHAN_QTY && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel") { g_busy = FALSE; resetTransaction(); return; }

            g_selectedCount = (integer)msg;
            if (g_selectedCount <= 0)
            {
                llRegionSayTo(g_ownerKey, 0, "Invalid quantity. Please try again.");
                showQuantityMenu();
                return;
            }

            g_totalCost = g_selectedCount * g_rollCost;
            if (g_totalCost > g_selectedQty)
            {
                llRegionSayTo(g_ownerKey, 0,
                    "Not enough flower for " + (string)g_selectedCount +
                    ". Max: " + (string)(g_selectedQty / g_rollCost) + ".");
                showQuantityMenu();
                return;
            }
            showConfirmMenu();
        }

        // ---- Confirmation ----
        else if (channel == DCHAN_CONFIRM && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (msg == "Cancel")
            {
                g_busy = FALSE;
                resetTransaction();
                return;
            }
            if (msg == "Roll It!")
                startRollingSequence();
        }
    }
}
