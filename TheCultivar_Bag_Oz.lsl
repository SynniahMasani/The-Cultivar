// ================================================================
// THE CULTIVAR  -  Bag Object Script  (TC_Bag_Oz   -  ~28g)
// Version: 1.0
// Lives inside: TC_Bag_Oz
//
// Description format:
//   strain:quality:packager:weightg:forSale:price
//   Example: "OG Kush:loud:FarmerJoe:28g:0:0"
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

integer DCHAN_OWNER   = -77001;
integer DCHAN_PRICE   = -77002;
integer DCHAN_BUYER   = -77003;

integer g_listenOwner;
integer g_listenPrice;
integer g_listenBuyer;
integer g_listenRegister;
integer g_bagConfigChan   = 0;  // start_param channel when rezzed by bagging table
integer g_listenBagConfig = 0;  // listens for TC_BAG_CONFIG from the table

string  g_strain    = "Unknown";
string  g_quality   = "reggie";
string  g_packager  = "Unknown";
integer g_weight    = 0;
integer g_price     = 0;
integer g_forSale   = FALSE;

key     g_ownerKey;
string  g_ownerName;
integer g_hudChannel = 0;
integer g_registered = FALSE;

key     g_pendingBuyer = NULL_KEY;

parseDescription()
{
    string desc = llGetObjectDesc();
    if (desc == "" || desc == "object") return;
    list parts = llParseString2List(desc, [":"], []);
    if (llGetListLength(parts) >= 4)
    {
        g_strain   = llList2String(parts, 0);
        g_quality  = llList2String(parts, 1);
        g_packager = llList2String(parts, 2);
        string wtStr = llList2String(parts, 3);
        g_weight   = (integer)llGetSubString(wtStr, 0, -2);
        if (llGetListLength(parts) >= 5)
            g_forSale = (integer)llList2String(parts, 4);
        if (llGetListLength(parts) >= 6)
            g_price   = (integer)llList2String(parts, 5);
    }
}

saveDescription()
{
    llSetObjectDesc(
        g_strain    + ":" + g_quality   + ":" + g_packager  + ":" +
        (string)g_weight + "g:" + (string)g_forSale + ":" + (string)g_price
    );
}

string qualLabel()
{
    if (g_quality == "reggie") return "Reggie";
    if (g_quality == "mids")   return "Mids";
    if (g_quality == "loud")   return "Loud";
    if (g_quality == "exotic") return "Exotic";
    return g_quality;
}

updateHoverText()
{
    string line1 = g_strain + " [" + qualLabel() + "]";
    string line2 = (string)g_weight + "g  *  Packed by " + g_packager;
    string line3;
    if (g_forSale)
        line3 = "FOR SALE  -  L$" + (string)g_price + "  -  Click to buy";
    else
        line3 = "Personal stash";

    vector textColor = <0.7, 0.7, 0.7>;
    if (g_quality == "mids")   textColor = <1.0, 0.9, 0.3>;
    if (g_quality == "loud")   textColor = <0.3, 0.9, 0.3>;
    if (g_quality == "exotic") textColor = <0.6, 0.3, 1.0>;
    llSetText(line1 + "\n" + line2 + "\n" + line3, textColor, 1.0);
}

integer deriveHUDChannel(key ownerID)
{
    string hexSub = llGetSubString((string)ownerID, 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}

pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN, "TC_PING|" + (string)llGetKey() + "|bag");
    llSetTimerEvent(8.0);
}

updateSaleState(integer pForSale, integer pPrice)
{
    if (pForSale && pPrice > 0)
        llSetForSale(1, llList2Integer([pPrice], 0)); // Mono scope bug workaround: wrap in list
    else
        llSetForSale(0, 0);
    llSetPayPrice(PAY_HIDE, [PAY_HIDE, PAY_HIDE, PAY_HIDE, PAY_HIDE]); // suppress Pay dialog
}

showOwnerMenu()
{
    if (g_listenOwner) llListenRemove(g_listenOwner);
    g_listenOwner = llListen(DCHAN_OWNER, "", g_ownerKey, "");
    list buttons;
    if (g_forSale)
        buttons = ["Remove From Sale", "Change Price", "Take Back", "Close"];
    else
        buttons = ["Put For Sale", "Load Into Jar", "Take Back", "Close"];
    string saleStr = "Personal";
    if (g_forSale) saleStr = "FOR SALE @ L$" + (string)g_price;
    llDialog(g_ownerKey,
        "=== YOUR OZ BAG ===\n" +
        g_strain + " [" + qualLabel() + "]\n" +
        (string)g_weight + "g  *  Packed by: " + g_packager + "\n" + saleStr,
        buttons, DCHAN_OWNER);
    llSetTimerEvent(30.0);
}

showBuyerMenu(key buyer)
{
    g_pendingBuyer = buyer;
    if (g_listenBuyer) llListenRemove(g_listenBuyer);
    g_listenBuyer = llListen(DCHAN_BUYER, "", buyer, "");
    llDialog(buyer,
        "=== FOR SALE ===\n" + g_strain + " [" + qualLabel() + "]\n" +
        (string)g_weight + "g\nPacked by: " + g_packager + "\n\nPrice: L$" + (string)g_price,
        ["Buy Now", "No Thanks"], DCHAN_BUYER);
    llSetTimerEvent(30.0);
}

// Oz (~28g) price range
showPriceMenu()
{
    if (g_listenOwner) llListenRemove(g_listenOwner);
    if (g_listenPrice) llListenRemove(g_listenPrice);
    g_listenPrice = llListen(DCHAN_PRICE, "", g_ownerKey, "");
    llDialog(g_ownerKey,
        "=== SET PRICE ===\nChoose a price for your " +
        g_strain + " (" + (string)g_weight + "g):",
        ["L$500", "L$600", "L$750", "L$900", "L$1000",
         "L$1250", "L$1500", "L$1750", "L$2000", "L$2500", "Back"],
        DCHAN_PRICE);
    llSetTimerEvent(30.0);
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        parseDescription();
        updateHoverText();
        updateSaleState(g_forSale, g_price);
        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");
    }

    on_rez(integer start_param)
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);

        if (start_param != 0)
        {
            // Freshly rezzed by bagging table  -  wait for strain config
            g_bagConfigChan = start_param;
            if (g_listenBagConfig) llListenRemove(g_listenBagConfig);
            g_listenBagConfig = llListen(g_bagConfigChan, "", NULL_KEY, "");
            llRegionSay(g_bagConfigChan, "TC_BAG_READY");
            llSetTimerEvent(10.0); // die if table never sends config
            return;
        }

        // Rezzed from inventory by player  -  read stored description
        parseDescription();
        updateHoverText();
        updateSaleState(g_forSale, g_price);
        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            key newOwner = llGetOwner();
            // SALE_ORIGINAL purchase: notify the seller's HUD before updating g_ownerKey
            if (g_forSale && g_price > 0 && g_ownerKey != NULL_KEY)
            {
                integer sellerHUDChan = deriveHUDChannel(g_ownerKey);
                llRegionSayTo(g_ownerKey, sellerHUDChan,
                    "TC_SALE_COMPLETE|" + (string)g_price + "|" + llKey2Name(newOwner));
                llRegionSayTo(g_ownerKey, 0,
                    "Sold your " + g_strain + " bag to " +
                    llKey2Name(newOwner) + " for L$" + (string)g_price + ".");
            }
            g_ownerKey  = newOwner;
            g_ownerName = llKey2Name(newOwner);
            g_forSale   = FALSE;
            g_price     = 0;
            saveDescription();
            updateHoverText();
            updateSaleState(FALSE, 0);
            g_registered = FALSE;
        }
    }

    timer()
    {
        llSetTimerEvent(0.0);
        // Config timeout  -  bagging table never sent TC_BAG_CONFIG
        if (g_bagConfigChan != 0)
        {
            llDie();
            return;
        }
        if (g_listenOwner)    { llListenRemove(g_listenOwner);    g_listenOwner    = 0; }
        if (g_listenPrice)    { llListenRemove(g_listenPrice);    g_listenPrice    = 0; }
        if (g_listenBuyer)    { llListenRemove(g_listenBuyer);    g_listenBuyer    = 0; }
        if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
        g_pendingBuyer = NULL_KEY;
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);
        if (toucher == g_ownerKey)
            showOwnerMenu();
        else if (g_forSale)
            showBuyerMenu(toucher);
        else
            llRegionSayTo(toucher, 0,
                "This bag belongs to " + g_ownerName + " and isn't for sale.");
    }

    money(key buyer, integer amount)
    {
        // Direct Pay received. Bags should be purchased via right-click -> Buy
        // (SALE_ORIGINAL). That flow handles L$ and object transfer automatically
        // without needing PERMISSION_DEBIT. If someone used Pay instead, attempt
        // a refund if we have PERMISSION_DEBIT (granted when "Put For Sale" chosen).
        if (llGetPermissions() & PERMISSION_DEBIT)
        {
            llGiveMoney(buyer, amount);
            llRegionSayTo(buyer, 0,
                "Refunded L$" + (string)amount +
                ". Please right-click this bag and choose 'Buy' to purchase it.");
        }
        else
        {
            llRegionSayTo(buyer, 0,
                "Please right-click this bag and choose 'Buy' to purchase it.");
            llOwnerSay(llKey2Name(buyer) + " paid L$" + (string)amount +
                " via Pay. Tell them to use 'Buy' instead.");
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- Configuration from bagging table (fired once after rez) ----
        if (g_bagConfigChan != 0 && channel == g_bagConfigChan && cmd == "TC_BAG_CONFIG")
        {
            // TC_BAG_CONFIG|strain|quality|packager|weight
            g_strain   = llList2String(parts, 1);
            g_quality  = llList2String(parts, 2);
            g_packager = llList2String(parts, 3);
            g_weight   = (integer)llList2String(parts, 4);
            g_forSale  = FALSE;
            g_price    = 0;
            g_bagConfigChan = 0;
            if (g_listenBagConfig) { llListenRemove(g_listenBagConfig); g_listenBagConfig = 0; }
            llSetTimerEvent(0.0);
            saveDescription();
            updateHoverText();
            updateSaleState(FALSE, 0);
        }
        else if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            llSetTimerEvent(0.0);
        }
        else if (channel == DCHAN_OWNER)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);
            if (g_listenOwner) { llListenRemove(g_listenOwner); g_listenOwner = 0; }

            if (msg == "Put For Sale")
            {
                // Request PERMISSION_DEBIT now so refunds work if buyer uses Pay instead of Buy
                llRequestPermissions(g_ownerKey, PERMISSION_DEBIT);
                showPriceMenu();
            }
            else if (msg == "Remove From Sale")
            {
                g_forSale = FALSE;
                g_price   = 0;
                saveDescription();
                updateHoverText();
                updateSaleState(FALSE, 0);
                llRegionSayTo(g_ownerKey, 0, "Bag removed from sale.");
            }
            else if (msg == "Change Price")
                showPriceMenu();
            else if (msg == "Load Into Jar")
                llRegionSayTo(g_ownerKey, 0,
                    "Touch your Cultivar weed jar to load this bag into it.");
            else if (msg == "Take Back")
            {
                string sizeName = "dime";
                if      (g_weight >= 28) sizeName = "oz";
                else if (g_weight >= 14) sizeName = "half";
                else if (g_weight >= 7)  sizeName = "quarter";
                else if (g_weight >= 4)  sizeName = "eighth";

                integer ownerHUDChan = deriveHUDChannel(g_ownerKey);
                llRegionSayTo(g_ownerKey, ownerHUDChan,
                    "TC_ADD_ITEM|bag_" + sizeName + "|" +
                    g_strain + "|" + g_quality + "|1|" + g_packager);
                llRegionSayTo(g_ownerKey, 0, "Bag returned to your inventory.");
                llDie();
            }
        }
        else if (channel == DCHAN_PRICE)
        {
            if (id != g_ownerKey) return;
            llSetTimerEvent(0.0);
            if (g_listenPrice) { llListenRemove(g_listenPrice); g_listenPrice = 0; }

            if (msg == "Back") { showOwnerMenu(); return; }
            g_price   = (integer)llGetSubString(msg, 2, -1);
            g_forSale = TRUE;
            saveDescription();
            updateHoverText();
            updateSaleState(g_forSale, g_price);
            llRegionSayTo(g_ownerKey, 0,
                g_strain + " is now for sale at L$" + (string)g_price + ".");
        }
        else if (channel == DCHAN_BUYER)
        {
            llSetTimerEvent(0.0);
            if (g_listenBuyer) { llListenRemove(g_listenBuyer); g_listenBuyer = 0; }
            if (msg == "Buy Now")
            {
                llRegionSayTo(id, 0,
                    "To purchase: right-click this bag and choose 'Buy' (L$" +
                    (string)g_price + ").");
            }
            g_pendingBuyer = NULL_KEY;
        }
    }

    run_time_permissions(integer perms) {}
}
