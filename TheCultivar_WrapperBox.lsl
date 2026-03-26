// ================================================================
// THE CULTIVAR  -  Synwoods Wrapper Box Script
// Version: 1.0
// Lives inside: any TC Synwoods Wrapper Box world object
//
// WHAT IT DOES:
//   Purchasable flavor pack. When touched by the registered HUD
//   owner, gives WRAPPERS_PER_BOX blunt wrappers of WRAPPER_FLAVOR
//   directly into the player's HUD inventory via TC_WRAPPER_GIVE.
//
// PER-VARIANT SETUP:
//   Set WRAPPER_FLAVOR to the desired flavor string for each copy.
//
// FLAVORS:
//   "Angel's Breath"  — vanilla cream / ivory
//   "Honey Berry"     — berry / purple-magenta
//   "Dark Halo"       — chocolate / dark brown
//   "Russian Cream"   — cream / grey-silver
//   "Sweet Aromatic"  — aromatic / warm orange-brown
//
// PING / REGISTER FLOW:
//   1. Rez → pingHUD() → llRegionSay(TC_OBJECT_PING_CHAN,
//        "TC_PING|key|WrapperBox|replyChannel")
//   2. HUD_Comms responds on replyChannel:
//        "TC_REGISTER|ownerKey|hudChannel|ownerName|brandName"
//   3. Box stores g_hudOwner and g_hudChannel, opens listen on it
//   4. Touch → verify owner → send TC_WRAPPER_GIVE on g_hudChannel
//   5. HUD_Comms adds wrappers, responds TC_WRAPPER_ACK
//   6. Box plays effects, confirms to player, resets hover text
//
// NON-OWNER TOUCH:
//   Returns message identifying the registered owner.
//
// UNREGISTERED TOUCH:
//   Re-attempts ping; informs toucher to equip their HUD.
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;
integer HOVER_FADE_SECS = 30;

string  WRAPPER_FLAVOR   = "Angel's Breath";
integer WRAPPERS_PER_BOX = 5;

integer g_replyChannel = 0;
integer g_listenHandle = 0;
integer g_listenHUD    = 0;
key     g_hudOwner     = NULL_KEY;
integer g_hudChannel   = 0;
integer g_registered   = FALSE;
integer g_awaitingAck  = FALSE;
integer g_opened       = FALSE;  // TRUE once wrappers have been given

// ----------------------------------------------------------------
// Generate a random guaranteed-negative reply channel.
// Range: -100000 to -1099998
// ----------------------------------------------------------------
integer randomNegChan()
{
    return (integer)(llFrand(999999.0) * -1) - 100000;
}

// ----------------------------------------------------------------
// Broadcast TC_PING so the nearest HUD can register with us.
// Opens a timed listen on the reply channel (15 s timeout).
// ----------------------------------------------------------------
pingHUD()
{
    g_registered  = FALSE;
    g_awaitingAck = FALSE;
    g_hudOwner    = NULL_KEY;

    if (g_listenHandle) llListenRemove(g_listenHandle);
    g_replyChannel = randomNegChan();
    g_listenHandle = llListen(g_replyChannel, "", NULL_KEY, "");

    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|WrapperBox|" +
        (string)g_replyChannel);

    llSetTimerEvent(15.0);
}

// ----------------------------------------------------------------
// Update hover text to reflect current registration state.
// ----------------------------------------------------------------
setHoverText()
{
    if (g_opened)
        llSetText("Synwoods  -  " + WRAPPER_FLAVOR +
                  "\nEmpty", <0.5, 0.5, 0.5>, 0.7);
    else if (g_registered)
        llSetText("Synwoods  -  " + WRAPPER_FLAVOR +
                  "\nTouch to open!", <0.9, 0.8, 0.5>, 1.0);
    else
        llSetText("Synwoods  -  " + WRAPPER_FLAVOR +
                  "\nWaiting for HUD...", <0.6, 0.6, 0.6>, 0.8);
}

// ================================================================
default
{
    state_entry()
    {
        g_opened = (llLinksetDataRead("wrapper_opened") == "1");
        setHoverText();
        if (!g_opened) pingHUD();
        else llSetTimerEvent(HOVER_FADE_SECS);
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
        // Idle fade: box is opened (empty) and not waiting — fade and stop
        if (g_opened && !g_awaitingAck)
        {
            llSetText("Synwoods  -  " + WRAPPER_FLAVOR +
                      "\nEmpty", <0.5, 0.5, 0.5>, 0.0);
            llSetTimerEvent(0.0);
            return;
        }

        llSetTimerEvent(0.0);

        if (!g_registered)
        {
            // Ping timed out — no HUD found in range
            if (g_listenHandle) llListenRemove(g_listenHandle);
            g_listenHandle = 0;
            setHoverText();
            llSetTimerEvent(HOVER_FADE_SECS);
        }
        else if (g_awaitingAck)
        {
            // HUD did not respond to TC_WRAPPER_GIVE in time
            g_awaitingAck = FALSE;
            llRegionSayTo(g_hudOwner, 0,
                "Couldn't reach your HUD. Make sure it is still worn and try again.");
            setHoverText();
            llSetTimerEvent(HOVER_FADE_SECS);
        }
        else
        {
            // Post-success: clear particles and reset hover text
            llParticleSystem([]);
            setHoverText();
            llSetTimerEvent(HOVER_FADE_SECS);
        }
    }

    touch_start(integer nd)
    {
        setHoverText();
        key toucher = llDetectedKey(0);

        if (g_opened)
        {
            llRegionSayTo(toucher, 0, "This box is empty.");
            return;
        }

        if (!g_registered || g_hudOwner == NULL_KEY)
        {
            // Re-attempt registration and inform the toucher
            pingHUD();
            llRegionSayTo(toucher, 0,
                "No HUD detected. Make sure your Cultivar HUD is worn, then try again.");
            return;
        }

        if (toucher != g_hudOwner)
        {
            llRegionSayTo(toucher, 0,
                "This wrapper box belongs to " + llGetDisplayName(g_hudOwner) + ".");
            return;
        }

        if (g_awaitingAck)
        {
            llRegionSayTo(toucher, 0, "Still processing  -  please wait a moment.");
            return;
        }

        // Send wrappers to the HUD on the private channel
        llRegionSayTo(toucher, g_hudChannel,
            "TC_WRAPPER_GIVE|" + WRAPPER_FLAVOR + "|" +
            (string)WRAPPERS_PER_BOX + "|" + (string)toucher);

        g_awaitingAck = TRUE;
        llSetTimerEvent(10.0);
        llSetText("Opening...", <0.9, 0.85, 0.5>, 1.0);
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- HUD responds to ping ----
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

        // ---- HUD confirms wrappers were added ----
        else if (channel == g_hudChannel && cmd == "TC_WRAPPER_ACK")
        {
            llSetTimerEvent(0.0);
            g_awaitingAck = FALSE;
            g_opened      = TRUE;
            llLinksetDataWrite("wrapper_opened", "1");

            // Quality-neutral celebration burst
            llParticleSystem([
                PSYS_PART_FLAGS,           PSYS_PART_EMISSIVE_MASK,
                PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
                PSYS_PART_START_COLOR,     <0.9, 0.8, 0.5>,
                PSYS_PART_START_ALPHA,     1.0,
                PSYS_PART_END_ALPHA,       0.0,
                PSYS_PART_START_SCALE,     <0.04, 0.04, 0.0>,
                PSYS_PART_END_SCALE,       <0.01, 0.01, 0.0>,
                PSYS_PART_MAX_AGE,         1.5,
                PSYS_SRC_BURST_RATE,       0.05,
                PSYS_SRC_BURST_PART_COUNT, 8,
                PSYS_SRC_BURST_SPEED_MIN,  0.1,
                PSYS_SRC_BURST_SPEED_MAX,  0.3,
                PSYS_SRC_MAX_AGE,          0.3
            ]);
            llPlaySound("wrapper_open", 0.5);

            llRegionSayTo(g_hudOwner, 0,
                "Added " + (string)WRAPPERS_PER_BOX + "x " +
                WRAPPER_FLAVOR + " wrappers to your inventory.");

            llSetText("Opened!", <0.5, 0.9, 0.5>, 1.0);
            llSetTimerEvent(3.0);
        }
    }
}
