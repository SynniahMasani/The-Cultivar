// ================================================================
// THE CULTIVAR — HUD Animation Script
// Version: 1.0
// Handles: All avatar animation playback triggered by smoking,
//          passing, and session events. Kept isolated so animation
//          bugs never affect inventory or comms.
//
// ANIMATION NAMING CONVENTION (animations stored in HUD object):
//   smoke_joint_reggie_idle    — holding joint, reggie tier
//   smoke_joint_mids_idle      — holding joint, mids tier
//   smoke_joint_loud_idle      — holding joint, loud tier
//   smoke_joint_exotic_idle    — holding joint, exotic tier
//   smoke_blunt_[quality]_idle
//   smoke_pipe_[quality]_idle
//   smoke_bong_[quality]_idle
//   smoke_puff                 — the actual hit animation (short, loops back)
//   pass_give                  — passing to someone animation
//   pass_receive               — receiving from someone animation
//   smoke_sit_[quality]_idle   — sitting/session variant
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_IDENTITY  = 400;
integer CHAN_ANIMATION = 500;

// Currently playing animation name (so we can stop it cleanly)
string  g_currentAnim     = "";
string  g_currentStrain   = "";
string  g_currentQuality  = "";
string  g_currentItemType = "";

// Puff timer — how often the puff animation fires over the idle
float   PUFF_INTERVAL = 12.0; // seconds between puffs
integer g_puffTimerActive = FALSE;
integer g_puffCount       = 0;
integer MAX_PUFFS         = 5; // smoke stops naturally after this many puffs (~60s)

// ----------------------------------------------------------------
// Stop whatever is currently playing
// ----------------------------------------------------------------
stopCurrentAnim()
{
    if (g_currentAnim != "")
    {
        llStopAnimation(g_currentAnim);
        g_currentAnim = "";
    }
    if (g_puffTimerActive)
    {
        llSetTimerEvent(0.0);
        g_puffTimerActive = FALSE;
    }
    g_puffCount = 0;
    // Notify UI so it can turn off the smoke button glow and clear state
    llMessageLinked(LINK_SET, CHAN_UI, "SMOKE_STOPPED", NULL_KEY);
}

// ----------------------------------------------------------------
// Build the idle animation name from item type and quality
// ----------------------------------------------------------------
string buildAnimName(string itemType, string quality)
{
    // Normalize itemType to an animation category
    string category = "joint"; // default
    if (itemType == "blunt")      category = "blunt";
    else if (itemType == "pipe")  category = "pipe";
    else if (itemType == "bong")  category = "bong";
    else if (itemType == "joint") category = "joint";
    else if (llSubStringIndex(itemType, "joint") != -1) category = "joint";
    else if (llSubStringIndex(itemType, "blunt") != -1) category = "blunt";

    return "smoke_" + category + "_" + quality + "_idle";
}

// ----------------------------------------------------------------
// Start a smoking animation
// ----------------------------------------------------------------
startSmokeAnim(string strain, string quality, string itemType)
{
    stopCurrentAnim();

    g_currentStrain   = strain;
    g_currentQuality  = quality;
    g_currentItemType = itemType;
    g_currentAnim     = buildAnimName(itemType, quality);
    g_puffCount       = 0;

    // Check the animation exists in inventory before playing
    if (llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
    {
        llStartAnimation(g_currentAnim);
    }
    else
    {
        // Fallback to basic joint animation if specific one not found
        g_currentAnim = "smoke_joint_reggie_idle";
        if (llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
            llStartAnimation(g_currentAnim);
        else
            llOwnerSay("[Animation] Missing animation: " + g_currentAnim);
    }

    // Start puff timer
    llSetTimerEvent(PUFF_INTERVAL);
    g_puffTimerActive = TRUE;
}

// ----------------------------------------------------------------
// Play the short puff animation over the idle
// ----------------------------------------------------------------
playPuffAnim()
{
    // Puff anim is a short overlay — it plays then idle resumes naturally
    if (llGetInventoryType("smoke_puff") == INVENTORY_ANIMATION)
    {
        llStopAnimation(g_currentAnim);
        llStartAnimation("smoke_puff");
        // Short delay then resume idle
        llSleep(2.5);
        llStopAnimation("smoke_puff");
        if (g_currentAnim != "" &&
            llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
        {
            llStartAnimation(g_currentAnim);
        }
    }
}

// ----------------------------------------------------------------
// Play a pass animation (give or receive, one-shot)
// ----------------------------------------------------------------
playPassAnim(string direction)
{
    string animName = "pass_" + direction; // pass_give or pass_receive
    if (llGetInventoryType(animName) == INVENTORY_ANIMATION)
    {
        // Temporarily stop idle
        if (g_currentAnim != "") llStopAnimation(g_currentAnim);
        llStartAnimation(animName);
        llSleep(2.0);
        llStopAnimation(animName);
        // Resume idle if still smoking
        if (g_currentAnim != "" &&
            llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
        {
            llStartAnimation(g_currentAnim);
        }
    }
}

// ================================================================
default
{
    state_entry()
    {
        // Nothing to do on start — wait for link messages
    }

    on_rez(integer start_param)
    {
        stopCurrentAnim();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            stopCurrentAnim();
            llResetScript();
        }
    }

    timer()
    {
        // Periodic puff animation while smoking
        if (g_puffTimerActive && g_currentAnim != "")
        {
            g_puffCount++;
            if (g_puffCount >= MAX_PUFFS)
            {
                // Item is spent — stop everything and notify UI
                stopCurrentAnim();
                return;
            }
            playPuffAnim();
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != CHAN_ANIMATION) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Comms sends this when a smoke event is confirmed
        if (cmd == "START_SMOKE_ANIM")
        {
            // START_SMOKE_ANIM|strainName|quality|itemType
            string strain   = llList2String(parts, 1);
            string quality  = llList2String(parts, 2);
            string itemType = llList2String(parts, 3);
            if (itemType == "") itemType = "joint"; // safe default
            startSmokeAnim(strain, quality, itemType);
        }

        // Session ended or item depleted
        else if (cmd == "STOP_SMOKE_ANIM")
        {
            stopCurrentAnim();
        }

        // Passing an item to someone
        else if (cmd == "PLAY_PASS_GIVE")
        {
            playPassAnim("give");
        }

        // Receiving a passed item
        else if (cmd == "PLAY_PASS_RECEIVE")
        {
            playPassAnim("receive");
        }

        // UI requests current animation state (for display)
        else if (cmd == "REQUEST_ANIM_STATE")
        {
            string state = "IDLE";
            if (g_currentAnim != "")
                state = "SMOKING|" + g_currentStrain + "|" + g_currentQuality;
            llMessageLinked(LINK_SET, CHAN_UI, "ANIM_STATE|" + state, NULL_KEY);
        }

        // Switch animation quality on the fly (e.g. passed a better item)
        else if (cmd == "SWITCH_ANIM_QUALITY")
        {
            string newQuality = llList2String(parts, 1);
            if (g_currentAnim != "")
            {
                startSmokeAnim(g_currentStrain, newQuality, g_currentItemType);
            }
        }
    }
}
