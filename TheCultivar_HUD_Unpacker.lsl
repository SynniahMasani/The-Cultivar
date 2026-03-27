// ================================================================
// THE CULTIVAR  -  HUD Unpacker Script
// Version: 2.1
//
// WHAT IT DOES:
//   Automatically delivers all bundled items as an organised folder
//   the moment the HUD is attached. Plays a sound, shows visual
//   feedback, then requests permission to auto-detach.
//
// SETUP:
//   1. Set FOLDER_NAME to the label you want in the recipient's
//      inventory (e.g. "The Cultivar Kit").
//   2. Set SOUND_NAME to the name of a sound in this object's inventory
//      that plays on delivery, or "" to skip sound entirely.
//      IMPORTANT: the sound must stay INSIDE this object for playback.
//      Add it to EXCLUDED below so it plays locally but is NOT given
//      to recipients (they do not need it in their inventory).
//   3. Add all items to deliver into this object's inventory.
//      The unpacker script is excluded automatically.
//   4. The player will see one permission dialog ("Allow to attach /
//      detach?") — they must click Allow for the HUD to auto-detach
//      after delivery. If they deny, they are asked to detach manually.
//
// NOTES:
//   Scripts are intentionally NOT delivered. Any scripts that need to
//   reach the player should be bundled inside an INVENTORY_OBJECT item
//   (e.g. put UpdateClient inside the WeedJar object before packaging).
//   Delivering scripts directly via llGiveInventoryList causes the entire
//   transfer to fail silently if any script lacks PERM_TRANSFER.
//
//   Each new owner automatically gets a clean delivery because
//   g_delivered is reset on both on_rez and CHANGED_OWNER.
// ================================================================

string  FOLDER_NAME = "The Cultivar Kit";
string  SOUND_NAME  = "Evil Laugh sound";   // must be in THIS object's inventory; set "" to disable

list EXCLUDED = [
    "Evil Laugh sound"  // stays in object for local playback, not given to recipient
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
    // Scripts are intentionally excluded: they either run inside this HUD
    // (and must not be re-delivered) or are already bundled inside the kit
    // objects (INVENTORY_OBJECT entries). Including scripts here would cause
    // llGiveInventoryList to fail silently whenever a HUD-internal script
    // lacks PERM_TRANSFER, leaving the recipient with nothing at all.
    list types = [
        INVENTORY_OBJECT,   INVENTORY_NOTECARD,  INVENTORY_LANDMARK,
        INVENTORY_CLOTHING, INVENTORY_BODYPART,  INVENTORY_GESTURE,
        INVENTORY_ANIMATION,INVENTORY_SOUND,     INVENTORY_TEXTURE
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

    if (SOUND_NAME != "")
    {
        key soundKey = llGetInventoryKey(SOUND_NAME);
        if (soundKey != NULL_KEY)
            llPlaySound(soundKey, 0.5);
        // If the sound is missing from this object's inventory the play is
        // silently skipped — no script error, no effect on item delivery.
    }

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
        // When a copy is given to a new owner, reset delivery state so they
        // can unpack normally.  This fires even if on_rez / attach ordering
        // means the attach event ran before on_rez had a chance to reset.
        if (change & CHANGED_OWNER)
        {
            g_delivered   = FALSE;
            g_detaching   = FALSE;
            g_hasAttachPerm = FALSE;
            llSetTimerEvent(0.0);
        }

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

    // Auto-unpack the moment the HUD is worn.
    // NOTE: on some simulators attach fires before on_rez, so g_delivered
    // may still hold TRUE from a previous owner's session.  We reset it
    // here explicitly — on_rez → llResetScript() also resets everything,
    // but that may happen after this event on certain region types.
    attach(key id)
    {
        if (id == NULL_KEY) return; // being detached, not attached
        g_delivered     = FALSE;
        g_detaching     = FALSE;
        g_hasAttachPerm = FALSE;
        llSetTimerEvent(0.0);
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
