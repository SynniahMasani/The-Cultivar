// ================================================================
// THE CULTIVAR  -  HUD Inventory Manager Script
// Version: 1.0
// Handles: All player inventory  -  seeds, flower, rolled items,
//          edibles, bags, consumables
// Persistence: llLinksetDataWrite (survives sim restarts)
// ================================================================
//
// INVENTORY FORMAT (strided list, stride = 5, serialized to string)
// Each item slot: itemType ~ strainName ~ quality ~ quantity ~ packager
//
// itemType values:
//   seed_raw, flower_raw, joint, blunt, spliff, edible_brownie,
//   edible_gummy, edible_drink, concentrate, bag_dime, bag_eighth,
//   bag_quarter, bag_oz, fertilizer_basic, fertilizer_premium,
//   fertilizer_exotic, water_can
//
// quality values: reggie, mids, loud, exotic
//
// Example serialized: "flower_raw~OG Kush~loud~14~FarmerJoe"
// Multiple items separated by "^"
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_IDENTITY  = 400;
integer CHAN_ANIMATION = 500;

// Stride size for inventory list
integer STRIDE = 5;

// Inventory stored as an LSL list in memory, persisted as string
list g_inventory; // [itemType, strainName, quality, quantity, packager, ...]

// Max stack size per slot to prevent abuse
integer MAX_STACK = 100;

// ----------------------------------------------------------------
// Serialize list to storable string
// ----------------------------------------------------------------
string serializeInventory()
{
    string result = "";
    integer len = llGetListLength(g_inventory);
    integer i;
    for (i = 0; i < len; i += STRIDE)
    {
        string slot = llList2String(g_inventory, i)   + "~" +
                      llList2String(g_inventory, i+1) + "~" +
                      llList2String(g_inventory, i+2) + "~" +
                      llList2String(g_inventory, i+3) + "~" +
                      llList2String(g_inventory, i+4);
        if (result == "") result = slot;
        else result += "^" + slot;
    }
    return result;
}

// ----------------------------------------------------------------
// Deserialize string back to list
// ----------------------------------------------------------------
list deserializeInventory(string data)
{
    list result;
    if (data == "") return result;

    list slots = llParseString2List(data, ["^"], []);
    integer s;
    for (s = 0; s < llGetListLength(slots); s++)
    {
        list fields = llParseString2List(llList2String(slots, s), ["~"], []);
        if (llGetListLength(fields) == STRIDE)
            result += fields;
    }
    return result;
}

// ----------------------------------------------------------------
// Save inventory to persistent storage
// ----------------------------------------------------------------
saveInventory()
{
    llLinksetDataWrite("inv_data", serializeInventory());
}

// ----------------------------------------------------------------
// Load inventory from persistent storage
// ----------------------------------------------------------------
loadInventory()
{
    string data = llLinksetDataRead("inv_data");
    g_inventory = deserializeInventory(data);
}

// ----------------------------------------------------------------
// Find the index of an existing stack matching type+strain+quality+packager
// Returns -1 if not found
// ----------------------------------------------------------------
integer findSlot(string itemType, string strainName, string quality, string packager)
{
    integer len = llGetListLength(g_inventory);
    integer i;
    for (i = 0; i < len; i += STRIDE)
    {
        if (llList2String(g_inventory, i)   == itemType  &&
            llList2String(g_inventory, i+1) == strainName &&
            llList2String(g_inventory, i+2) == quality   &&
            llList2String(g_inventory, i+4) == packager)
        {
            return i;
        }
    }
    return -1;
}

// ----------------------------------------------------------------
// Add items to inventory, stacking where possible
// ----------------------------------------------------------------
addItem(string itemType, string strainName, string quality,
        integer qty, string packager)
{
    integer idx = findSlot(itemType, strainName, quality, packager);

    if (idx != -1)
    {
        // Stack onto existing slot
        integer current = (integer)llList2String(g_inventory, idx + 3);
        integer newQty  = current + qty;
        if (newQty > MAX_STACK) newQty = MAX_STACK;
        g_inventory = llListReplaceList(g_inventory, [(string)newQty], idx+3, idx+3);
    }
    else
    {
        // New slot
        g_inventory += [itemType, strainName, quality, (string)qty, packager];
    }

    saveInventory();
    broadcastInventorySummary();
    llOwnerSay("Added to inventory: " + (string)qty + "x " + quality + " " +
               strainName + " [" + itemType + "]");
}

// ----------------------------------------------------------------
// Remove items from inventory
// Returns TRUE if successful, FALSE if insufficient quantity
// ----------------------------------------------------------------
integer removeItem(string itemType, string strainName, string quality,
                   integer qty, string packager)
{
    integer idx = findSlot(itemType, strainName, quality, packager);
    if (idx == -1)
    {
        llOwnerSay("Item not found in inventory.");
        return FALSE;
    }

    integer current = (integer)llList2String(g_inventory, idx + 3);
    if (current < qty)
    {
        llOwnerSay("Not enough " + strainName + " to do that.");
        return FALSE;
    }

    integer newQty = current - qty;
    if (newQty <= 0)
    {
        // Remove the slot entirely
        g_inventory = llDeleteSubList(g_inventory, idx, idx + STRIDE - 1);
    }
    else
    {
        g_inventory = llListReplaceList(g_inventory, [(string)newQty], idx+3, idx+3);
    }

    saveInventory();
    broadcastInventorySummary();
    return TRUE;
}

// ----------------------------------------------------------------
// Send a summary string to the UI script for display
// ----------------------------------------------------------------
broadcastInventorySummary()
{
    string summary = "";
    integer len = llGetListLength(g_inventory);
    integer i;
    for (i = 0; i < len; i += STRIDE)
    {
        string line = llList2String(g_inventory, i+3) + "x " +
                      llList2String(g_inventory, i+2) + " " +
                      llList2String(g_inventory, i+1) + " [" +
                      llList2String(g_inventory, i)   + "]";
        if (summary == "") summary = line;
        else summary += "\n" + line;
    }

    if (summary == "") summary = "Your inventory is empty.";
    llMessageLinked(LINK_SET, CHAN_UI, "UPDATE_INVENTORY_DISPLAY|" + summary, NULL_KEY);
}

// ----------------------------------------------------------------
// Return quantity of a specific item (for checks by other scripts)
// ----------------------------------------------------------------
integer getQuantity(string itemType, string strainName, string quality)
{
    integer len = llGetListLength(g_inventory);
    integer i;
    integer total = 0;
    for (i = 0; i < len; i += STRIDE)
    {
        if (llList2String(g_inventory, i)   == itemType &&
            llList2String(g_inventory, i+1) == strainName &&
            llList2String(g_inventory, i+2) == quality)
        {
            total += (integer)llList2String(g_inventory, i+3);
        }
    }
    return total;
}

// ================================================================
default
{
    state_entry()
    {
        loadInventory();
        broadcastInventorySummary();
    }

    on_rez(integer start_param)
    {
        loadInventory();
        broadcastInventorySummary();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llLinksetDataWrite("inv_data", "");
            llResetScript();
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != CHAN_INVENTORY) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Plant sends harvest result to HUD
        if (cmd == "ADD_ITEM")
        {
            // ADD_ITEM|itemType|strainName|quality|qty|packager
            addItem(
                llList2String(parts, 1),
                llList2String(parts, 2),
                llList2String(parts, 3),
                (integer)llList2String(parts, 4),
                llList2String(parts, 5)
            );
        }

        // Crafting table, session, or pass system consuming inventory
        else if (cmd == "REMOVE_ITEM")
        {
            // REMOVE_ITEM|itemType|strainName|quality|qty|packager
            integer success = removeItem(
                llList2String(parts, 1),
                llList2String(parts, 2),
                llList2String(parts, 3),
                (integer)llList2String(parts, 4),
                llList2String(parts, 5)
            );
            // Report success/fail back via comms channel.
            // Pass 'id' through so HUD_Comms can notify the requesting world object.
            if (success)
                llMessageLinked(LINK_SET, CHAN_COMMS, "REMOVE_SUCCESS|" + llList2String(parts,1) + "|" + llList2String(parts,2), id);
            else
                llMessageLinked(LINK_SET, CHAN_COMMS, "REMOVE_FAIL|" + llList2String(parts,1) + "|" + llList2String(parts,2), id);
        }

        // UI opened the inventory panel, needs fresh data
        else if (cmd == "REQUEST_INVENTORY")
        {
            broadcastInventorySummary();
        }

        // Another script needs to know if player has enough of something
        else if (cmd == "CHECK_QTY")
        {
            // CHECK_QTY|itemType|strainName|quality|requiredQty
            string  iType    = llList2String(parts, 1);
            string  iStrain  = llList2String(parts, 2);
            string  iQuality = llList2String(parts, 3);
            integer required = (integer)llList2String(parts, 4);
            integer have     = getQuantity(iType, iStrain, iQuality);
            string  result   = "QTY_RESULT|" + iType + "|" + iStrain + "|" +
                               iQuality + "|" + (string)have + "|" +
                               (string)(have >= required);
            llMessageLinked(LINK_SET, CHAN_COMMS, result, NULL_KEY);
        }

        // Full raw inventory dump (for saving to bag/jar, or world object requests)
        else if (cmd == "REQUEST_RAW_INVENTORY")
        {
            string filterType = llList2String(parts, 1); // optional filter
            string reqObjKey  = llList2String(parts, 2); // optional requesting object

            string output;
            if (filterType != "" && filterType != "all")
            {
                // Build filtered serialization  -  only matching item types
                string filtered = "";
                integer len = llGetListLength(g_inventory);
                integer i;
                for (i = 0; i < len; i += STRIDE)
                {
                    if (llList2String(g_inventory, i) == filterType)
                    {
                        string slot =
                            llList2String(g_inventory, i)   + "~" +
                            llList2String(g_inventory, i+1) + "~" +
                            llList2String(g_inventory, i+2) + "~" +
                            llList2String(g_inventory, i+3) + "~" +
                            llList2String(g_inventory, i+4);
                        if (filtered == "") filtered = slot;
                        else filtered += "^" + slot;
                    }
                }
                output = filtered;
            }
            else
            {
                output = serializeInventory();
            }

            llMessageLinked(LINK_SET, CHAN_COMMS,
                "RAW_INVENTORY|" + output + "|" + filterType + "|" + reqObjKey,
                NULL_KEY);
        }
    }
}
