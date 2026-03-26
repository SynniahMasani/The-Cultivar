// ================================================================
// THE CULTIVAR  -  Var Papers Box Script
// Version: 1.0
// Lives inside: any TC Var Papers world object
//
// WHAT IT DOES:
//   Purchasable rolling papers. When touched by the registered HUD
//   owner, gives PAPERS_PER_BOX rolling papers directly into the
//   player's HUD inventory via TC_ADD_ITEM. Papers are required to
//   roll joints and spliffs at the Rolling Tray.
//
//   Item stored as: papers_raw | Var Papers | standard | qty | Var
//
// PING / REGISTER FLOW:
//   1. Rez → pingHUD() → llRegionSay(TC_OBJECT_PING_CHAN,
//        "TC_PING|key|papers_box|replyChannel")
//   2. HUD_Comms responds on replyChannel:
//        "TC_REGISTER|ownerKey|hudChannel|ownerName|brandName"
//   3. Box stores g_hudOwner and g_hudChannel, opens listen on it
//   4. Touch → verify owner → send TC_ADD_ITEM on g_hudChannel
//   5. Box plays effects and confirms to player
//
// NON-OWNER TOUCH:
//   Returns message identifying the registered owner.
//
// UNREGISTERED TOUCH:
//   Re-attempts ping; informs toucher to equip their HUD.
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

integer PAPERS_PER_BOX = 50;

integer g_replyChannel = 0;
integer g_listenHandle = 0;
integer g_listenHUD    = 0;
key     g_hudOwner     = NULL_KEY;
integer g_hudChannel   = 0;
integer g_registered   = FALSE;
integer g_busy         = FALSE;
integer g_opened       = FALSE;  // TRUE once papers have been given

// ----------------------------------------------------------------
integer randomNegChan()
{
    return (integer)(llFrand(999999.0) * -1) - 100000;
}

// ----------------------------------------------------------------
pingHUD()
{
    g_registered = FALSE;
    g_hudOwner   = NULL_KEY;

    if (g_listenHandle) llListenRemove(g_listenHandle);
    g_replyChannel = randomNegChan();
    g_listenHandle = llListen(g_replyChannel, "", NULL_KEY, "");

    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|papers_box|" +
        (string)g_replyChannel);

    llSetTimerEvent(15.0);
}

// ----------------------------------------------------------------
setHoverText()
{
    if (g_opened)
        llSetText("Var Papers  -  King Size Slim\nEmpty",
                  <0.5, 0.5, 0.5>, 0.7);
    else if (g_registered)
        llSetText("Var Papers  -  King Size Slim\n" +
                  (string)PAPERS_PER_BOX + " per box  |  Touch to open",
                  <0.85, 0.2, 0.2>, 1.0);
    else
        llSetText("Var Papers  -  King Size Slim\nWaiting for HUD...",
                  <0.6, 0.6, 0.6>, 0.8);
}

// ================================================================
default
{
    state_entry()
    {
        g_opened = (llLinksetDataRead("papers_opened") == "1");
        setHoverText();
        if (!g_opened) pingHUD();
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer change)     { if (change & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        llSetTimerEvent(0.0);

        if (!g_registered)
        {
            if (g_listenHandle) llListenRemove(g_listenHandle);
            g_listenHandle = 0;
            setHoverText();
            return;
        }

        // Post-open cooldown expired
        g_busy = FALSE;
        llParticleSystem([]);
        setHoverText();
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);

        if (!g_registered || g_hudOwner == NULL_KEY)
        {
            pingHUD();
            llRegionSayTo(toucher, 0,
                "No HUD detected. Make sure your Cultivar HUD is worn, then try again.");
            return;
        }

        if (toucher != g_hudOwner)
        {
            llRegionSayTo(toucher, 0,
                "This box belongs to " + llGetDisplayName(g_hudOwner) + ".");
            return;
        }

        if (g_opened)
        {
            llRegionSayTo(toucher, 0, "This box is empty.");
            return;
        }

        if (g_busy)
        {
            llRegionSayTo(toucher, 0, "Opening  -  just a moment.");
            return;
        }

        g_busy   = TRUE;
        g_opened = TRUE;
        llLinksetDataWrite("papers_opened", "1");

        // Add papers to HUD main inventory
        llRegionSayTo(toucher, g_hudChannel,
            "TC_ADD_ITEM|papers_raw|Var Papers|standard|" +
            (string)PAPERS_PER_BOX + "|Var");

        // Celebration burst
        llParticleSystem([
            PSYS_PART_FLAGS,           PSYS_PART_EMISSIVE_MASK,
            PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
            PSYS_PART_START_COLOR,     <0.85, 0.2, 0.2>,
            PSYS_PART_END_COLOR,       <1.0, 0.8, 0.8>,
            PSYS_PART_START_ALPHA,     1.0,
            PSYS_PART_END_ALPHA,       0.0,
            PSYS_PART_START_SCALE,     <0.03, 0.03, 0.0>,
            PSYS_PART_END_SCALE,       <0.01, 0.01, 0.0>,
            PSYS_PART_MAX_AGE,         1.5,
            PSYS_SRC_BURST_RATE,       0.05,
            PSYS_SRC_BURST_PART_COUNT, 10,
            PSYS_SRC_BURST_SPEED_MIN,  0.1,
            PSYS_SRC_BURST_SPEED_MAX,  0.4,
            PSYS_SRC_MAX_AGE,          0.3
        ]);
        llPlaySound("wrapper_open", 0.5);

        llRegionSayTo(g_hudOwner, 0,
            "Added " + (string)PAPERS_PER_BOX + "x Var Papers to your inventory.");

        llSetText("Opened!", <0.5, 0.9, 0.5>, 1.0);
        llSetTimerEvent(3.0);
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (channel == g_replyChannel && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);

            if (g_listenHandle) llListenRemove(g_listenHandle);
            g_listenHandle = 0;
            llSetTimerEvent(0.0);

            g_hudOwner   = regOwner;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;

            if (g_listenHUD) llListenRemove(g_listenHUD);
            g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");

            setHoverText();
        }
    }
}
