// ================================================================
// THE CULTIVAR  -  HUD Animation Script
// Version: 1.2
// Preserves the full working animation logic while removing debug spam.
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_IDENTITY  = 400;
integer CHAN_ANIMATION = 500;

string  g_currentAnim     = "";
string  g_currentStrain   = "";
string  g_currentQuality  = "";
string  g_currentItemType = "";

float   PUFF_INTERVAL = 12.0;
integer g_puffTimerActive = FALSE;

integer g_puffInProgress = FALSE;
integer g_passInProgress = FALSE;
string  g_passAnimName   = "";
string  g_puffAnimName   = "";

string  g_genderSuffix   = "_female";
integer g_hasAnimPerm = FALSE;

integer g_startPending  = FALSE;
string  g_pendingStrain   = "";
string  g_pendingQuality  = "";
string  g_pendingItemType = "";

integer g_fxActive = FALSE;

integer PERM_NONE    = 0;
integer PERM_XP      = 1;
integer PERM_CLASSIC = 2;

integer g_permMode    = 0;
key     g_permAgent   = NULL_KEY;
integer g_classicMask = 0;
string  g_permReason  = "";

requestHybridPermissions(key agent, string reason)
{
    g_permAgent  = agent;
    g_permReason = reason;
    g_permMode   = PERM_NONE;
    llRequestExperiencePermissions(agent, "");
}

fxStartHigh(string quality)
{
    string fxFlag = llLinksetDataRead("hud_fx_enabled");
    if (fxFlag != "1") return;
    if (g_fxActive) return;

    float blur     = 0.10;
    float distMin  = 5.0;
    float distMax  = 25.0;
    string tintColLegacy = "1.0;0.92;0.80;0.10";
    string tintColRLVa   = "1.0/0.92/0.80";

    if (quality == "mids")
    {
        blur = 0.18;
        tintColLegacy = "1.0;0.90;0.75;0.14";
        tintColRLVa   = "1.0/0.90/0.75";
    }
    else if (quality == "loud")
    {
        blur = 0.28;
        tintColLegacy = "1.0;0.85;0.70;0.18";
        tintColRLVa   = "1.0/0.85/0.70";
        distMax = 30.0;
    }
    else if (quality == "exotic")
    {
        blur = 0.40;
        tintColLegacy = "0.95;0.78;0.95;0.22";
        tintColRLVa   = "0.95/0.78/0.95";
        distMax = 40.0;
    }

    string rlvMode1     = "@setsphere_mode:1=force";
    string rlvMode2     = "@setsphere_mode:2=force";
    string rlvOrigin    = "@setsphere_origin:0=force";
    string rlvDistMin   = "@setsphere_distmin:"  + (string)distMin + "=force";
    string rlvDistMax   = "@setsphere_distmax:"  + (string)distMax + "=force";
    string rlvExtend    = "@setsphere_distextend:1=force";
    string rlvParam     = "@setsphere_param:"    + (string)blur    + "=force";
    string rlvTintRLVa  = "@setsphere_tint:"     + tintColRLVa     + "=force";
    string rlvTintOld   = "@setsphere_tint:"     + tintColLegacy   + "=force";
    string rlvActivate  = "@setsphere=force";

    // Emit both RLVa variants for maximum viewer compatibility.
    llOwnerSay(rlvMode1);
    llOwnerSay(rlvMode2);
    llOwnerSay(rlvOrigin);
    llOwnerSay(rlvDistMin);
    llOwnerSay(rlvDistMax);
    llOwnerSay(rlvExtend);
    llOwnerSay(rlvParam);
    llOwnerSay(rlvTintRLVa);
    llOwnerSay(rlvTintOld);
    llOwnerSay(rlvActivate);

    g_fxActive = TRUE;
}

fxClearHigh()
{
    if (!g_fxActive) return;
    llOwnerSay("@setsphere_mode:0=force");
    llOwnerSay("@setsphere=clear");
    g_fxActive = FALSE;
}

string getGenderSuffix()
{
    list details = llGetObjectDetails(llGetOwner(), [OBJECT_BODY_SHAPE_TYPE]);
    integer bodyType = llList2Integer(details, 0);
    if (bodyType == 1) return "_male";
    return "_female";
}

string resolveAnim(string baseName)
{
    string gendered = baseName + g_genderSuffix;
    if (llGetInventoryType(gendered) == INVENTORY_ANIMATION)
        return gendered;
    return baseName;
}

stopCurrentAnim()
{
    if (g_hasAnimPerm)
    {
        if (g_currentAnim != "") llStopAnimation(g_currentAnim);
        if (g_puffAnimName != "") llStopAnimation(g_puffAnimName);
        if (g_passAnimName != "") llStopAnimation(g_passAnimName);
    }

    g_currentAnim     = "";
    g_currentStrain   = "";
    g_currentQuality  = "";
    g_currentItemType = "";
    g_puffAnimName    = "";
    g_passAnimName    = "";
    g_puffInProgress  = FALSE;
    g_passInProgress  = FALSE;

    if (g_puffTimerActive)
    {
        llSetTimerEvent(0.0);
        g_puffTimerActive = FALSE;
    }

    fxClearHigh();
}

string buildAnimName(string itemType, string quality)
{
    string category = "joint";
    if (itemType == "blunt")      category = "blunt";
    else if (itemType == "pipe")  category = "pipe";
    else if (itemType == "bong")  category = "bong";
    else if (itemType == "joint") category = "joint";
    else if (llSubStringIndex(itemType, "joint") != -1) category = "joint";
    else if (llSubStringIndex(itemType, "blunt") != -1) category = "blunt";

    return "smoke_" + category + "_" + quality + "_idle";
}

startSmokeAnim(string strain, string quality, string itemType)
{
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
        g_currentAnim = resolveAnim("smoke_joint_reggie_idle");
        if (llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
            llStartAnimation(g_currentAnim);
        else
            llOwnerSay("[Animation] Missing animation: " + g_currentAnim);
    }

    llSetTimerEvent(PUFF_INTERVAL);
    g_puffTimerActive = TRUE;
    fxStartHigh(quality);
}

playPuffAnim()
{
    if (!g_hasAnimPerm) return;
    string animName = resolveAnim("smoke_puff");
    if (llGetInventoryType(animName) != INVENTORY_ANIMATION) return;
    if (g_passInProgress) return;

    llStopAnimation(g_currentAnim);
    llStartAnimation(animName);
    g_puffAnimName   = animName;
    g_puffInProgress = TRUE;
    llSetTimerEvent(2.5);
}

playPassAnim(string direction)
{
    if (!g_hasAnimPerm) return;
    string animName = resolveAnim("pass_" + direction);
    if (llGetInventoryType(animName) != INVENTORY_ANIMATION) return;

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

onPermissionsReady()
{
    g_hasAnimPerm = TRUE;
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
    llOwnerSay("[Animation] Permission failed: " + reasonText + " — smoking animations disabled.");
}

default
{
    state_entry()
    {
        g_genderSuffix = getGenderSuffix();
        g_hasAnimPerm  = FALSE;
        g_classicMask  = PERMISSION_TRIGGER_ANIMATION;
        string fxBoot = llLinksetDataRead("hud_fx_enabled");
        if (fxBoot == "")
        {
            llLinksetDataWrite("hud_fx_enabled", "1");
        }
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
            llRequestPermissions(agent, g_classicMask);
    }

    experience_permissions_denied(key agent, integer reason)
    {
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
        if (g_puffInProgress)
        {
            g_puffInProgress = FALSE;
            if (g_hasAnimPerm) llStopAnimation(g_puffAnimName);
            g_puffAnimName = "";
            if (g_hasAnimPerm && g_currentAnim != "" && llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
            {
                llStartAnimation(g_currentAnim);
            }
            if (g_puffTimerActive)
                llSetTimerEvent(PUFF_INTERVAL);
            return;
        }

        if (g_passInProgress)
        {
            g_passInProgress = FALSE;
            if (g_hasAnimPerm && g_passAnimName != "")
                llStopAnimation(g_passAnimName);
            g_passAnimName = "";
            if (g_hasAnimPerm && g_currentAnim != "" && llGetInventoryType(g_currentAnim) == INVENTORY_ANIMATION)
            {
                llStartAnimation(g_currentAnim);
            }
            if (g_puffTimerActive)
                llSetTimerEvent(PUFF_INTERVAL);
            return;
        }

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

        if (cmd == "START_SMOKE_ANIM")
        {
            string strain   = llList2String(parts, 1);
            string quality  = llList2String(parts, 2);
            string itemType = llList2String(parts, 3);
            if (itemType == "") itemType = "joint";
            startSmokeAnim(strain, quality, itemType);
        }
        else if (cmd == "STOP_SMOKE_ANIM")
        {
            stopCurrentAnim();
        }
        else if (cmd == "PLAY_PASS_GIVE")
        {
            playPassAnim("give");
        }
        else if (cmd == "PLAY_PASS_RECEIVE")
        {
            playPassAnim("receive");
        }
        else if (cmd == "REQUEST_ANIM_STATE")
        {
            string animState = "IDLE";
            if (g_currentAnim != "")
                animState = "SMOKING|" + g_currentStrain + "|" + g_currentQuality;
            llMessageLinked(LINK_SET, CHAN_UI, "ANIM_STATE|" + animState, NULL_KEY);
        }
        else if (cmd == "SWITCH_ANIM_QUALITY")
        {
            string newQuality = llList2String(parts, 1);
            if (g_currentAnim != "")
            {
                startSmokeAnim(g_currentStrain, newQuality, g_currentItemType);
            }
        }
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
