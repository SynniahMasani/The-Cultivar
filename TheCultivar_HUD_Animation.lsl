// ================================================================
// THE CULTIVAR  -  HUD Animation Script
// Version: 1.1
// Handles: All avatar animation playback triggered by smoking,
//          passing, and session events. Kept isolated so animation
//          bugs never affect inventory or comms.
//
// ANIMATION NAMING CONVENTION (animations stored in HUD object):
//
//   Gender-aware: the script detects OBJECT_BODY_SHAPE_TYPE and
//   appends _female or _male to every animation name. If the
//   gendered variant is not found it falls back to the base name.
//
//   Idle Anims (loop while smoking):
//     smoke_joint_[quality]_idle_female  /  smoke_joint_[quality]_idle_male
//     smoke_blunt_[quality]_idle_female  /  smoke_blunt_[quality]_idle_male
//     smoke_pipe_[quality]_idle_female   /  smoke_pipe_[quality]_idle_male
//     smoke_bong_[quality]_idle_female   /  smoke_bong_[quality]_idle_male
//     [quality] = reggie | mids | loud | exotic
//
//   Action Anims (one-shot, ~2-2.5 s):
//     smoke_puff_female  /  smoke_puff_male   -  the actual hit overlay
//     pass_give_female   /  pass_give_male    -  handing off
//     pass_receive_female / pass_receive_male -  receiving
//
//   Non-gendered fallbacks (optional, used if gendered missing):
//     smoke_joint_reggie_idle, smoke_puff, pass_give, pass_receive ...
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

// Puff timer  -  how often the puff animation fires over the idle.
// This also re-triggers the idle animation each cycle, acting as a
// loop refresh for non-looping animations. Runs until STOP_SMOKE_ANIM.
float   PUFF_INTERVAL = 12.0; // seconds between puffs / idle refreshes
integer g_puffTimerActive = FALSE;

// Pending animation flags  -  used instead of llSleep() to return
// control to the event queue while short anims play out.
integer g_puffInProgress = FALSE; // TRUE while smoke_puff overlay is active
integer g_passInProgress = FALSE; // TRUE while pass_give/receive is active
string  g_passAnimName   = "";    // which pass anim is currently playing
string  g_puffAnimName   = "";    // which puff anim is currently playing

// Gender-aware animation suffix (_female or _male)
string  g_genderSuffix   = "_female"; // default; updated on state_entry and on_rez

// Animation permission flag
integer g_hasAnimPerm = FALSE;

// Pending start request: if startSmokeAnim is called before perms are
// granted, we stash the args and replay them inside onPermissionsReady.
integer g_startPending  = FALSE;
string  g_pendingStrain   = "";
string  g_pendingQuality  = "";
string  g_pendingItemType = "";

// RLV high-effects state
integer g_fxActive = FALSE;

// ================================================================
// Hybrid permission layer  -  try Experience first, fall back to classic
// ================================================================
integer PERM_NONE    = 0;
integer PERM_XP      = 1;
integer PERM_CLASSIC = 2;

integer g_permMode    = 0;
key     g_permAgent   = NULL_KEY;
integer g_classicMask = 0;       // PERMISSION_TRIGGER_ANIMATION here
string  g_permReason  = "";

requestHybridPermissions(key agent, string reason)
{
    g_permAgent  = agent;
    g_permReason = reason;
    g_permMode   = PERM_NONE;
    llRequestExperiencePermissions(agent, "");
}

// ----------------------------------------------------------------
// RLV high effects (visual blur + warm tint while smoking)
// Mode 2 = blur. Quality scales the intensity:
//   reggie  -> very subtle
//   mids    -> light
//   loud    -> moderate
//   exotic  -> strong
// Requires an RLV-compatible viewer; non-RLV viewers ignore the
// commands silently. Toggle stored in linkset data hud_fx_enabled.
// ----------------------------------------------------------------
fxStartHigh(string quality)
{
    if (llLinksetDataRead("hud_fx_enabled") != "1") return;
    if (g_fxActive) return;

    float blur     = 0.10;
    float distMin  = 5.0;
    float distMax  = 25.0;
    string tintCol = "1.0;0.92;0.80;0.10"; // warm amber, light alpha

    if (quality == "mids")
    {
        blur = 0.18;
        tintCol = "1.0;0.90;0.75;0.14";
    }
    else if (quality == "loud")
    {
        blur = 0.28;
        tintCol = "1.0;0.85;0.70;0.18";
        distMax = 30.0;
    }
    else if (quality == "exotic")
    {
        blur = 0.40;
        tintCol = "0.95;0.78;0.95;0.22"; // hint of purple haze
        distMax = 40.0;
    }

    // Configure and activate sphere effect
    llOwnerSay("@setsphere_mode:2=force");
    llOwnerSay("@setsphere_origin:0=force");
    llOwnerSay("@setsphere_distmin:" + (string)distMin + "=force");
    llOwnerSay("@setsphere_distmax:" + (string)distMax + "=force");
    llOwnerSay("@setsphere_distextend:1=force");
    llOwnerSay("@setsphere_param:" + (string)blur + "=force");
    llOwnerSay("@setsphere_tint:" + tintCol + "=force");
    llOwnerSay("@setsphere=force");

    g_fxActive = TRUE;
}

fxClearHigh()
{
    if (!g_fxActive) return;
    llOwnerSay("@setsphere_mode:0=force");
    llOwnerSay("@setsphere=clear");
    g_fxActive = FALSE;
}

// ----------------------------------------------------------------
// Detect avatar body shape type and return the animation suffix
// ----------------------------------------------------------------
string getGenderSuffix()
{
    list details = llGetObjectDetails(llGetOwner(), [OBJECT_BODY_SHAPE_TYPE]);
    integer bodyType = llList2Integer(details, 0);
    if (bodyType == 1) return "_male";
    return "_female";
}

// ----------------------------------------------------------------
// Return the gendered variant of an animation if it exists in
// inventory, otherwise return the base (non-gendered) name.
// ----------------------------------------------------------------
string resolveAnim(string baseName)
{
    string gendered = baseName + g_genderSuffix;
    if (llGetInventoryType(gendered) == INVENTORY_ANIMATION)
        return gendered;
    return baseName;
}

// ----------------------------------------------------------------
// Stop whatever is currently playing
// ----------------------------------------------------------------
stopCurrentAnim()
{
    if (g_hasAnimPerm && g_currentAnim != "")
    {
        llStopAnimation(g_currentAnim);
    }
    g_currentAnim = "";
    if (g_puffTimerActive)
    {
        llSetTimerEvent(0.0);
        g_puffTimerActive = FALSE;
    }
    // Clear RLV effects
    fxClearHigh();
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
    // Check permission first  -  if not ready, queue and request via hybrid
    if (!g_hasAnimPerm)
    {
        g_pendingStrain   = strain;
        g_pendingQuality  = quality;
        g_pendingItemType = itemType;
        g_startPending    = TRUE;
        requestHybridPermissions(llGetOwner(), "Play Cultivar smoking animations");
        return;
    }

    stopCurrentAnim();

    g_currentStrain   = strain;
    g_currentQuality  = quality;
    g_currentItemType = itemType;
    g_currentAnim     = resolveAnim(buildAnimName(itemType, quality));

    if (llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
    {
        llStartAnimation(g_currentAnim);
    }
    else
    {
        // Fallback to basic joint animation if specific one not found
        g_currentAnim = resolveAnim("smoke_joint_reggie_idle");
        if (llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
            llStartAnimation(g_currentAnim);
        else
            llOwnerSay("[Animation] Missing animation: " + g_currentAnim);
    }

    // Start puff timer
    llSetTimerEvent(PUFF_INTERVAL);
    g_puffTimerActive = TRUE;

    // RLV high effects (no-op if disabled or non-RLV viewer)
    fxStartHigh(quality);
}

// ----------------------------------------------------------------
// Play the short puff animation over the idle.
// Returns immediately; the timer resumes idle after 2.5 s.
// ----------------------------------------------------------------
playPuffAnim()
{
    if (!g_hasAnimPerm) return;
    string animName = resolveAnim("smoke_puff");
    if (llGetInventoryType(animName) != INVENTORY_ANIMATION) return;

    // If a pass is still playing, let it finish first
    if (g_passInProgress) return;

    llStopAnimation(g_currentAnim);
    llStartAnimation(animName);
    g_puffAnimName   = animName;
    g_puffInProgress = TRUE;
    llSetTimerEvent(2.5);
}

// ----------------------------------------------------------------
// Play a pass animation (give or receive, one-shot).
// Returns immediately; the timer resumes idle after 2.0 s.
// ----------------------------------------------------------------
playPassAnim(string direction)
{
    if (!g_hasAnimPerm) return;
    string animName = resolveAnim("pass_" + direction);
    if (llGetInventoryType(animName) != INVENTORY_ANIMATION) return;

    // Cancel any in-progress puff cleanly before starting pass
    if (g_puffInProgress)
    {
        llStopAnimation(g_puffAnimName);
        g_puffAnimName   = "";
        g_puffInProgress = FALSE;
    }

    if (g_currentAnim != "") llStopAnimation(g_currentAnim);
    llStartAnimation(animName);
    g_passAnimName   = animName;
    g_passInProgress = TRUE;
    llSetTimerEvent(2.0);
}

// ----------------------------------------------------------------
// Permission ready/failed callbacks (script-specific)
// ----------------------------------------------------------------
onPermissionsReady()
{
    g_hasAnimPerm = TRUE;
    // If a smoke-anim start was queued before perms landed, replay it
    if (g_startPending)
    {
        g_startPending = FALSE;
        startSmokeAnim(g_pendingStrain, g_pendingQuality, g_pendingItemType);
    }
}

onPermissionsFailed(string reasonText)
{
    g_hasAnimPerm = FALSE;
    g_startPending = FALSE;
    llOwnerSay("[Animation] Permission failed: " + reasonText +
               " — smoking animations disabled.");
}

// ================================================================
default
{
    state_entry()
    {
        g_genderSuffix = getGenderSuffix();
        g_hasAnimPerm  = FALSE;
        g_classicMask  = PERMISSION_TRIGGER_ANIMATION;
        requestHybridPermissions(llGetOwner(), "Play Cultivar smoking animations");
    }

    on_rez(integer start_param)
    {
        g_genderSuffix = getGenderSuffix();
        g_hasAnimPerm  = FALSE;
        g_classicMask  = PERMISSION_TRIGGER_ANIMATION;
        stopCurrentAnim();
        requestHybridPermissions(llGetOwner(), "Play Cultivar smoking animations");
    }

    experience_permissions(key agent)
    {
        g_permMode = PERM_XP;
        if (llGetPermissions() & PERMISSION_TRIGGER_ANIMATION)
            onPermissionsReady();
        else
        {
            llOwnerSay("Experience didn't grant animation perm, using standard prompt.");
            llRequestPermissions(agent, g_classicMask);
        }
    }

    experience_permissions_denied(key agent, integer reason)
    {
        llOwnerSay("Experience not available here (" +
                   llGetExperienceErrorMessage(reason) +
                   "). Using standard permission prompt.");
        llRequestPermissions(agent, g_classicMask);
    }

    run_time_permissions(integer perm)
    {
        if ((perm & g_classicMask) == g_classicMask)
        {
            g_permMode = PERM_CLASSIC;
            onPermissionsReady();
        }
        else
        {
            onPermissionsFailed("classic permissions denied");
        }
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
        // ── End of puff overlay: stop puff, resume idle ──────────
        if (g_puffInProgress)
        {
            g_puffInProgress = FALSE;
            if (g_hasAnimPerm) llStopAnimation(g_puffAnimName);
            g_puffAnimName = "";
            if (g_hasAnimPerm && g_currentAnim != "" &&
                llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
            {
                llStartAnimation(g_currentAnim);
            }
            // Restore the puff-interval countdown
            if (g_puffTimerActive)
                llSetTimerEvent(PUFF_INTERVAL);
            return;
        }

        // ── End of pass animation: stop pass, resume idle ────────
        if (g_passInProgress)
        {
            g_passInProgress = FALSE;
            if (g_hasAnimPerm && g_passAnimName != "")
                llStopAnimation(g_passAnimName);
            g_passAnimName = "";
            if (g_hasAnimPerm && g_currentAnim != "" &&
                llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
            {
                llStartAnimation(g_currentAnim);
            }
            if (g_puffTimerActive)
                llSetTimerEvent(PUFF_INTERVAL);
            return;
        }

        // ── Periodic puff + idle refresh ─────────────────────────
        // Runs indefinitely until STOP_SMOKE_ANIM. The smokeable object
        // controls smoke duration and will send TC_SMOKE_FINISHED →
        // STOP_SMOKE_ANIM when it's done. Each tick also re-triggers the
        // idle via the puff overlay cycle, so non-looping idle anims
        // stay active for the full smoke.
        if (g_puffTimerActive && g_currentAnim != "")
        {
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
            string animState = "IDLE";
            if (g_currentAnim != "")
                animState = "SMOKING|" + g_currentStrain + "|" + g_currentQuality;
            llMessageLinked(LINK_SET, CHAN_UI, "ANIM_STATE|" + animState, NULL_KEY);
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

        // Live FX toggle from settings menu
        else if (cmd == "FX_START")
        {
            string quality = llList2String(parts, 1);
            if (quality == "") quality = g_currentQuality;
            fxStartHigh(quality);
        }
        else if (cmd == "FX_CLEAR")
        {
            fxClearHigh();
        }
    }
}
