// ================================================================
// THE CULTIVAR  -  HUD Unpacker Script
// Version: 2.0
//
// WHAT IT DOES:
//   Automatically delivers all bundled items as an organised folder
//   the moment the HUD is attached. Plays a sound, shows visual
//   feedback, then requests permission to auto-detach.
//
// SETUP:
//   1. Set FOLDER_NAME to the label you want in the recipient's
//      inventory (e.g. "The Cultivar Kit").
//   2. Set SOUND_NAME to the sound in this object's inventory that
//      should play on delivery (or leave blank to skip).
//   3. Add all items to deliver into this object's inventory.
//      The unpacker script and the sound are excluded automatically.
//   4. The player will see one permission dialog ("Allow to attach /
//      detach?") — they must click Allow for the HUD to auto-detach
//      after delivery. If they deny, they are asked to detach manually.
//
// NOTES:
//   INVENTORY_SCRIPT items ARE included so world-object scripts
//   (Rolling Tray, Edibles Bench, etc.) get delivered alongside
//   notecards, textures, and objects. Only THIS script is skipped.
// ================================================================

string  FOLDER_NAME = "The Cultivar Kit";
string  SOUND_NAME  = "Evil Laugh sound";

list EXCLUDED = [
    "Evil Laugh sound"
    // The unpacker script itself is always excluded via llGetScriptName()
];

// ---- Internal state ----
integer g_hasAttachPerm = FALSE;
integer g_delivered     = FALSE;
integer g_detaching     = FALSE;
integer g_displayLink   = -1;

// ================================================================
// Helpers
// ================================================================

integer findLinkByName(string primName)
{
    integer total = llGetNumberOfPrims();
    integer i;
    for (i = 1; i <= total; ++i)
    {
        if (llGetLinkName(i) == primName)
            return i;
    }
    return -1;
}

integer isExcluded(string itemName)
{
    if (itemName == llGetScriptName())            return TRUE;
    if (llListFindList(EXCLUDED, [itemName]) != -1) return TRUE;
    return FALSE;
}

list buildGiveList()
{
    list items;
    list types = [
        INVENTORY_OBJECT,   INVENTORY_NOTECARD,  INVENTORY_LANDMARK,
        INVENTORY_CLOTHING, INVENTORY_BODYPART,  INVENTORY_GESTURE,
        INVENTORY_ANIMATION,INVENTORY_SOUND,     INVENTORY_TEXTURE,
        INVENTORY_SCRIPT
    ];
    integer t;
    for (t = 0; t < llGetListLength(types); ++t)
    {
        integer itype = llList2Integer(types, t);
        integer count = llGetInventoryNumber(itype);
        integer i;
        for (i = 0; i < count; ++i)
        {
            string iname = llGetInventoryName(itype, i);
            if (!isExcluded(iname))
                items += [iname];
        }
    }
    return items;
}

setIdleVisuals()
{
    if (g_displayLink != -1)
        llSetLinkPrimitiveParamsFast(g_displayLink,
            [PRIM_GLOW, ALL_SIDES, 0.03]);
    llSetText("Touch to unpack", <1.0, 0.95, 0.8>, 1.0);
}

setActiveVisuals()
{
    if (g_displayLink != -1)
        llSetLinkPrimitiveParamsFast(g_displayLink,
            [PRIM_GLOW, ALL_SIDES, 0.12]);
    llSetText("Delivering items...", <1.0, 0.8, 0.3>, 1.0);
}

doUnpack()
{
    if (g_delivered) return; // only run once
    g_delivered = TRUE;

    setActiveVisuals();

    if (SOUND_NAME != "" && llGetInventoryType(SOUND_NAME) == INVENTORY_SOUND)
        llPlaySound(llGetInventoryKey(SOUND_NAME), 0.5);

    list giveItems = buildGiveList();
    if (llGetListLength(giveItems) > 0)
    {
        llGiveInventoryList(llGetOwner(), FOLDER_NAME, giveItems);
        llOwnerSay("Your items have been delivered to a folder called \""
                   + FOLDER_NAME + "\" in your inventory.");
    }
    else
    {
        llOwnerSay("Nothing to deliver — this unpacker is empty.");
    }

    llSetText("Done!  Detaching...", <0.5, 1.0, 0.5>, 1.0);
    g_detaching = TRUE;
    llSetTimerEvent(2.5); // brief pause, then detach
}

// ================================================================
default
// ================================================================
{
    state_entry()
    {
        g_displayLink = findLinkByName("Display");
        setIdleVisuals();
        // Request permission to auto-detach after delivery.
        // The player will see one dialog — clicking Allow enables
        // the HUD to detach itself cleanly after unpacking.
        llRequestPermissions(llGetOwner(), PERMISSION_ATTACH);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & (CHANGED_LINK | CHANGED_INVENTORY | CHANGED_OWNER))
        {
            g_displayLink = findLinkByName("Display");
            setIdleVisuals();
        }
    }

    run_time_permissions(integer perm)
    {
        g_hasAttachPerm = (perm & PERMISSION_ATTACH) != 0;
    }

    // Auto-unpack the moment the HUD is worn
    attach(key id)
    {
        if (id == NULL_KEY) return; // being detached, not attached
        // Re-request permissions in case state_entry fired before attach
        llRequestPermissions(llGetOwner(), PERMISSION_ATTACH);
        doUnpack();
    }

    // Manual trigger — owner can also touch to unpack if auto didn't fire
    touch_start(integer nd)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        doUnpack();
    }

    timer()
    {
        llSetTimerEvent(0.0);

        if (!g_detaching) return;

        if (g_hasAttachPerm)
        {
            llDetachFromAvatar();
        }
        else
        {
            llOwnerSay("Auto-detach needs permission. Please detach this "
                       "HUD manually from your viewer's worn items list.");
        }
    }
}
