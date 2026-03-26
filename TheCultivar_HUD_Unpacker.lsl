// ================================================================
// THE CULTIVAR  -  HUD Unpacker Script
// Version: 1.0
// Lives inside: the TC HUD object
//
// WHAT IT DOES:
//   Delivers all non-script items from the HUD's inventory to the
//   owner when touched. Useful for first-time setup, allowing the
//   player to receive notecards, textures, objects, and any other
//   assets bundled with the HUD.
//
//   Scripts (INVENTORY_SCRIPT) are intentionally skipped because
//   they run inside the HUD itself and are not meant to be given out.
//
// USAGE:
//   Touch the HUD after first attaching it. All bundled items will
//   be delivered to your inventory automatically.
// ================================================================

integer g_busy = FALSE;

default
{
    state_entry()
    {
        g_busy = FALSE;
    }

    attach(key id)
    {
        // Reset on detach
        if (id == NULL_KEY) g_busy = FALSE;
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);
        if (toucher != llGetOwner()) return;
        if (g_busy)
        {
            llOwnerSay("Already unpacking — please wait.");
            return;
        }

        g_busy = TRUE;

        integer total   = llGetInventoryNumber(INVENTORY_ALL);
        integer given   = 0;
        string  skipped = "";
        integer i;

        for (i = 0; i < total; i++)
        {
            string itemName = llGetInventoryName(INVENTORY_ALL, i);
            integer itemType = llGetInventoryType(itemName);

            // Skip scripts — they run inside the HUD, not given to the player
            if (itemType == INVENTORY_SCRIPT) jump next_item;

            llGiveInventory(llGetOwner(), itemName);
            given++;

            @next_item;
        }

        if (given > 0)
            llOwnerSay("Delivered " + (string)given + " item" +
                       (string)(given > 1) + " to your inventory.");
        else
            llOwnerSay("No items to deliver (scripts are kept inside the HUD).");

        g_busy = FALSE;
    }
}
