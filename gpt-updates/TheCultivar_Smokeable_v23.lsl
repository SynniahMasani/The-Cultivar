// ================================================================
// THE CULTIVAR  -  Smokeable Object Script
// Version: 2.3
// Lives inside: TC_Smoke_Joint_Reggie, TC_Smoke_Joint_Mids,
//               TC_Smoke_Joint_Loud, TC_Smoke_Joint_Exotic,
//               TC_Smoke_Blunt_Reggie, TC_Smoke_Blunt_Mids, etc.
//
// Name format: TC_Smoke_[Type]_[Quality]
//   e.g. TC_Smoke_Joint_Loud, TC_Smoke_Blunt_Exotic
//
// This script:
//   1. Parses type+quality from its own object name on rez
//   2. Derives the owner's HUD private channel
//   3. Requests PERMISSION_ATTACH from owner
//   4. On permission granted, temp-attaches to ATTACH_RHAND
//   5. After attach, re-requests permissions for later detach
//   6. Sends TC_SMOKE_ATTACH_READY to HUD
//   7. Runs smoke particles and a touch dialog
//   8. Auto-detaches and notifies HUD (TC_SMOKE_FINISHED) when done
//
// 2.3 change:
//   - Tier-colored smoke: reggie brown, mids green, loud red,
//     exotic magenta->cyan rainbow blend.
//   - Stronger swirl motion via PSYS_SRC_OMEGA.
//   - Put It Out now always dies after detach attempt so the held
//     blunt/joint cannot remain stuck in hand.
// ================================================================

string  g_itemType      = "joint";
string  g_quality       = "reggie";
integer g_smokeDuration = 300;
integer g_attached      = FALSE;
integer g_canInteract   = FALSE;
integer g_hasDetachPerm = FALSE;
integer g_hudChannel    = 0;
integer g_lisHUD        = 0;
integer g_lisDialog     = 0;
integer g_smokeStartTime = 0;

float   INTERACT_LOCKOUT = 5.0;
integer DCHAN_PUFF = -130001;

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

integer deriveHUDChannel(key ownerID)
{
    string h = llGetSubString((string)ownerID, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

list parseItemName(string objName)
{
    if (llSubStringIndex(objName, "TC_Smoke_") != 0)
        return ["joint", "reggie"];
    string rest = llGetSubString(objName, 9, -1);
    list   parts = llParseString2List(rest, ["_"], []);
    if (llGetListLength(parts) < 2)
        return ["joint", "reggie"];
    return [llToLower(llList2String(parts, 0)),
            llToLower(llList2String(parts, 1))];
}

integer getSmokeDuration(string itemType, string quality)
{
    if (itemType == "blunt")
    {
        if (quality == "mids")   return 600;
        if (quality == "loud")   return 720;
        if (quality == "exotic") return 900;
        return 480;
    }
    if (itemType == "spliff")
    {
        if (quality == "mids")   return 300;
        if (quality == "loud")   return 360;
        if (quality == "exotic") return 480;
        return 240;
    }
    if (itemType == "edible")
    {
        if (quality == "mids")   return 720;
        if (quality == "loud")   return 900;
        if (quality == "exotic") return 1200;
        return 600;
    }
    if (quality == "mids")   return 360;
    if (quality == "loud")   return 480;
    if (quality == "exotic") return 600;
    return 300;
}

vector qualityColor(string quality)
{
    if (quality == "mids")   return <0.25, 0.95, 0.35>;
    if (quality == "loud")   return <0.95, 0.18, 0.12>;
    if (quality == "exotic") return <1.0,  0.15, 0.85>;
    return <0.46, 0.30, 0.14>;
}

vector qualityColorEnd(string quality)
{
    if (quality == "mids")   return <0.10, 0.75, 0.22>;
    if (quality == "loud")   return <0.90, 0.40, 0.10>;
    if (quality == "exotic") return <0.10, 0.85, 1.00>;
    return <0.60, 0.42, 0.22>;
}

startSmokeParticles()
{
    vector startCol = qualityColor(g_quality);
    vector endCol   = qualityColorEnd(g_quality);

    float  startScaleX  = 0.03;
    float  startScaleY  = 0.03;
    float  endScaleX    = 0.12;
    float  endScaleY    = 0.12;
    integer burstCount  = 3;
    float  burstRate    = 0.15;
    float  startAlpha   = 0.65;
    float  maxAge       = 6.0;
    float  speedMin     = 0.15;
    float  speedMax     = 0.30;
    float  accelZ       = 0.05;
    vector srcOmega     = <0.0, 0.0, 1.2>;
    float  angleEnd     = 0.45;

    if (g_itemType == "blunt")
    {
        startScaleX = 0.14;
        startScaleY = 0.14;
        endScaleX   = 0.80;
        endScaleY   = 0.80;
        burstCount  = 16;
        burstRate   = 0.07;
        startAlpha  = 0.96;
        maxAge      = 9.0;
        speedMin    = 0.28;
        speedMax    = 0.55;
        accelZ      = 0.15;
        srcOmega    = <0.0, 0.0, 2.4>;
        angleEnd    = 0.65;
    }
    else if (g_itemType == "spliff")
    {
        endScaleX  = 0.18;
        endScaleY  = 0.18;
        burstCount = 4;
        burstRate  = 0.12;
        srcOmega   = <0.0, 0.0, 1.7>;
        angleEnd   = 0.55;
    }

    if (g_quality == "exotic")
    {
        endScaleX  = endScaleX * 1.20;
        endScaleY  = endScaleY * 1.20;
        burstCount = burstCount + 4;
        srcOmega.z = srcOmega.z + 1.6;
    }
    else if (g_quality == "loud")
    {
        endScaleX  = endScaleX * 1.10;
        endScaleY  = endScaleY * 1.10;
        burstCount = burstCount + 2;
        srcOmega.z = srcOmega.z + 0.8;
    }

    llParticleSystem([
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_WIND_MASK |
            PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     startCol,
        PSYS_PART_END_COLOR,       endCol,
        PSYS_PART_START_ALPHA,     startAlpha,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <startScaleX, startScaleY, 0.0>,
        PSYS_PART_END_SCALE,       <endScaleX, endScaleY, 0.0>,
        PSYS_PART_MAX_AGE,         maxAge,
        PSYS_SRC_BURST_RATE,       burstRate,
        PSYS_SRC_BURST_PART_COUNT, burstCount,
        PSYS_SRC_BURST_SPEED_MIN,  speedMin,
        PSYS_SRC_BURST_SPEED_MAX,  speedMax,
        PSYS_SRC_ACCEL,            <0.0, 0.0, accelZ>,
        PSYS_SRC_OMEGA,            srcOmega,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        angleEnd
    ]);
}

smokeFinished(integer savePause)
{
    integer remaining = 0;
    if (savePause && g_smokeStartTime > 0)
    {
        integer elapsed = llGetUnixTime() - g_smokeStartTime;
        remaining = g_smokeDuration - elapsed;
        if (remaining < 15) remaining = 0;
    }

    llParticleSystem([]);
    if (g_lisHUD)    { llListenRemove(g_lisHUD);    g_lisHUD    = 0; }
    if (g_lisDialog) { llListenRemove(g_lisDialog); g_lisDialog = 0; }

    if (remaining > 0)
        llSay(g_hudChannel, "TC_SMOKE_PAUSED|" + g_itemType + "|" + g_quality + "|" + (string)remaining);
    else
        llSay(g_hudChannel, "TC_SMOKE_FINISHED");

    llSetTimerEvent(0.0);
    if (g_hasDetachPerm)
        llDetachFromAvatar();
    llSleep(0.2);
    llDie();
}

passSmokeable(key target)
{
    llGiveInventory(target, llGetObjectName());
    smokeFinished(FALSE);
}

onPermissionsReady()
{
    if (!g_attached)
        llAttachToAvatarTemp(ATTACH_RHAND);
    else
        g_hasDetachPerm = TRUE;
}

onPermissionsFailed(string reasonText)
{
    if (!g_attached)
    {
        llOwnerSay("[Smokeable] Permission failed pre-attach: " + reasonText + " — cannot attach.");
        llDie();
        return;
    }
    g_hasDetachPerm = FALSE;
}

default
{
    state_entry()
    {
        if (llSubStringIndex(llGetObjectName(), "TC_Smoke_") != 0)
        {
            llSetScriptState(llGetScriptName(), FALSE);
            return;
        }

        list parsed     = parseItemName(llGetObjectName());
        g_itemType      = llList2String(parsed, 0);
        g_quality       = llList2String(parsed, 1);
        g_smokeDuration = getSmokeDuration(g_itemType, g_quality);
        g_hudChannel    = deriveHUDChannel(llGetOwner());
        g_classicMask   = PERMISSION_ATTACH;
    }

    on_rez(integer start_param)
    {
        if (start_param > 0)
            g_smokeDuration = start_param;
        requestHybridPermissions(llGetOwner(), "Attach smokeable");
        llSetTimerEvent(10.0);
    }

    experience_permissions(key agent)
    {
        g_permMode = PERM_XP;
        if (llGetPermissions() & PERMISSION_ATTACH)
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
            onPermissionsFailed("classic permissions denied");
    }

    attach(key attachedTo)
    {
        if (attachedTo == NULL_KEY)
        {
            llParticleSystem([]);
            llDie();
            return;
        }

        llSetLocalRot(llEuler2Rot(<90.0, 274.0, 270.0> * DEG_TO_RAD));
        llSetPos(<0.04991, -0.0339, 0.01178>);

        if (!g_attached)
        {
            g_attached = TRUE;
            llSay(g_hudChannel, "TC_SMOKE_ATTACH_READY|" + g_itemType + "|" + g_quality);
            startSmokeParticles();
            llPlaySound("smoke_inhale", 0.4);
            g_lisHUD = llListen(g_hudChannel, "", NULL_KEY, "TC_END_SMOKE");
            g_canInteract = FALSE;
            llSetTimerEvent(INTERACT_LOCKOUT);
            requestHybridPermissions(attachedTo, "Detach smokeable");
        }
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);
        if (toucher != llGetOwner()) return;
        if (!g_canInteract) return;
        if (g_lisDialog) { llListenRemove(g_lisDialog); g_lisDialog = 0; }
        g_lisDialog = llListen(DCHAN_PUFF, "", toucher, "");
        integer minsLeft = g_smokeDuration / 60;
        llDialog(toucher,
            "=== " + g_itemType + " ===\n" +
            g_quality + " quality\n" +
            "~" + (string)minsLeft + " min remaining",
            ["Take a Puff", "Put It Out"],
            DCHAN_PUFF);
    }

    timer()
    {
        if (!g_attached)
        {
            llDie();
            return;
        }

        if (!g_canInteract)
        {
            g_canInteract    = TRUE;
            g_smokeStartTime = llGetUnixTime();
            llSetTimerEvent((float)g_smokeDuration);
            return;
        }

        smokeFinished(FALSE);
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel == g_hudChannel && msg == "TC_END_SMOKE")
        {
            smokeFinished(TRUE);
            return;
        }

        if (channel == DCHAN_PUFF)
        {
            if (g_lisDialog) { llListenRemove(g_lisDialog); g_lisDialog = 0; }
            if (msg == "Put It Out")
                smokeFinished(TRUE);
            else if (msg == "Take a Puff")
            {
                llOwnerSay("You take a deep puff of that " + g_quality + " " + g_itemType + ". Stay elevated.");
                llPlaySound("smoke_inhale", 0.3);
            }
        }
    }
}
