// ================================================================
// THE CULTIVAR — Plug Board Main Script
// Version: 1.0
// Handles: Stocked inventory reading, buyer browsing, pricing,
//          payment processing, bag delivery, owner management,
//          and HUD sale notifications.
//
// HOW STOCKING WORKS:
//   Owner drops bag objects into the board's inventory.
//   The board reads its own object inventory on CHANGED_INVENTORY.
//   Bag names follow the convention set by the bagging table:
//     TC_Bag_[Size]:[strain]:[quality]:[packager]:[weight]g
//   The board parses this name to build its listings automatically.
//   Owner then sets a price per slot via the owner menu.
//
// HOW BUYING WORKS:
//   Buyer touches board → sees browse menu → picks a listing
//   → board tells them the price → buyer pays the board
//   → board gives the bag, pays the owner, notifies owner HUD
//
// PRICING STORAGE:
//   Prices are stored in llLinksetData keyed by slot index.
//   Format: "price_0", "price_1", etc.
//   Survives sim restarts — owner doesn't have to reprice on relog.
//
// PRIM LINK STRUCTURE:
//   Link 1 (root)  : Board frame/body
//   Links 2–9      : Display slots (up to 8, one per listing)
//                    Each shows quality color glow + hover label
//   Link 10        : "OPEN/CLOSED" sign prim (optional)
//
// MAX LISTINGS: 8 (matches LSL dialog button limit)
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

// Dialog channels
integer DCHAN_OWNER_MAIN    = -101001;
integer DCHAN_OWNER_PRICE   = -101002;
integer DCHAN_OWNER_SLOT    = -101003;
integer DCHAN_BUYER_BROWSE  = -101004;
integer DCHAN_BUYER_CONFIRM = -101005;
integer DCHAN_CONSIGN_TERMS = -101006;
integer DCHAN_CONSIGN_CLEAR = -101007;

integer g_listenOwnerMain;
integer g_listenOwnerPrice;
integer g_listenOwnerSlot;
integer g_listenBuyerBrowse;
integer g_listenBuyerConfirm;
integer g_listenRegister;
integer g_listenHUD;
integer g_listenConsignTerms;
integer g_listenConsignClear;

key     g_ownerKey    = NULL_KEY;
string  g_ownerName   = "";
integer g_hudChannel  = 0;
integer g_registered  = FALSE;
integer g_boardOpen   = TRUE;

// Stocked listings parsed from inventory
// Stride 6: [invName, strain, quality, packager, weightG, price]
list    g_listings;
integer LIST_STRIDE = 6;
integer MAX_SLOTS   = 8;

// Pending buyer transaction state
key     g_pendingBuyer   = NULL_KEY;
integer g_pendingSlot    = -1;
integer g_pendingPrice   = 0;

// Owner's pending price-set slot
integer g_pricingSlot = -1;

// Consignment mode
integer g_consignEnabled      = FALSE;
integer g_consignFeePercent   = 10;    // % board owner takes on consignment sales
integer MAX_CONSIGN_SLOTS     = 3;     // max simultaneous consignment listings
key     g_pendingConsignKey   = NULL_KEY;
string  g_pendingConsignName  = "";
integer g_consignWindowActive = FALSE; // TRUE while waiting for consignor to drop
integer g_consignWindowStart  = 0;    // llGetUnixTime() when window opened

// ----------------------------------------------------------------
// Derive HUD channel from UUID
// ----------------------------------------------------------------
integer deriveHUDChannel(key id)
{
    string h = llGetSubString((string)id, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

// ----------------------------------------------------------------
// Ping HUD for registration
// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|plug_board");
    llSetTimerEvent(8.0);
}

// ----------------------------------------------------------------
// Parse a bag object name into its component fields
// Expected format: TC_Bag_[Size]:[strain]:[quality]:[packager]:[weight]g
// Returns list [strain, quality, packager, weightG] or [] on fail
// ----------------------------------------------------------------
list parseBagName(string invName)
{
    // Strip the TC_Bag_[Size]: prefix
    integer colonIdx = llSubStringIndex(invName, ":");
    if (colonIdx == -1) return [];

    string dataStr = llGetSubString(invName, colonIdx + 1, -1);
    list   parts   = llParseString2List(dataStr, [":"], []);
    if (llGetListLength(parts) < 4) return [];

    string strain   = llList2String(parts, 0);
    string quality  = llList2String(parts, 1);
    string packager = llList2String(parts, 2);
    string weightStr = llList2String(parts, 3);
    // Strip trailing 'g'
    integer weight  = (integer)llGetSubString(weightStr, 0, -2);

    return [strain, quality, packager, weight];
}

// ----------------------------------------------------------------
// Scan object inventory and rebuild listings list
// Only reads INVENTORY_OBJECT items with TC_Bag_ prefix
// ----------------------------------------------------------------
rebuildListings()
{
    g_listings = [];
    integer count = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i;
    integer slot = 0;

    for (i = 0; i < count && slot < MAX_SLOTS; i++)
    {
        string invName = llGetInventoryName(INVENTORY_OBJECT, i);
        if (llSubStringIndex(invName, "TC_Bag_") == 0)
        {
            list parsed = parseBagName(invName);
            if (llGetListLength(parsed) == 4)
            {
                // Load saved price for this slot
                integer price = (integer)llLinksetDataRead("price_" + (string)slot);

                g_listings += [
                    invName,                      // 0: inventory name
                    llList2String(parsed, 0),     // 1: strain
                    llList2String(parsed, 1),     // 2: quality
                    llList2String(parsed, 2),     // 3: packager
                    llList2Integer(parsed, 3),    // 4: weight grams
                    price                         // 5: price L$
                ];
                slot++;
            }
        }
    }
}

// ----------------------------------------------------------------
// Get field from a listing slot
// ----------------------------------------------------------------
string listingStr(integer slot, integer field)
{
    return llList2String(g_listings, slot * LIST_STRIDE + field);
}
integer listingInt(integer slot, integer field)
{
    return llList2Integer(g_listings, slot * LIST_STRIDE + field);
}

// ----------------------------------------------------------------
// Update the display script with current listing data
// ----------------------------------------------------------------
updateDisplay()
{
    integer count = llGetListLength(g_listings) / LIST_STRIDE;
    string  displayData = (string)count + "|" + (string)g_boardOpen;
    integer i;
    for (i = 0; i < count; i++)
    {
        displayData += "|" +
            listingStr(i, 1) + "~" +   // strain
            listingStr(i, 2) + "~" +   // quality
            listingStr(i, 3) + "~" +   // packager
            (string)listingInt(i, 4) + "~" + // weight
            (string)listingInt(i, 5);  // price
    }
    llMessageLinked(LINK_SET, 4000, "UPDATE_DISPLAY|" + displayData, NULL_KEY);
}

// ----------------------------------------------------------------
// Update main hover text
// ----------------------------------------------------------------
updateHoverText()
{
    integer count = llGetListLength(g_listings) / LIST_STRIDE;
    if (count == 0)
    {
        llSetText("THE CULTIVAR\nPlug Board\n[No stock]\nOwner: " + g_ownerName,
                  <0.6, 0.6, 0.6>, 1.0);
        return;
    }

    string text = "THE CULTIVAR — Plug Board\n";
    if (!g_boardOpen)
    {
        text += "[ CLOSED ]\n";
        llSetText(text + "Owner: " + g_ownerName, <0.8, 0.3, 0.3>, 1.0);
        return;
    }

    string strainPl = "";
    if (count != 1) strainPl = "s";
    text += (string)count + " strain" + strainPl + " available\n";
    text += "Touch to browse\nOwner: " + g_ownerName;
    llSetText(text, <0.4, 0.9, 0.4>, 1.0);
}

// ----------------------------------------------------------------
// Close all open dialog listens
// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenRegister)      { llListenRemove(g_listenRegister);      g_listenRegister     = 0; }
    if (g_listenOwnerMain)     { llListenRemove(g_listenOwnerMain);     g_listenOwnerMain    = 0; }
    if (g_listenOwnerPrice)    { llListenRemove(g_listenOwnerPrice);    g_listenOwnerPrice   = 0; }
    if (g_listenOwnerSlot)     { llListenRemove(g_listenOwnerSlot);     g_listenOwnerSlot    = 0; }
    if (g_listenBuyerBrowse)   { llListenRemove(g_listenBuyerBrowse);   g_listenBuyerBrowse  = 0; }
    if (g_listenBuyerConfirm)  { llListenRemove(g_listenBuyerConfirm);  g_listenBuyerConfirm = 0; }
    if (g_listenConsignTerms)  { llListenRemove(g_listenConsignTerms);  g_listenConsignTerms = 0; }
    if (g_listenConsignClear)  { llListenRemove(g_listenConsignClear);  g_listenConsignClear = 0; }
}

// ----------------------------------------------------------------
// OWNER MAIN MENU
// ----------------------------------------------------------------
showOwnerMenu()
{
    closeAllListens();
    integer count  = llGetListLength(g_listings) / LIST_STRIDE;
    string  boardStateStr = "CLOSED";
    if (g_boardOpen) boardStateStr = "OPEN";
    string  status = (string)count + " listings  •  " + boardStateStr;
    string  toggleBtn = "Open Board";
    if (g_boardOpen) toggleBtn = "Close Board";
    string  consignBtn = "Consign: OFF";
    if (g_consignEnabled) consignBtn = "Consign: ON";

    g_listenOwnerMain = llListen(DCHAN_OWNER_MAIN, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== YOUR PLUG BOARD ===\n" + status,
        ["Set Prices", "Restock", toggleBtn,
         "Clear Slot", consignBtn, "Clr Consign",
         "Board Stats", "Close"],
        DCHAN_OWNER_MAIN);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// SET PRICES MENU — pick a slot then enter price
// ----------------------------------------------------------------
showSetPricesMenu()
{
    closeAllListens();
    integer count = llGetListLength(g_listings) / LIST_STRIDE;
    if (count == 0)
    {
        llRegionSayTo(g_ownerKey, 0, "No bags stocked yet. Drop bags into the board first.");
        return;
    }

    list   buttons;
    string menuText = "=== SET PRICES ===\nSelect a listing to price:\n\n";
    integer i;
    for (i = 0; i < count; i++)
    {
        string  strain  = listingStr(i, 1);
        string  quality = listingStr(i, 2);
        integer price   = listingInt(i, 5);
        integer weight  = listingInt(i, 4);
        string  priceStr = "unpriced";
        if (price > 0) priceStr = "L$" + (string)price;

        buttons += [llGetSubString(strain, 0, 8) + " #" + (string)(i+1)];
        menuText += "#" + (string)(i+1) + " " + quality + " " + strain +
                    " " + (string)weight + "g — " + priceStr + "\n";
    }
    buttons += ["Back"];

    g_listenOwnerSlot = llListen(DCHAN_OWNER_SLOT, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_OWNER_SLOT);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// PRICE PICKER — preset L$ values
// ----------------------------------------------------------------
showPricePicker(integer slot)
{
    g_pricingSlot = slot;
    closeAllListens();
    string strain  = listingStr(slot, 1);
    string quality = listingStr(slot, 2);
    integer weight = listingInt(slot, 4);
    integer cur    = listingInt(slot, 5);

    string curStr = "Unpriced";
    if (cur > 0) curStr = "Current: L$" + (string)cur;
    g_listenOwnerPrice = llListen(DCHAN_OWNER_PRICE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== PRICE: " + quality + " " + strain + " " + (string)weight + "g ===\n" +
        curStr + "\nSet new price:",
        ["L$50",  "L$75",  "L$100", "L$150",
         "L$200", "L$300", "L$400", "L$500",
         "L$750", "L$1000","L$1500","Back"],
        DCHAN_OWNER_PRICE);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// CLEAR SLOT MENU — remove a listing from the board
// ----------------------------------------------------------------
showClearSlotMenu()
{
    closeAllListens();
    integer count = llGetListLength(g_listings) / LIST_STRIDE;
    if (count == 0)
    {
        llRegionSayTo(g_ownerKey, 0, "Nothing stocked to remove.");
        return;
    }

    list   buttons;
    string menuText = "=== CLEAR SLOT ===\nReturn a bag to your inventory:\n\n";
    integer i;
    for (i = 0; i < count; i++)
    {
        string strain  = listingStr(i, 1);
        string quality = listingStr(i, 2);
        buttons += [llGetSubString(strain, 0, 8) + " #" + (string)(i+1)];
        menuText += "#" + (string)(i+1) + " " + quality + " " + strain + "\n";
    }
    buttons += ["Back"];

    // Reuse slot listen channel
    g_listenOwnerSlot = llListen(DCHAN_OWNER_SLOT, "", g_ownerKey, "");
    llLinksetDataWrite("board_clear_mode", "1");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_OWNER_SLOT);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// BUYER BROWSE MENU — show available listings with prices
// ----------------------------------------------------------------
showBuyerMenu(key buyer)
{
    closeAllListens();
    integer count = llGetListLength(g_listings) / LIST_STRIDE;

    list   buttons;
    string menuText = "=== THE CULTIVAR ===\n" + g_ownerName + "'s stash\n\n";

    list qualLabels = ["[R]","[M]","[L]","[E]"];
    list qualNames  = ["reggie","mids","loud","exotic"];

    integer i;
    for (i = 0; i < count; i++)
    {
        string  strain   = listingStr(i, 1);
        string  quality  = listingStr(i, 2);
        string  packager = listingStr(i, 3);
        integer weight   = listingInt(i, 4);
        integer price    = listingInt(i, 5);

        if (price == 0) jump skip_unpriced; // skip unpriced listings

        integer qIdx   = llListFindList(qualNames, [quality]);
        string  qLabel = llList2String(qualLabels, qIdx);

        string btnLabel = llGetSubString(strain, 0, 8) +
                          " L$" + (string)price;
        buttons += [btnLabel];
        menuText += qLabel + " " + strain + "  " + (string)weight + "g" +
                    "  —  L$" + (string)price + "\n";
        @skip_unpriced;
    }

    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(buyer, 0,
            "Nothing priced for sale right now. Check back soon.");
        return;
    }

    buttons += ["Close"];
    g_listenBuyerBrowse = llListen(DCHAN_BUYER_BROWSE, "", buyer, "");
    llDialog(buyer, menuText, buttons, DCHAN_BUYER_BROWSE);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// BUYER CONFIRM MENU — shown after picking a listing
// ----------------------------------------------------------------
showBuyerConfirm(key buyer, integer slot)
{
    closeAllListens();
    g_pendingBuyer = buyer;
    g_pendingSlot  = slot;
    g_pendingPrice = listingInt(slot, 5);

    string strain   = listingStr(slot, 1);
    string quality  = listingStr(slot, 2);
    string packager = listingStr(slot, 3);
    integer weight  = listingInt(slot, 4);

    g_listenBuyerConfirm = llListen(DCHAN_BUYER_CONFIRM, "", buyer, "");
    llDialog(buyer,
        "=== CONFIRM PURCHASE ===\n" +
        quality + " " + strain + "\n" +
        (string)weight + "g  •  Packed by " + packager + "\n\n" +
        "Price: L$" + (string)g_pendingPrice + "\n\n" +
        "Pay L$" + (string)g_pendingPrice +
        " to the board to complete purchase.",
        ["I'll Pay", "Cancel"], DCHAN_BUYER_CONFIRM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Complete a sale — give bag, pay seller, notify HUD, update board
// ----------------------------------------------------------------
completeSale(key buyer, integer slot)
{
    string invName  = listingStr(slot, 0);
    string strain   = listingStr(slot, 1);
    string quality  = listingStr(slot, 2);
    integer weight  = listingInt(slot, 4);
    integer price   = listingInt(slot, 5);

    // Verify bag is still in inventory (could have been restocked)
    if (llGetInventoryType(invName) != INVENTORY_OBJECT)
    {
        llGiveMoney(buyer, price); // refund
        llRegionSayTo(buyer, 0,
            "Sorry — that bag was just sold. Refunding your L$" +
            (string)price + ".");
        rebuildListings();
        updateDisplay();
        updateHoverText();
        return;
    }

    // Give bag to buyer
    llGiveInventory(buyer, invName);

    // Pay seller — split if consignment
    if (isConsignment(invName))
    {
        key    cKey    = consignorKeyOf(invName);
        string cName   = consignorNameOf(invName);
        integer fee    = price * g_consignFeePercent / 100;
        integer payout = price - fee;

        llGiveMoney(g_ownerKey, fee);
        llGiveMoney(cKey, payout);

        llRegionSayTo(buyer, 0,
            "✓ Purchased: " + quality + " " + strain + " " +
            (string)weight + "g  —  Check your inventory!");
        llRegionSayTo(g_ownerKey, 0,
            "✓ Consignment sale: " + quality + " " + strain + " to " +
            llKey2Name(buyer) + " — fee L$" + (string)fee + " received.");
        llInstantMessage(cKey,
            "✓ Your " + quality + " " + strain + " sold for L$" + (string)price +
            "! You receive L$" + (string)payout +
            " (" + (string)g_consignFeePercent + "% board fee).");

        llLinksetDataDelete(csKey(invName));
    }
    else
    {
        llGiveMoney(g_ownerKey, price);

        llRegionSayTo(buyer, 0,
            "✓ Purchased: " + quality + " " + strain + " " +
            (string)weight + "g  —  Check your inventory!");
        llRegionSayTo(g_ownerKey, 0,
            "✓ Sold " + quality + " " + strain + " " + (string)weight +
            "g to " + llKey2Name(buyer) + " for L$" + (string)price + "!");
    }

    // Notify owner HUD
    llRegionSayTo(g_ownerKey, g_hudChannel,
        "TC_SALE_COMPLETE|" + (string)price + "|" + llKey2Name(buyer));

    // Clear this slot's price data
    llLinksetDataDelete("price_" + (string)slot);

    // Rebuild — bag is now gone from inventory
    rebuildListings();
    updateDisplay();
    updateHoverText();

    // Re-index remaining slot prices correctly
    // (handled by rebuildListings reading saved price_N keys)
}

// ----------------------------------------------------------------
// Consignment helper functions
// ----------------------------------------------------------------
string csKey(string invName)
{
    // Linkset data key for consignment attribution
    return "cs_" + llGetSubString(invName, 7, 36);
}

integer isConsignment(string invName)
{
    return llLinksetDataRead(csKey(invName)) != "";
}

key consignorKeyOf(string invName)
{
    string data = llLinksetDataRead(csKey(invName));
    if (data == "") return NULL_KEY;
    list parts = llParseString2List(data, ["^"], []);
    return (key)llList2String(parts, 0);
}

string consignorNameOf(string invName)
{
    string data = llLinksetDataRead(csKey(invName));
    if (data == "") return "";
    list parts = llParseString2List(data, ["^"], []);
    return llList2String(parts, 1);
}

integer countConsignedBags()
{
    integer count = 0;
    integer total = llGetListLength(g_listings) / LIST_STRIDE;
    integer i;
    for (i = 0; i < total; i++)
    {
        if (isConsignment(listingStr(i, 0))) count++;
    }
    return count;
}

// ----------------------------------------------------------------
// NON-OWNER MENU — Browse or Consign Here
// ----------------------------------------------------------------
showNonOwnerMenu(key toucher)
{
    closeAllListens();
    g_listenConsignTerms = llListen(DCHAN_CONSIGN_TERMS, "", toucher, "");
    llDialog(toucher,
        "=== " + g_ownerName + "'s Plug Board ===\n\n" +
        "Browse the stash, or consign your own bags here.\n" +
        "Consignment fee: " + (string)g_consignFeePercent + "%",
        ["Browse", "Consign Here", "Close"],
        DCHAN_CONSIGN_TERMS);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// CONSIGN TERMS DIALOG — shown to prospective consignors
// ----------------------------------------------------------------
showConsignTerms(key consignor)
{
    closeAllListens();
    integer slotsUsed = countConsignedBags();
    if (slotsUsed >= MAX_CONSIGN_SLOTS)
    {
        llRegionSayTo(consignor, 0,
            "Sorry — all " + (string)MAX_CONSIGN_SLOTS +
            " consignment slots are full right now.");
        return;
    }
    g_listenConsignTerms = llListen(DCHAN_CONSIGN_TERMS, "", consignor, "");
    llDialog(consignor,
        "=== CONSIGN HERE ===\n\n" +
        "Drop a TC_Bag_ into this board.\n" +
        "When it sells, " + (string)g_consignFeePercent +
        "% goes to the board owner.\n" +
        "You keep " + (string)(100 - g_consignFeePercent) + "%.\n\n" +
        "Agree and drop your bag within 5 minutes.",
        ["Agree & Drop", "Cancel"],
        DCHAN_CONSIGN_TERMS);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// CLEAR CONSIGN MENU — owner removes consignment attribution
// ----------------------------------------------------------------
showClearConsignMenu()
{
    closeAllListens();
    integer count = llGetListLength(g_listings) / LIST_STRIDE;
    list   buttons;
    string menuText = "=== CLEAR CONSIGNMENT ===\nRemove consignment tag from a slot:\n\n";
    integer found = FALSE;
    integer i;
    for (i = 0; i < count; i++)
    {
        string invName = listingStr(i, 0);
        if (isConsignment(invName))
        {
            string cName = consignorNameOf(invName);
            buttons += [llGetSubString(listingStr(i, 1), 0, 6) + " #" + (string)(i+1)];
            menuText += "#" + (string)(i+1) + " " + listingStr(i, 1) +
                        " — by " + cName + "\n";
            found = TRUE;
        }
    }
    if (!found)
    {
        llRegionSayTo(g_ownerKey, 0, "No consignment slots to clear.");
        showOwnerMenu();
        return;
    }
    buttons += ["Back"];
    g_listenConsignClear = llListen(DCHAN_CONSIGN_CLEAR, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_CONSIGN_CLEAR);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Stats card for owner
// ----------------------------------------------------------------
showStats()
{
    integer totalSold     = (integer)llLinksetDataRead("board_total_sold");
    integer totalEarned   = (integer)llLinksetDataRead("board_total_earned");
    integer totalVisitors = (integer)llLinksetDataRead("board_visitors");
    integer listed        = llGetListLength(g_listings) / LIST_STRIDE;

    llRegionSayTo(g_ownerKey, 0,
        "=== PLUG BOARD STATS ===\n" +
        "Currently Listed: " + (string)listed + "\n" +
        "Total Sold: "    + (string)totalSold   + " bags\n" +
        "Total Earned: L$" + (string)totalEarned + "\n" +
        "Total Visitors: " + (string)totalVisitors);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);

        // Listen for HUD registration
        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");

        // g_listenHUD is not opened here — the board sends TC_SALE_COMPLETE
        // to the HUD but never needs to receive anything on g_hudChannel

        rebuildListings();
        updateHoverText();
        updateDisplay();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            // Board transferred — wipe all data for new owner, then reset
            llLinksetDataReset();
            llResetScript();
        }

        if (change & CHANGED_INVENTORY)
        {
            // If a consignment window is active, attribute any new bags
            if (g_consignWindowActive && g_pendingConsignKey != NULL_KEY)
            {
                integer now = llGetUnixTime();
                if (now - g_consignWindowStart < 300)
                {
                    // Find new TC_Bag_ items not already in current listings
                    integer invCount = llGetInventoryNumber(INVENTORY_OBJECT);
                    integer ii;
                    for (ii = 0; ii < invCount; ii++)
                    {
                        string iName = llGetInventoryName(INVENTORY_OBJECT, ii);
                        if (llSubStringIndex(iName, "TC_Bag_") == 0 &&
                            llLinksetDataRead(csKey(iName)) == "" &&
                            llListFindList(g_listings, [iName]) == -1)
                        {
                            llLinksetDataWrite(csKey(iName),
                                (string)g_pendingConsignKey + "^" + g_pendingConsignName);
                            llRegionSayTo(g_pendingConsignKey, 0,
                                "✓ Bag received for consignment! The owner will set a price.");
                            g_consignWindowActive = FALSE;
                            g_pendingConsignKey   = NULL_KEY;
                            g_pendingConsignName  = "";
                            ii = invCount; // break
                        }
                    }
                }
                else
                {
                    // Window expired without a bag being dropped
                    g_consignWindowActive = FALSE;
                    g_pendingConsignKey   = NULL_KEY;
                    g_pendingConsignName  = "";
                }
            }

            // Rebuild listings from inventory
            rebuildListings();
            updateDisplay();
            updateHoverText();
            if (g_ownerKey != NULL_KEY)
                llRegionSayTo(g_ownerKey, 0,
                    "Board updated — " +
                    (string)(llGetListLength(g_listings) / LIST_STRIDE) +
                    " listings. Don't forget to set prices!");
        }
    }

    timer()
    {
        closeAllListens();
        llSetTimerEvent(0.0);
        g_pendingBuyer   = NULL_KEY;
        g_pendingSlot    = -1;
        g_pendingPrice   = 0;
        g_pricingSlot    = -1;
        llLinksetDataDelete("board_clear_mode");

        if (!g_registered)
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't reach your HUD. Make sure your Cultivar HUD is worn.");
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);

        if (toucher == g_ownerKey)
        {
            pingHUD();
            llLinksetDataWrite("board_intent", "owner_menu");
        }
        else
        {
            if (!g_boardOpen)
            {
                llRegionSayTo(toucher, 0,
                    g_ownerName + "'s board is closed right now.");
                return;
            }
            if (llGetListLength(g_listings) == 0)
            {
                llRegionSayTo(toucher, 0,
                    "Nothing in stock right now. Check back later.");
                return;
            }

            // Track visitor count
            integer visitors = (integer)llLinksetDataRead("board_visitors");
            llLinksetDataWrite("board_visitors", (string)(visitors + 1));

            if (g_consignEnabled)
                showNonOwnerMenu(toucher);
            else
                showBuyerMenu(toucher);
        }
    }

    // Buyer pays the board directly
    money(key buyer, integer amount)
    {
        if (g_pendingBuyer == NULL_KEY || g_pendingBuyer != buyer ||
            g_pendingSlot == -1)
        {
            // No pending transaction — refund
            llGiveMoney(buyer, amount);
            llRegionSayTo(buyer, 0,
                "No active purchase. Browse the board first, then pay.");
            return;
        }

        if (amount < g_pendingPrice)
        {
            llGiveMoney(buyer, amount);
            llRegionSayTo(buyer, 0,
                "Not enough. Price is L$" + (string)g_pendingPrice +
                ". Refunding.");
            return;
        }

        // Overpaid — refund difference
        if (amount > g_pendingPrice)
            llGiveMoney(buyer, amount - g_pendingPrice);

        // Update cumulative stats
        integer totalSold   = (integer)llLinksetDataRead("board_total_sold");
        integer totalEarned = (integer)llLinksetDataRead("board_total_earned");
        llLinksetDataWrite("board_total_sold",   (string)(totalSold + 1));
        llLinksetDataWrite("board_total_earned", (string)(totalEarned + g_pendingPrice));

        integer slot = g_pendingSlot;
        g_pendingBuyer = NULL_KEY;
        g_pendingSlot  = -1;
        g_pendingPrice = 0;

        completeSale(buyer, slot);
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // HUD registration
        if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;

            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            llSetTimerEvent(0.0);

            string intent = llLinksetDataRead("board_intent");
            llLinksetDataDelete("board_intent");
            if (intent == "owner_menu") showOwnerMenu();
        }

        // OWNER MAIN MENU
        else if (channel == DCHAN_OWNER_MAIN && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenOwnerMain) { llListenRemove(g_listenOwnerMain); g_listenOwnerMain = 0; }

            if      (msg == "Set Prices")  showSetPricesMenu();
            else if (msg == "Restock")
                llRegionSayTo(g_ownerKey, 0,
                    "Drop bag objects from your inventory onto the board to restock.");
            else if (msg == "Close Board") { g_boardOpen = FALSE; updateHoverText(); updateDisplay(); }
            else if (msg == "Open Board")  { g_boardOpen = TRUE;  updateHoverText(); updateDisplay(); }
            else if (msg == "Clear Slot")  showClearSlotMenu();
            else if (msg == "Consign: OFF" || msg == "Consign: ON")
            {
                g_consignEnabled = !g_consignEnabled;
                string consignState = "DISABLED";
                if (g_consignEnabled) consignState = "ENABLED";
                llRegionSayTo(g_ownerKey, 0,
                    "Consignment mode: " + consignState + ".");
            }
            else if (msg == "Clr Consign") showClearConsignMenu();
            else if (msg == "Board Stats") showStats();
        }

        // OWNER SLOT SELECTION (price or clear)
        else if (channel == DCHAN_OWNER_SLOT && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenOwnerSlot) { llListenRemove(g_listenOwnerSlot); g_listenOwnerSlot = 0; }

            if (msg == "Back") { showOwnerMenu(); return; }

            string clearMode = llLinksetDataRead("board_clear_mode");
            llLinksetDataDelete("board_clear_mode");

            // Parse slot number from button label "StrainName #N"
            integer hashIdx = llSubStringIndex(msg, "#");
            if (hashIdx == -1) return;
            integer slot = (integer)llGetSubString(msg, hashIdx + 1, -1) - 1;

            if (clearMode == "1")
            {
                // Return bag to owner inventory
                string invName = listingStr(slot, 0);
                if (llGetInventoryType(invName) == INVENTORY_OBJECT)
                {
                    llGiveInventory(g_ownerKey, invName);
                    llLinksetDataDelete("price_" + (string)slot);
                    llRegionSayTo(g_ownerKey, 0,
                        "Returned " + listingStr(slot, 1) + " to your inventory.");
                    rebuildListings();
                    updateDisplay();
                    updateHoverText();
                }
            }
            else
            {
                showPricePicker(slot);
            }
        }

        // OWNER PRICE PICKER
        else if (channel == DCHAN_OWNER_PRICE && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenOwnerPrice) { llListenRemove(g_listenOwnerPrice); g_listenOwnerPrice = 0; }

            if (msg == "Back") { showSetPricesMenu(); return; }

            integer newPrice = (integer)llGetSubString(msg, 2, -1); // strip "L$"
            if (g_pricingSlot >= 0 && newPrice > 0)
            {
                // Save price to persistent storage
                llLinksetDataWrite("price_" + (string)g_pricingSlot, (string)newPrice);
                // Update in-memory listing
                g_listings = llListReplaceList(g_listings,
                    [newPrice],
                    g_pricingSlot * LIST_STRIDE + 5,
                    g_pricingSlot * LIST_STRIDE + 5);

                llRegionSayTo(g_ownerKey, 0,
                    "✓ " + listingStr(g_pricingSlot, 1) + " priced at L$" +
                    (string)newPrice);
                updateDisplay();
                updateHoverText();
            }
            g_pricingSlot = -1;
        }

        // BUYER BROWSE SELECTION
        else if (channel == DCHAN_BUYER_BROWSE)
        {
            llSetTimerEvent(0.0);
            if (g_listenBuyerBrowse) { llListenRemove(g_listenBuyerBrowse); g_listenBuyerBrowse = 0; }

            if (msg == "Close") return;

            // Match button label to listing slot
            // Button format: "StrainShort L$NNN"
            integer count = llGetListLength(g_listings) / LIST_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string strain = listingStr(i, 1);
                integer price = listingInt(i, 5);
                if (price == 0) jump skip_buyer;
                string btnLabel = llGetSubString(strain, 0, 8) +
                                  " L$" + (string)price;
                if (btnLabel == msg)
                {
                    showBuyerConfirm(id, i);
                    return;
                }
                @skip_buyer;
            }
        }

        // BUYER CONFIRM
        else if (channel == DCHAN_BUYER_CONFIRM)
        {
            llSetTimerEvent(0.0);
            if (g_listenBuyerConfirm) { llListenRemove(g_listenBuyerConfirm); g_listenBuyerConfirm = 0; }

            if (msg == "Cancel")
            {
                g_pendingBuyer = NULL_KEY;
                g_pendingSlot  = -1;
                return;
            }
            if (msg == "I'll Pay")
            {
                llRegionSayTo(id, 0,
                    "Right-click the board and choose Pay, " +
                    "then enter L$" + (string)g_pendingPrice + ".");
            }
        }

        // NON-OWNER MENU / CONSIGN TERMS
        else if (channel == DCHAN_CONSIGN_TERMS)
        {
            llSetTimerEvent(0.0);
            if (g_listenConsignTerms) { llListenRemove(g_listenConsignTerms); g_listenConsignTerms = 0; }

            if (msg == "Browse")
                showBuyerMenu(id);
            else if (msg == "Consign Here")
                showConsignTerms(id);
            else if (msg == "Agree & Drop")
            {
                g_pendingConsignKey   = id;
                g_pendingConsignName  = name;
                g_consignWindowActive = TRUE;
                g_consignWindowStart  = llGetUnixTime();
                llRegionSayTo(id, 0,
                    "✓ Consignment agreed! Drop your TC_Bag_ into the board within 5 minutes.");
            }
            // "Cancel" / "Close" — no action
        }

        // CONSIGN CLEAR — owner removes consignment tag from a slot
        else if (channel == DCHAN_CONSIGN_CLEAR && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenConsignClear) { llListenRemove(g_listenConsignClear); g_listenConsignClear = 0; }

            if (msg == "Back") { showOwnerMenu(); return; }

            integer hashIdx = llSubStringIndex(msg, "#");
            if (hashIdx == -1) return;
            integer slot = (integer)llGetSubString(msg, hashIdx + 1, -1) - 1;
            string  invName = listingStr(slot, 0);
            if (isConsignment(invName))
            {
                string cName = consignorNameOf(invName);
                llLinksetDataDelete(csKey(invName));
                llRegionSayTo(g_ownerKey, 0,
                    "✓ Removed consignment tag from slot #" + (string)(slot+1) +
                    " (was consigned by " + cName + ").");
            }
            showOwnerMenu();
        }
    }
}
