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
// Unix time when the smoke countdown actually started (after lockout).
// Used to compute remaining seconds when the user puts it out.
integer g_smokeStartTime = 0;

// Interaction lockout: block touch dialog for this many seconds after attach
// so the permission banner can display without collision.
float   INTERACT_LOCKOUT = 5.0;

integer DCHAN_PUFF = -130001;

// ================================================================
// Hybrid permission layer  -  try Experience first, fall back to classic
// ================================================================
integer PERM_NONE    = 0;
integer PERM_XP      = 1;
integer PERM_CLASSIC = 2;

integer g_permMode    = 0;       // PERM_NONE / PERM_XP / PERM_CLASSIC
key     g_permAgent   = NULL_KEY;
integer g_classicMask = 0;       // PERMISSION_ATTACH for this script
string  g_permReason  = "";

// Forward declarations conceptually  -  LSL has no real forward decls,
// so onPermissionsReady() and onPermissionsFailed() are defined below
// and called from the event handlers further down.

requestHybridPermissions(key agent, string reason)
{
    g_permAgent  = agent;
    g_permReason = reason;
    g_permMode   = PERM_NONE;
    // Try Experience permissions first  -  silently quiet on XP-enabled
    // parcels, falls through to experience_permissions_denied otherwise.
    llRequestExperiencePermissions(agent, "");
}

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
// Quality-specific smoke particle start color
// ----------------------------------------------------------------
vector qualityColor(string quality)
{
    if (quality == "mids")   return <0.9, 0.85, 0.5>;
    if (quality == "loud")   return <0.6, 0.9,  0.5>;
    if (quality == "exotic") return <0.8, 0.6,  1.0>;
    return <0.75, 0.7, 0.6>;
}

// End color: reggie/mids fade to pale gray (normal dissipation),
// while loud and exotic hold a vivid tint for longer so the high-tier
// smoke actually reads as colorful in the air instead of washing out
// to white within half a second.
vector qualityColorEnd(string quality)
{
    if (quality == "loud")   return <0.55, 0.85, 0.55>; // lingering green
    if (quality == "exotic") return <0.70, 0.55, 0.95>; // lingering purple
    if (quality == "mids")   return <0.90, 0.88, 0.75>; // warm off-white
    return <0.92, 0.92, 0.92>;                          // reggie: plain gray
}

// ----------------------------------------------------------------
// Smoke particle system
//
// Color branches only on quality (joints and blunts of the same
// quality produce the same hue). itemType controls how THICK the
// smoke is  -  blunts are larger props so they get wider end
// scale and more particles per burst to look visually chunkier.
// ----------------------------------------------------------------
startSmokeParticles()
{
    vector startCol = qualityColor(g_quality);
    vector endCol   = qualityColorEnd(g_quality);
    llOwnerSay("DEBUG PROP: startSmokeParticles type=" + g_itemType +
               " quality=" + g_quality +
               " start=" + (string)startCol +
               " end=" + (string)endCol);

    // Per-itemType thickness tuning. Blunts get beefier smoke than
    // joints / spliffs so the larger mesh doesn't visually swallow
    // the plume. These are scalar deltas applied to the base values
    // so one particle system still serves every type+quality.
    float  endScaleX    = 0.10;
    float  endScaleY    = 0.10;
    integer burstCount  = 2;
    float  burstRate    = 0.2;

    if (g_itemType == "blunt")
    {
        endScaleX  = 0.18;
        endScaleY  = 0.18;
        burstCount = 3;
        burstRate  = 0.15;
    }
    else if (g_itemType == "spliff")
    {
        endScaleX  = 0.12;
        endScaleY  = 0.12;
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
        PSYS_PART_START_ALPHA,     0.55,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.02, 0.02, 0.0>,
        PSYS_PART_END_SCALE,       <endScaleX, endScaleY, 0.0>,
        PSYS_PART_MAX_AGE,         5.0,
        PSYS_SRC_BURST_RATE,       burstRate,
        PSYS_SRC_BURST_PART_COUNT, burstCount,
        // Bumped from 0.02-0.05 to 0.15-0.3 so particles escape larger
        // meshes (blunts/spliffs) instead of being born inside the prim
        PSYS_SRC_BURST_SPEED_MIN,  0.15,
        PSYS_SRC_BURST_SPEED_MAX,  0.30,
        // Slight upward drift so smoke always rises away from the prim
        PSYS_SRC_ACCEL,            <0.0, 0.0, 0.05>,
        PSYS_SRC_ANGLE_BEGIN,      0.0,
        PSYS_SRC_ANGLE_END,        0.35
    ]);
}

// ----------------------------------------------------------------
// Notify HUD and detach
//
// If savePause is TRUE and there is meaningful time remaining, the
// smokeable reports TC_SMOKE_PAUSED so the HUD can offer Resume
// next time the player picks the same item. Otherwise it reports
// TC_SMOKE_FINISHED (natural expiry / not worth resuming).
// ----------------------------------------------------------------
smokeFinished(integer savePause)
{
    integer remaining = 0;
    if (savePause && g_smokeStartTime > 0)
    {
        integer elapsed = llGetUnixTime() - g_smokeStartTime;
        remaining = g_smokeDuration - elapsed;
        if (remaining < 15) remaining = 0; // not worth resuming
    }
    llOwnerSay("DEBUG PROP: smokeFinished savePause=" + (string)savePause +
               " elapsed=" + (string)(llGetUnixTime() - g_smokeStartTime) +
               " duration=" + (string)g_smokeDuration +
               " remaining=" + (string)remaining +
               " hasDetachPerm=" + (string)g_hasDetachPerm);

    llParticleSystem([]);
    if (g_lisHUD)    { llListenRemove(g_lisHUD);    g_lisHUD    = 0; }
    if (g_lisDialog) { llListenRemove(g_lisDialog); g_lisDialog = 0; }

    if (remaining > 0)
    {
        llSay(g_hudChannel,
            "TC_SMOKE_PAUSED|" + g_itemType + "|" + g_quality +
            "|" + (string)remaining);
    }
    else
    {
        llSay(g_hudChannel, "TC_SMOKE_FINISHED");
    }

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
    smokeFinished(FALSE);
}

// ----------------------------------------------------------------
// Permission ready/failed callbacks (script-specific)
// ----------------------------------------------------------------
onPermissionsReady()
{
    // Either the Experience or classic flow granted PERMISSION_ATTACH.
    if (!g_attached)
    {
        llOwnerSay("DEBUG PROP: permissions ready (mode=" + (string)g_permMode +
                   "), calling llAttachToAvatarTemp");
        llAttachToAvatarTemp(ATTACH_RHAND);
    }
    else
    {
        // Post-attach re-grant  -  we can now detach by script
        llOwnerSay("DEBUG PROP: post-attach permissions ready, detach enabled");
        g_hasDetachPerm = TRUE;
    }
}

onPermissionsFailed(string reasonText)
{
    // CRITICAL: only die if we never attached. After a successful
    // attach, a failed re-request for detach permission must NOT kill
    // the prop  -  that was the cause of smoke vanishing 1-2 seconds
    // after the joint appeared (XP unavailable -> classic prompt for
    // detach -> player dismissed -> llDie -> particles gone).
    // We just lose the ability to script-detach gracefully; the prop
    // can still smoke for its full duration and detach via llDie()
    // at the end of smokeFinished().
    if (!g_attached)
    {
        llOwnerSay("[Smokeable] Permission failed pre-attach: " +
                   reasonText + " — cannot attach.");
        llDie();
        return;
    }
    llOwnerSay("DEBUG PROP: post-attach detach perm failed (" +
               reasonText + ") — keeping smoke alive, will llDie() at end.");
    g_hasDetachPerm = FALSE;
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

        // This script only needs PERMISSION_ATTACH from the avatar
        g_classicMask = PERMISSION_ATTACH;

        llOwnerSay("DEBUG PROP: state_entry " + llGetObjectName() +
                   " owner=" + (string)llGetOwner());
    }

    on_rez(integer start_param)
    {
        // Resume support: HUD_Comms rezzes with start_param = remaining
        // seconds when continuing a previously paused smoke of the same
        // type+quality. 0 means a fresh smoke (use the default duration
        // already computed in state_entry from the object name).
        if (start_param > 0)
        {
            g_smokeDuration = start_param;
            llOwnerSay("DEBUG PROP: resuming paused smoke, remaining=" +
                       (string)start_param + "s");
        }

        // Try Experience permissions first; falls back to classic via the
        // experience_permissions_denied event if Experience isn't available.
        llOwnerSay("DEBUG PROP: on_rez, requesting hybrid permissions");
        requestHybridPermissions(llGetOwner(), "Attach smokeable");

        // Safety timeout — if permissions + attach don't complete in 10s, die
        llSetTimerEvent(10.0);
    }

    experience_permissions(key agent)
    {
        g_permMode = PERM_XP;
        llOwnerSay("DEBUG PROP: Experience permissions granted");
        // Verify we actually got PERMISSION_ATTACH from the Experience
        if (llGetPermissions() & PERMISSION_ATTACH)
            onPermissionsReady();
        else
        {
            // XP granted something but not what we need — fall back to classic
            llOwnerSay("Experience didn't grant attach perm, using standard prompt.");
            llRequestPermissions(agent, g_classicMask);
        }
    }

    experience_permissions_denied(key agent, integer reason)
    {
        // Single subtle owner-say with the readable reason, then fall back
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

            // Re-request permissions after attach for later detach.
            // Ownership context changes after temp-attach, so the pre-attach
            // grant may not carry over for llDetachFromAvatar(). Re-runs the
            // hybrid flow (XP first, classic fallback).
            requestHybridPermissions(attachedTo, "Detach smokeable");

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
        llOwnerSay("DEBUG PROP: timer fired attached=" + (string)g_attached +
                   " canInteract=" + (string)g_canInteract +
                   " smokeStartTime=" + (string)g_smokeStartTime);
        if (!g_attached)
        {
            llOwnerSay("DEBUG PROP: timed out waiting for attach, dying");
            llDie();
            return;
        }

        if (!g_canInteract)
        {
            // Lockout period ended — enable touch dialog, start smoke countdown
            g_canInteract    = TRUE;
            g_smokeStartTime = llGetUnixTime();
            llOwnerSay("DEBUG PROP: lockout ended, starting smoke duration timer " +
                       (string)g_smokeDuration + "s");
            llSetTimerEvent((float)g_smokeDuration);
            return;
        }

        // Smoke duration expired naturally — do not save a pause entry
        llOwnerSay("DEBUG PROP: smoke duration expired naturally");
        smokeFinished(FALSE);
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel == g_hudChannel && msg == "TC_END_SMOKE")
        {
            // HUD-side "Put It Out" — save remaining for resume
            smokeFinished(TRUE);
            return;
        }

        if (channel == DCHAN_PUFF)
        {
            if (g_lisDialog) { llListenRemove(g_lisDialog); g_lisDialog = 0; }
            if (msg == "Put It Out")
            {
                // In-world "Put It Out" — save remaining for resume
                smokeFinished(TRUE);
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
