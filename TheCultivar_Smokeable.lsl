// ================================================================
// THE CULTIVAR  -  Smokeable Object Script
// Version: 1.1
// Lives inside: TC_Smoke_Joint_Reggie, TC_Smoke_Joint_Mids,
//               TC_Smoke_Joint_Loud, TC_Smoke_Joint_Exotic,
//               TC_Smoke_Blunt_Reggie, etc.
//
// This script handles the object that gets temp-attached to the
// player's right hand. It:
//   - Listens for the attach instruction on start_param channel
//   - Attaches itself to the smoker's right hand
//   - Runs a smoke particle effect and sound
//   - Auto-detaches after ATTACH_DURATION seconds
//   - Self-destructs cleanly
//
// The object should have these permissions set:
//   - Copy : YES (needed for the jar to give it out)
//   - Transfer : YES
//   - Modify : NO (protect your mesh/textures)
//
// PARTICLE SYSTEM:
//   Subtle, quality-aware smoke that reacts to avatar movement
//   by using PSYS_SRC_PATTERN_ANGLE to emit forward from the tip
// ================================================================

integer g_listenChan  = 0;
integer g_listenAttach;
key     g_targetAvatar = NULL_KEY;
integer g_attachDuration = 120;
string  g_itemType = "joint";
integer g_smokeDuration = 300;
string  g_strain  = "";
string  g_quality = "reggie";
integer g_attached = FALSE;
integer g_hasAttachPerm = FALSE;

// ----------------------------------------------------------------
// Quality-specific smoke particle color
// ----------------------------------------------------------------
vector qualityColor(string quality)
{
    if (quality == "mids")   return <0.9, 0.85, 0.5>;
    if (quality == "loud")   return <0.6, 0.9,  0.5>;
    if (quality == "exotic") return <0.8, 0.6,  1.0>;
    return <0.75, 0.7, 0.6>; // reggie  -  pale grey-tan
}

// ----------------------------------------------------------------
// Smoke particle system  -  tip of the joint/blunt
// ----------------------------------------------------------------
startSmokeParticles()
{
    vector col = qualityColor(g_quality);
    llParticleSystem([
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_WIND_MASK |           // reacts to virtual wind
            PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,       PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_START_COLOR,  col,
        PSYS_PART_END_COLOR,    <0.95, 0.95, 0.95>,
        PSYS_PART_START_ALPHA,  0.55,
        PSYS_PART_END_ALPHA,    0.0,
        PSYS_PART_START_SCALE,  <0.02, 0.02, 0.0>,
        PSYS_PART_END_SCALE,    <0.08, 0.08, 0.0>,
        PSYS_PART_MAX_AGE,      5.0,
        PSYS_SRC_BURST_RATE,    0.2,
        PSYS_SRC_BURST_PART_COUNT, 2,
        PSYS_SRC_BURST_SPEED_MIN,  0.02,
        PSYS_SRC_BURST_SPEED_MAX,  0.05,
        PSYS_SRC_ANGLE_BEGIN,   0.0,
        PSYS_SRC_ANGLE_END,     0.15     // tight cone from tip
    ]);
}

// ----------------------------------------------------------------
// Attempt temp-attach to target avatar's right hand
// ----------------------------------------------------------------
attachToHand()
{
    // llAttachToAvatarTemp requires the script to be owned by the target
    // This only works after the object is transferred to them
    // The rez-then-attach flow: jar rezzes near avatar, object
    // changes owner on rez (if jar owner == object owner and
    // avatar is within range), then attaches.
    //
    // Practical approach in SL: use llAttachToAvatarTemp() which
    // attaches without needing to go through inventory.
    // This requires the avatar to have "Allow Scripts to Attach"
    // enabled (on by default in most regions).
    //
    // The object must be owned by the attaching avatar for this to work.
    // Since the jar is owned by the avatar and rezzes the object,
    // the rezzed object is owned by the jar owner (= the avatar).

    // Notify now so the player gets immediate feedback;
    // position/particles/timer are started inside the attach() event
    // once SL confirms the object has actually landed on the hand.
    llRegionSayTo(g_targetAvatar, 0,
        "Lit. " + g_itemType + " will last " +
        (string)(g_smokeDuration / 60) + " minutes.");

    llAttachToAvatarTemp(ATTACH_RHAND); // right hand attachment point
    // g_attached, particles, and timer are set in the attach() event
    // to guarantee the object is on the hand before effects start.
}

// ================================================================
default
{
    state_entry()
    {
        // Guard: only run inside a properly named smokeable object
        // (TC_Smoke_Joint_*, TC_Smoke_Blunt_*, etc.).  If this script
        // is accidentally present in the session object or any other
        // non-smokeable prop it must NOT fire the attach logic — that
        // would attempt to temp-attach the wrong object to the avatar's
        // hand, causing it to "pop up" at unexpected world positions.
        if (llSubStringIndex(llGetObjectName(), "TC_Smoke_") != 0)
        {
            llSetScriptState(llGetScriptName(), FALSE);
            return;
        }

        // Object was just rezzed  -  listen on start_param channel
        // for attach instructions from the jar's attach script
        g_listenChan  = llGetStartParameter();
        if (g_listenChan < 0)
        {
            // Negative: listen channel from the jar's attach script
            g_listenAttach = llListen(g_listenChan, "", NULL_KEY, "");
            // Confirm we're listening
            llRegionSay(g_listenChan, "TC_ATTACH_CONFIRMED");
            // Safety timeout  -  die if no instructions arrive
            llSetTimerEvent(10.0);
        }
        else
        {
            // Zero = manual test rez; positive = smoke duration passed by HUD
            if (g_listenChan > 0)
            {
                g_smokeDuration = g_listenChan;
                if (g_listenChan >= 600)     g_itemType = "blunt";
                else if (g_listenChan >= 420) g_itemType = "spliff";
                else                          g_itemType = "joint";
            }
            g_targetAvatar = llGetOwner();
            attachToHand();
        }
    }

    attach(key attachedTo)
    {
        if (attachedTo == NULL_KEY)
        {
            // Detached  -  clean up and die
            llParticleSystem([]);
            llDie();
        }
        else
        {
            // Snap to the attachment point so the object doesn't appear
            // at the world-space offset it had when rezzed.
            // <0, 90, 0> degrees orients most joint/blunt meshes naturally
            // along the hand's forward axis; adjust if your mesh needs it.
            llSetLocalRot(llEuler2Rot(<0.0, 90.0, 0.0> * DEG_TO_RAD));
            llSetPos(ZERO_VECTOR);

            // Request PERMISSION_ATTACH so llDetachFromAvatar() works later
            llRequestPermissions(attachedTo, PERMISSION_ATTACH);

            // Just attached  -  start particles
            if (!g_attached)
            {
                g_attached = TRUE;
                startSmokeParticles();
                llPlaySound("smoke_inhale", 0.4);
                llSetTimerEvent((float)g_smokeDuration);
            }
        }
    }

    run_time_permissions(integer perm)
    {
        if (perm & PERMISSION_ATTACH)
            g_hasAttachPerm = TRUE;
    }

    timer()
    {
        if (!g_attached)
        {
            // Setup timeout  -  no attach instructions received
            llListenRemove(g_listenAttach);
            llDie();
        }
        else
        {
            // Attach duration expired  -  time to go
            llParticleSystem([]);
            if (g_hasAttachPerm)
                llDetachFromAvatar(); // llDie() is called in attach(NULL_KEY)
            else
                llDie(); // permission not granted, die directly
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel != g_listenChan) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (cmd == "TC_ATTACH_TO")
        {
            // TC_ATTACH_TO|smokerKey|duration|strain|quality|itemType
            g_targetAvatar   = (key)llList2String(parts, 1);
            g_attachDuration = (integer)llList2String(parts, 2);
            g_strain         = llList2String(parts, 3);
            g_quality        = llList2String(parts, 4);
            g_itemType       = llList2String(parts, 5);
            if (g_itemType == "") g_itemType = "joint";

            if (g_itemType == "blunt")
                g_smokeDuration = 600;
            else if (g_itemType == "spliff")
                g_smokeDuration = 420;
            else
                g_smokeDuration = 300;

            llListenRemove(g_listenAttach);
            llSetTimerEvent(0.0);

            // Only the owner of this object can attach it
            // The jar rezzed this so it's owned by the jar owner
            // If the smoker IS the jar owner, attach directly
            if (g_targetAvatar == llGetOwner())
            {
                attachToHand();
            }
            else
            {
                // Smoker is someone else  -  temp-attach across owners isn't
                // possible in LSL. WeedJar_Attach should have caught this
                // case and called giveToInventory() before ever rezzing us,
                // but as a safety fallback we give the object by name.
                llGiveInventory(g_targetAvatar, llGetObjectName());
                llRegionSayTo(g_targetAvatar, 0,
                    "? Smokeable in your inventory  -  wear it to light up!");
                llDie();
            }
        }
    }
}
