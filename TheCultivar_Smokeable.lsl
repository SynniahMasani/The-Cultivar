// ================================================================
// THE CULTIVAR  -  Smokeable Object Script
// Version: 2.2
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
// No jar-protocol logic (TC_ATTACH_TO) — the HUD_Comms script
// rezzes this object and it self-attaches. HUD_Comms handles
// TC_SMOKE_ATTACH_READY and TC_SMOKE_FINISHED on the private channel.
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

// Interaction lockout: block touch dialog for this many seconds after attach
// so the permission banner can display without collision.
float   INTERACT_LOCKOUT = 5.0;

integer DCHAN_PUFF = -130001;

// ----------------------------------------------------------------
// Derive the same private channel the HUD uses
// ----------------------------------------------------------------
integer deriveHUDChannel(key ownerID)
{
    string h = llGetSubString((string)ownerID, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

// ----------------------------------------------------------------
// Parse type and quality from object name
// TC_Smoke_Joint_Loud  -> ["joint", "loud"]
// TC_Smoke_Blunt_Exotic -> ["blunt", "exotic"]
// ----------------------------------------------------------------
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

// ----------------------------------------------------------------
// Duration table — seconds per type+quality
//   joint:  reggie=300  mids=360  loud=480  exotic=600
//   blunt:  reggie=480  mids=600  loud=720  exotic=900
//   spliff: reggie=240  mids=300  loud=360  exotic=480
//   edible: reggie=600  mids=720  loud=900  exotic=1200
// ----------------------------------------------------------------
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

// ----------------------------------------------------------------
// Quality-specific smoke particle color
// ----------------------------------------------------------------
vector qualityColor(string quality)
{
    if (quality == "mids")   return <0.9, 0.85, 0.5>;
    if (quality == "loud")   return <0.6, 0.9,  0.5>;
    if (quality == "exotic") return <0.8, 0.6,  1.0>;
    return <0.75, 0.7, 0.6>;
}

// ----------------------------------------------------------------
// Smoke particle system
// ----------------------------------------------------------------
startSmokeParticles()
{
    vector col = qualityColor(g_quality);
    llParticleSystem([
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_WIND_MASK |
            PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,     col,
        PSYS_PART_END_COLOR,       <0.95, 0.95, 0.95>,
        PSYS_PART_START_ALPHA,     0.55,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.02, 0.02, 0.0>,
        PSYS_PART_END_SCALE,       <0.08, 0.08, 0.0>,
        PSYS_PART_MAX_AGE,         5.0,
        PSYS_SRC_BURST_RATE,       0.2,
        PSYS_SRC_BURST_PART_COUNT, 2,
        PSYS_SRC_BURST_SPEED_MIN,  0.02,
        PSYS_SRC_BURST_SPEED_MAX,  0.05,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        0.15
    ]);
}

// ----------------------------------------------------------------
// Notify HUD and detach
// ----------------------------------------------------------------
smokeFinished()
{
    llParticleSystem([]);
    if (g_lisHUD)    { llListenRemove(g_lisHUD);    g_lisHUD    = 0; }
    if (g_lisDialog) { llListenRemove(g_lisDialog); g_lisDialog = 0; }
    llSay(g_hudChannel, "TC_SMOKE_FINISHED");
    if (g_hasDetachPerm)
        llDetachFromAvatar();
    else
        llDie();
}

// ----------------------------------------------------------------
// Give a copy to target and detach from current wearer
// ----------------------------------------------------------------
passSmokeable(key target)
{
    llGiveInventory(target, llGetObjectName());
    smokeFinished();
}

// ================================================================
default
{
    state_entry()
    {
        // Guard: only run inside a properly named smokeable object
        if (llSubStringIndex(llGetObjectName(), "TC_Smoke_") != 0)
        {
            llSetScriptState(llGetScriptName(), FALSE);
            return;
        }

        // Parse type+quality from object name
        list parsed     = parseItemName(llGetObjectName());
        g_itemType      = llList2String(parsed, 0);
        g_quality       = llList2String(parsed, 1);
        g_smokeDuration = getSmokeDuration(g_itemType, g_quality);

        // Derive owner's HUD channel
        g_hudChannel = deriveHUDChannel(llGetOwner());

        llOwnerSay("DEBUG PROP: state_entry " + llGetObjectName() +
                   " owner=" + (string)llGetOwner());
    }

    on_rez(integer start_param)
    {
        // Request PERMISSION_ATTACH from owner before attempting temp-attach.
        // llAttachToAvatarTemp requires this permission to be granted first.
        llOwnerSay("DEBUG PROP: on_rez, requesting PERMISSION_ATTACH");
        llRequestPermissions(llGetOwner(), PERMISSION_ATTACH);

        // Safety timeout — if permissions + attach don't complete in 10s, die
        llSetTimerEvent(10.0);
    }

    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_ATTACH)
        {
            if (!g_attached)
            {
                // Pre-attach permission granted — now temp-attach to right hand
                llOwnerSay("DEBUG PROP: PERMISSION_ATTACH granted, calling llAttachToAvatarTemp");
                llAttachToAvatarTemp(ATTACH_RHAND);
            }
            else
            {
                // Post-attach permission re-grant — we can now detach by script
                llOwnerSay("DEBUG PROP: post-attach PERMISSION_ATTACH granted");
                g_hasDetachPerm = TRUE;
            }
        }
        else
        {
            llOwnerSay("DEBUG PROP: PERMISSION_ATTACH denied, dying");
            llDie();
        }
    }

    attach(key attachedTo)
    {
        llOwnerSay("DEBUG PROP: attach event, attachedTo=" + (string)attachedTo);

        if (attachedTo == NULL_KEY)
        {
            llParticleSystem([]);
            llDie();
        }
        else
        {
            // Snap to right hand — final tuned offsets from in-world adjustment
            llSetLocalRot(llEuler2Rot(<90.0, 274.0, 270.0> * DEG_TO_RAD));
            llSetPos(<0.04991, -0.0339, 0.01178>);

            // Re-request PERMISSION_ATTACH after attach for later detach.
            // Ownership context changes after temp-attach, so the pre-attach
            // grant may not carry over for llDetachFromAvatar().
            llRequestPermissions(attachedTo, PERMISSION_ATTACH);

            if (!g_attached)
            {
                g_attached = TRUE;

                llOwnerSay("DEBUG PROP: sending TC_SMOKE_ATTACH_READY on chan " +
                           (string)g_hudChannel);
                llSay(g_hudChannel,
                    "TC_SMOKE_ATTACH_READY|" + g_itemType + "|" + g_quality);

                startSmokeParticles();
                llPlaySound("smoke_inhale", 0.4);

                // Listen on HUD channel for early-end signal
                g_lisHUD = llListen(g_hudChannel, "", NULL_KEY, "TC_END_SMOKE");

                // Interaction lockout — block touch dialog for N seconds so
                // the permission banner doesn't collide with smoke dialog.
                g_canInteract = FALSE;
                llSetTimerEvent(INTERACT_LOCKOUT);
            }
        }
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);
        if (toucher != llGetOwner()) return;
        if (!g_canInteract) return; // lockout while permission banner is up
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
            llOwnerSay("DEBUG PROP: timed out waiting for attach, dying");
            llDie();
            return;
        }

        if (!g_canInteract)
        {
            // Lockout period ended — enable touch dialog, start smoke countdown
            g_canInteract = TRUE;
            llSetTimerEvent((float)g_smokeDuration);
            return;
        }

        // Smoke duration expired naturally
        smokeFinished();
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel == g_hudChannel && msg == "TC_END_SMOKE")
        {
            smokeFinished();
            return;
        }

        if (channel == DCHAN_PUFF)
        {
            if (g_lisDialog) { llListenRemove(g_lisDialog); g_lisDialog = 0; }
            if (msg == "Put It Out")
            {
                smokeFinished();
            }
            else if (msg == "Take a Puff")
            {
                llOwnerSay("You take a deep puff of that " +
                           g_quality + " " + g_itemType + ". Stay elevated.");
                llPlaySound("smoke_inhale", 0.3);
            }
        }
    }
}
