// ================================================================
// THE CULTIVAR  -  Smokeable Object Script
// Version: 2.1
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
//   3. After a short delay, temp-attaches to ATTACH_RHAND
//   4. Sends TC_SMOKE_ATTACH_READY to HUD after attaching
//   5. Runs smoke particles and a touch dialog
//   6. Auto-detaches and notifies HUD (TC_SMOKE_FINISHED) when done
//
// No jar-protocol logic (TC_ATTACH_TO) — the HUD_Comms script
// rezzes this object and it self-attaches. HUD_Comms handles
// TC_SMOKE_ATTACH_READY and TC_SMOKE_FINISHED on the private channel.
// ================================================================

string  g_itemType      = "joint";
string  g_quality       = "reggie";
integer g_smokeDuration = 300;
integer g_attached      = FALSE;
integer g_attachRetries = 0;
integer g_hasAttachPerm = FALSE;
integer g_hudChannel    = 0;
integer g_lisHUD        = 0;
integer g_lisDialog     = 0;

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
    // Strip "TC_Smoke_" prefix (9 chars)
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
    // joint (default)
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
    return <0.75, 0.7, 0.6>; // reggie — pale grey-tan
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
    if (g_hasAttachPerm)
        llDetachFromAvatar(); // llDie() fires in attach(NULL_KEY)
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
                   " owner=" + (string)llGetOwner() +
                   " hudChan=" + (string)g_hudChannel);
    }

    on_rez(integer start_param)
    {
        // Object has been rezzed in-world — start polling for agent context
        g_attachRetries = 0;
        llOwnerSay("DEBUG PROP: on_rez fired, polling for agent context");
        llSetTimerEvent(0.25);
    }

    attach(key attachedTo)
    {
        llOwnerSay("DEBUG PROP: attach event attachedTo=" + (string)attachedTo);

        if (attachedTo == NULL_KEY)
        {
            // Detached — clean up and die
            llParticleSystem([]);
            llDie();
        }
        else
        {
            // Snap to right hand — orient mesh along hand's forward axis
            llSetLocalRot(llEuler2Rot(<0.0, 90.0, 0.0> * DEG_TO_RAD));
            llSetPos(<0.02, 0.0, 0.0>);

            // Request PERMISSION_ATTACH so llDetachFromAvatar() works later
            llRequestPermissions(attachedTo, PERMISSION_ATTACH);

            if (!g_attached)
            {
                g_attached = TRUE;
                llSetTimerEvent(0.0);

                // Announce to HUD: we are on the avatar and ready
                llOwnerSay("DEBUG PROP: sending TC_SMOKE_ATTACH_READY on chan " +
                           (string)g_hudChannel);
                llSay(g_hudChannel,
                    "TC_SMOKE_ATTACH_READY|" + g_itemType + "|" + g_quality);

                startSmokeParticles();
                llPlaySound("smoke_inhale", 0.4);

                // Listen on HUD channel for early-end signal
                g_lisHUD = llListen(g_hudChannel, "", NULL_KEY, "TC_END_SMOKE");

                // Start smoke duration countdown
                llSetTimerEvent((float)g_smokeDuration);
            }
        }
    }

    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_ATTACH)
            g_hasAttachPerm = TRUE;
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);
        if (toucher != llGetOwner()) return;
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
        if (g_attached)
        {
            // Smoke duration expired naturally
            smokeFinished();
            return;
        }

        // Not yet attached — poll for agent context then attempt attach
        key owner = llGetOwner();

        if (llGetAgentSize(owner) != ZERO_VECTOR)
        {
            // Owner recognized as in-world agent — attach now
            llOwnerSay("DEBUG PROP: agent confirmed (retry " +
                       (string)g_attachRetries + "), attaching");
            llAttachToAvatarTemp(ATTACH_RHAND);
            // Give attach() 5 seconds to fire, then give up
            llSetTimerEvent(5.0);
            // Use high retry count to mark that we've attempted
            g_attachRetries = 100;
        }
        else if (g_attachRetries >= 100)
        {
            // Already attempted attach, but attach() never fired
            llOwnerSay("DEBUG PROP: attach never completed, dying");
            llDie();
        }
        else
        {
            g_attachRetries += 1;
            llOwnerSay("DEBUG PROP: waiting for agent context (attempt " +
                       (string)g_attachRetries + ")");
            if (g_attachRetries > 20)
            {
                // 20 * 0.25s = 5 seconds — agent never appeared, give up
                llOwnerSay("DEBUG PROP: owner never became agent, dying");
                llDie();
            }
            // Keep polling at 0.25s
        }
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
