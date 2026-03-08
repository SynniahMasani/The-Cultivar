// ================================================================
// THE CULTIVAR — Session Object Core Script
// Version: 1.0
// Handles: Session lifecycle, participant management, invite
//          broadcasts, animation sync, passing around the circle,
//          and clean teardown when the session ends.
//
// LIFECYCLE:
//   1. HUD UI rezzes this object near the host avatar
//   2. On rez, this script announces itself back to the host HUD
//   3. Host HUD calls TC_SESSION_START with strain/quality info
//   4. Session object broadcasts TC_SESSION_INVITE on public channel
//   5. Nearby HUDs show invite dialogs — players who accept register
//   6. Once 2+ participants are in, animations sync across all HUDs
//   7. Host can pass to the next person (rotation order)
//   8. Session ends when: host ends it, item runs out, or everyone leaves
//   9. TC_SESSION_END is sent to all participant HUDs, object dies
//
// PARTICIPANT DATA (strided list, stride 4):
//   [avatarKey, avatarName, hudChannel, joinTime, ...]
//
// MAX PARTICIPANTS: 8 (LSL dialog button limit)
//
// PASSING LOGIC:
//   The "rotation" is the order participants joined.
//   Current holder is tracked. When they pass, next in rotation gets it.
//   Host can always pass manually by choosing a specific person.
// ================================================================

integer PUBLIC_SESSION_CHAN = -987654321;
integer TC_OBJECT_PING_CHAN = -111222333;

// Internal
integer SCHAN_CORE    = 3000;
integer SCHAN_EFFECTS = 3100;

// Dialog channels
integer DCHAN_PASS  = -99001;
integer DCHAN_HOST  = -99002;

integer g_listenPublic;
integer g_listenPrivate;  // session's own listen for participant messages
integer g_listenHost;
integer g_listenPass;

// Session identity
key     g_hostKey       = NULL_KEY;
string  g_hostName      = "";
string  g_brandName     = "";   // host's brand name for invite display
integer g_hostHUDChan   = 0;
string  g_strain        = "";
string  g_quality       = "";
integer g_sessionActive = FALSE;
integer g_startTime     = 0;

// Participants: [avatarKey, avatarName, hudChannel, joinTime, ...]
list    g_participants;
integer PART_STRIDE = 4;
integer MAX_PARTICIPANTS = 8;

// Passing state
integer g_currentHolder = 0; // index into participants list (stride-divided)
integer g_passCount     = 0; // total passes this session

// Cypher mode — auto-enables when >= 3 participants join
integer g_cypherMode          = FALSE;
integer g_turnTimer           = 15;  // seconds per turn in cypher mode
integer g_turnTimeRemaining   = 0;
integer g_lastInviteBroadcast = 0;   // llGetUnixTime() of last invite send

// Session's own private channel (derived from object key)
integer g_sessionChannel;

// ----------------------------------------------------------------
// Derive a session-specific channel from this object's key
// ----------------------------------------------------------------
integer deriveSessionChannel()
{
    string hexSub = llGetSubString((string)llGetKey(), 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}

// ----------------------------------------------------------------
// Derive HUD channel from avatar UUID (matches HUD_Comms formula)
// ----------------------------------------------------------------
integer deriveHUDChannel(key avatarID)
{
    string hexSub = llGetSubString((string)avatarID, 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}

// ----------------------------------------------------------------
// Add a participant to the session
// Returns TRUE if added, FALSE if already in or session full
// ----------------------------------------------------------------
integer addParticipant(key avatarKey, string avatarName)
{
    // Check if already in
    integer i;
    for (i = 0; i < llGetListLength(g_participants); i += PART_STRIDE)
    {
        if (llList2Key(g_participants, i) == avatarKey) return FALSE;
    }

    if (llGetListLength(g_participants) / PART_STRIDE >= MAX_PARTICIPANTS)
    {
        llRegionSayTo(avatarKey, 0,
            "The session is full right now (" +
            (string)MAX_PARTICIPANTS + " people max). Try again later.");
        return FALSE;
    }

    integer hudChan = deriveHUDChannel(avatarKey);
    g_participants += [avatarKey, avatarName, hudChan, llGetUnixTime()];
    return TRUE;
}

// ----------------------------------------------------------------
// Remove a participant by key
// ----------------------------------------------------------------
removeParticipant(key avatarKey)
{
    integer i;
    for (i = 0; i < llGetListLength(g_participants); i += PART_STRIDE)
    {
        if (llList2Key(g_participants, i) == avatarKey)
        {
            g_participants = llDeleteSubList(g_participants, i, i + PART_STRIDE - 1);
            // Adjust current holder index if needed
            integer totalParts = llGetListLength(g_participants) / PART_STRIDE;
            if (totalParts > 0 && g_currentHolder >= totalParts)
                g_currentHolder = 0;
            return;
        }
    }
}

// ----------------------------------------------------------------
// Get participant count
// ----------------------------------------------------------------
integer participantCount()
{
    return llGetListLength(g_participants) / PART_STRIDE;
}

// ----------------------------------------------------------------
// Get participant name at index
// ----------------------------------------------------------------
string participantName(integer idx)
{
    return llList2String(g_participants, idx * PART_STRIDE + 1);
}

// ----------------------------------------------------------------
// Get participant key at index
// ----------------------------------------------------------------
key participantKey(integer idx)
{
    return llList2Key(g_participants, idx * PART_STRIDE);
}

// ----------------------------------------------------------------
// Get participant HUD channel at index
// ----------------------------------------------------------------
integer participantHUDChan(integer idx)
{
    return llList2Integer(g_participants, idx * PART_STRIDE + 2);
}

// ----------------------------------------------------------------
// Broadcast a message to ALL participant HUDs
// ----------------------------------------------------------------
broadcastToAll(string msg)
{
    integer count = participantCount();
    integer i;
    for (i = 0; i < count; i++)
    {
        llRegionSayTo(participantKey(i), participantHUDChan(i), msg);
    }
}

// ----------------------------------------------------------------
// Sync animations — tell everyone to start their smoke anim
// ----------------------------------------------------------------
syncAnimations()
{
    string syncMsg = "TC_SESSION_SYNC|" + g_strain + "|" + g_quality;
    broadcastToAll(syncMsg);
}

// ----------------------------------------------------------------
// Broadcast session invite to nearby avatars
// Format: TC_SESSION_INVITE|hostName|hostKey|sessionObjectKey|strain|quality|sessionChannel
// hostKey is included so receiving HUDs can do an exact-key self-check
// ----------------------------------------------------------------
broadcastInvite()
{
    llRegionSay(PUBLIC_SESSION_CHAN,
        "TC_SESSION_INVITE|" + g_hostName + "|" +
        (string)g_hostKey + "|" +
        (string)llGetKey() + "|" + g_strain + "|" + g_quality + "|" +
        (string)g_sessionChannel + "|" + g_brandName);
}

// ----------------------------------------------------------------
// Update hover text showing session status
// ----------------------------------------------------------------
updateHoverText()
{
    if (!g_sessionActive)
    {
        llSetText("", ZERO_VECTOR, 0.0);
        return;
    }

    integer count    = participantCount();
    string  holderName = participantName(g_currentHolder);

    string text = "THE CULTIVAR — Session 🌿\n";
    text += g_quality + " " + g_strain + "\n";
    text += (string)count + " in the circle\n";
    text += "With: " + holderName;
    if (g_cypherMode) text += "\n⏱ CYPHER — " + (string)g_turnTimeRemaining + "s";

    llSetText(text, <0.4, 0.9, 0.4>, 1.0);
}

// ----------------------------------------------------------------
// Build the pass menu — list of participants to pass to
// ----------------------------------------------------------------
showPassMenu(key requester)
{
    if (g_listenPass) llListenRemove(g_listenPass);
    g_listenPass = llListen(DCHAN_PASS, "", requester, "");

    integer count = participantCount();
    list    buttons;
    string  menuText = "=== PASS THE " +
                       llToUpper(llGetSubString(g_quality, 0, 0)) +
                       llGetSubString(g_quality, 1, -1) + " " +
                       g_strain + " ===\nPass to:\n\n";

    integer i;
    for (i = 0; i < count; i++)
    {
        if (participantKey(i) != requester)
        {
            string btnName = llGetSubString(participantName(i), 0, 11);
            buttons += [btnName];
            menuText += participantName(i) + "\n";
        }
    }

    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(requester, 0,
            "Nobody else is in the session to pass to.");
        return;
    }

    buttons += ["Next In Rotation", "End Session", "Close"];
    llDialog(requester, menuText, buttons, DCHAN_PASS);
    // In cypher mode, keep the 5s timer running; menu timeout is handled by auto-pass
    if (!g_cypherMode) llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// Pass to the next person in rotation automatically
// ----------------------------------------------------------------
passToNext()
{
    integer count = participantCount();
    if (count < 2) return;

    integer nextIdx = (g_currentHolder + 1) % count;
    g_currentHolder = nextIdx;
    g_passCount++;

    key    nextKey  = participantKey(nextIdx);
    string nextName = participantName(nextIdx);
    string prevName = participantName((nextIdx - 1 + count) % count);

    // Reset cypher turn timer on every pass
    if (g_cypherMode) g_turnTimeRemaining = g_turnTimer;

    // Notify previous holder
    key prevKey = participantKey((nextIdx - 1 + count) % count);
    llRegionSayTo(prevKey, 0,
        "You passed the " + g_strain + " to " + nextName + ".");

    // Notify new holder
    llRegionSayTo(nextKey, 0,
        prevName + " passed you the " + g_quality + " " + g_strain +
        ". Your turn! 🌿");

    // Tell new holder's HUD to play receive animation
    llRegionSayTo(nextKey, participantHUDChan(nextIdx),
        "TC_PASS_RECEIVED|" + g_strain + "|" + g_quality);

    // In cypher mode, send turn countdown to new holder's HUD
    if (g_cypherMode)
        llRegionSayTo(nextKey, participantHUDChan(nextIdx),
            "TC_YOUR_TURN|" + (string)g_turnTimeRemaining + "|" + g_strain);

    // Tell previous holder's HUD to play give animation
    llRegionSayTo(prevKey, deriveHUDChannel(prevKey),
        "TC_PASS_GIVEN");

    // Tell effects script to show a pass particle beam
    llMessageLinked(LINK_SET, SCHAN_EFFECTS,
        "PASS_EFFECT|" + (string)prevKey + "|" + (string)nextKey, NULL_KEY);

    updateHoverText();
    llPlaySound("pass_whoosh", 0.5);
}

// ----------------------------------------------------------------
// Pass to a specific person by name match
// ----------------------------------------------------------------
passToNamed(string targetName, key requester)
{
    integer count = participantCount();
    integer i;
    for (i = 0; i < count; i++)
    {
        string pName = participantName(i);
        if (llGetSubString(pName, 0, 11) == targetName ||
            pName == targetName)
        {
            key targetKey = participantKey(i);
            if (targetKey == requester)
            {
                llRegionSayTo(requester, 0, "You can't pass to yourself.");
                return;
            }
            // Update current holder to target
            g_currentHolder = i;
            g_passCount++;

            // Reset cypher turn timer on every pass
            if (g_cypherMode) g_turnTimeRemaining = g_turnTimer;

            llRegionSayTo(requester, 0,
                "Passed the " + g_strain + " to " + pName + ".");
            llRegionSayTo(targetKey, 0,
                llKey2Name(requester) + " passed you the " +
                g_quality + " " + g_strain + ". 🌿");

            llRegionSayTo(targetKey, participantHUDChan(i),
                "TC_PASS_RECEIVED|" + g_strain + "|" + g_quality);

            // In cypher mode, send turn countdown to new holder's HUD
            if (g_cypherMode)
                llRegionSayTo(targetKey, participantHUDChan(i),
                    "TC_YOUR_TURN|" + (string)g_turnTimeRemaining + "|" + g_strain);

            llRegionSayTo(requester, deriveHUDChannel(requester),
                "TC_PASS_GIVEN");

            llMessageLinked(LINK_SET, SCHAN_EFFECTS,
                "PASS_EFFECT|" + (string)requester + "|" + (string)targetKey,
                NULL_KEY);

            updateHoverText();
            return;
        }
    }
    llRegionSayTo(requester, 0, "Couldn't find " + targetName + " in the session.");
}

// ----------------------------------------------------------------
// End the session cleanly
// ----------------------------------------------------------------
endSession(string reason)
{
    g_sessionActive = FALSE;

    // Notify all participants
    string endMsg = "TC_SESSION_END";
    broadcastToAll(endMsg);

    // Local chat notification
    integer count = participantCount();
    integer i;
    for (i = 0; i < count; i++)
    {
        llRegionSayTo(participantKey(i), 0,
            "The session has ended. " + reason);
    }

    // Stop effects
    llMessageLinked(LINK_SET, SCHAN_EFFECTS, "SESSION_END", NULL_KEY);

    // Die after a short delay
    llSleep(1.0);
    llDie();
}

// ================================================================
default
{
    state_entry()
    {
        g_sessionChannel = deriveSessionChannel();

        // Listen on channel 0 for TC_SESSION_START from host HUD
        llListen(0, "", NULL_KEY, "");
        // Listen on public channel for participant join messages
        g_listenPublic = llListen(PUBLIC_SESSION_CHAN, "", NULL_KEY, "");
        // Listen on session's own channel for participant communication
        g_listenPrivate = llListen(g_sessionChannel, "", NULL_KEY, "");

        // Announce ourselves to the region on the ping channel
        // so the host HUD knows our key and can send TC_SESSION_START
        llRegionSay(TC_OBJECT_PING_CHAN,
            "TC_SESSION_REZZED|" + (string)llGetKey() + "|" +
            (string)g_sessionChannel);

        llSetTimerEvent(30.0); // wait for host HUD to show item picker and respond
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    timer()
    {
        if (!g_sessionActive)
        {
            // Never got TC_SESSION_START — die quietly
            llDie();
            return;
        }

        if (g_cypherMode)
        {
            // 5-second cypher tick
            g_turnTimeRemaining -= 5;

            // Rebroadcast invite every 30s even during cypher mode
            integer now = llGetUnixTime();
            if (now - g_lastInviteBroadcast >= 30)
            {
                broadcastInvite();
                g_lastInviteBroadcast = now;
            }

            if (g_turnTimeRemaining <= 0)
            {
                // Time's up — auto-pass to next in rotation
                llRegionSayTo(participantKey(g_currentHolder), 0,
                    "⏱ Time's up! Auto-passing the " + g_strain + "...");
                passToNext();
                // passToNext() resets g_turnTimeRemaining = g_turnTimer
            }
            else
            {
                // Broadcast countdown to current holder's HUD
                key holderKey  = participantKey(g_currentHolder);
                integer holderChan = participantHUDChan(g_currentHolder);
                llRegionSayTo(holderKey, holderChan,
                    "TC_YOUR_TURN|" + (string)g_turnTimeRemaining + "|" + g_strain);
                updateHoverText();
            }
            llSetTimerEvent(5.0);
        }
        else
        {
            // Standard mode: periodic invite rebroadcast
            broadcastInvite();
            g_lastInviteBroadcast = llGetUnixTime();
            llSetTimerEvent(30.0);
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- Channel 0: Host HUD starting the session ----
        if (channel == 0 && cmd == "TC_SESSION_START")
        {
            // TC_SESSION_START|hostKey|hostHUDChannel|hostName|strain|quality
            g_hostKey     = (key)llList2String(parts, 1);
            g_hostHUDChan = (integer)llList2String(parts, 2);
            g_hostName    = llList2String(parts, 3);
            g_strain      = llList2String(parts, 4);
            g_quality     = llList2String(parts, 5);
            g_brandName   = llList2String(parts, 6);
            if (g_brandName == "") g_brandName = g_hostName;

            g_sessionActive = TRUE;
            g_startTime     = llGetUnixTime();

            // Add host as first participant
            addParticipant(g_hostKey, g_hostName);
            g_currentHolder = 0;

            // Start effects
            llMessageLinked(LINK_SET, SCHAN_EFFECTS,
                "SESSION_START|" + g_quality, NULL_KEY);

            // Begin broadcasting invites to nearby players
            broadcastInvite();
            updateHoverText();

            // Sync host's animation
            llRegionSayTo(g_hostKey, g_hostHUDChan,
                "TC_SESSION_SYNC|" + g_strain + "|" + g_quality);

            llRegionSayTo(g_hostKey, 0,
                "Session live! " + g_quality + " " + g_strain +
                " 🌿 Nearby players have been invited.");

            // Switch to periodic invite timer
            llSetTimerEvent(30.0);
        }

        // ---- Channel 0: Participant HUD sending join request (directed to this object) ----
        // HUD_Comms sends: TC_SESSION_JOIN|avatarKey|hudChannel|avatarName
        // via llRegionSayTo(sessionObjectKey, 0, ...) — already targeted to us
        else if (channel == 0 && cmd == "TC_SESSION_JOIN")
        {
            key    joinerKey  = (key)llList2String(parts, 1);
            // parts[2] is hudChannel — addParticipant derives it internally, skip
            string joinerName = llList2String(parts, 3);

            if (!g_sessionActive) return;

            // Distance check — joiner must be within 20m of the session object
            list posInfo = llGetObjectDetails(joinerKey, [OBJECT_POS]);
            if (llGetListLength(posInfo) > 0)
            {
                vector joinerPos = llList2Vector(posInfo, 0);
                if (llVecDist(joinerPos, llGetPos()) > 20.0)
                {
                    integer rejChan = deriveHUDChannel(joinerKey);
                    llRegionSayTo(joinerKey, rejChan, "TC_JOIN_REJECTED|distance");
                    llRegionSayTo(joinerKey, 0,
                        "You're too far from the session. Move closer and try again.");
                    return;
                }
            }

            if (addParticipant(joinerKey, joinerName))
            {
                integer joinerHUDChan = deriveHUDChannel(joinerKey);

                // Sync their animation
                llRegionSayTo(joinerKey, joinerHUDChan,
                    "TC_SESSION_SYNC|" + g_strain + "|" + g_quality);

                // Send them the session channel so they can communicate
                llRegionSayTo(joinerKey, joinerHUDChan,
                    "TC_SESSION_JOINED|" + (string)llGetKey() + "|" +
                    (string)g_sessionChannel + "|" + g_hostName + "|" +
                    g_strain + "|" + g_quality);

                // Notify everyone else
                broadcastToAll("TC_SESSION_MEMBER_JOIN|" + joinerName);

                // Local notification
                llRegionSayTo(joinerKey, 0,
                    "You joined " + g_hostName + "'s session. " +
                    g_quality + " " + g_strain + " is going around. 🌿");
                llRegionSayTo(g_hostKey, 0,
                    joinerName + " joined the session. " +
                    (string)participantCount() + " in the circle.");

                // Auto-enable cypher mode when 3 or more are in the circle
                if (!g_cypherMode && participantCount() >= 3)
                {
                    g_cypherMode         = TRUE;
                    g_turnTimeRemaining  = g_turnTimer;
                    g_lastInviteBroadcast = llGetUnixTime();
                    llSetTimerEvent(5.0);
                    broadcastToAll("TC_CYPHER_MODE|1|" + (string)g_turnTimer);
                    llRegionSayTo(g_hostKey, 0,
                        "⏱ Cypher mode activated — " +
                        (string)g_turnTimer + "s turns!");
                    // Start the first holder's countdown
                    key holderKey = participantKey(g_currentHolder);
                    llRegionSayTo(holderKey, participantHUDChan(g_currentHolder),
                        "TC_YOUR_TURN|" + (string)g_turnTimeRemaining + "|" + g_strain);
                }

                updateHoverText();
            }
        }

        // ---- Channel 0: Participant requesting a pass ----
        // HUD_UI sends TC_PASS_REQUEST via llRegionSayTo on channel 0
        else if (channel == 0 && cmd == "TC_PASS_REQUEST")
        {
            key requester = (key)llList2String(parts, 1);
            if (!g_sessionActive) return;
            if (participantKey(g_currentHolder) != requester)
            {
                llRegionSayTo(requester, 0,
                    "It's not your turn to pass. " +
                    participantName(g_currentHolder) + " has it.");
                return;
            }
            showPassMenu(requester);
        }

        // ---- Session channel: Messages from participants ----
        else if (channel == g_sessionChannel)
        {
            // Participant wants to pass
            if (cmd == "TC_PASS_REQUEST")
            {
                // TC_PASS_REQUEST|requesterKey
                key requester = (key)llList2String(parts, 1);

                // Only current holder can pass
                if (participantKey(g_currentHolder) != requester)
                {
                    llRegionSayTo(requester, 0,
                        "It's not your turn to pass. " +
                        participantName(g_currentHolder) + " has it.");
                    return;
                }
                showPassMenu(requester);
            }

            // Participant leaving voluntarily
            else if (cmd == "TC_SESSION_LEAVE")
            {
                key leaver = (key)llList2String(parts, 1);
                string leaverName = llKey2Name(leaver);

                removeParticipant(leaver);
                broadcastToAll("TC_SESSION_MEMBER_LEAVE|" + leaverName);
                llRegionSayTo(leaver, 0, "You left the session.");

                // If host left, end the session
                if (leaver == g_hostKey)
                {
                    endSession(g_hostName + " ended the session.");
                    return;
                }

                // If only 1 person left, end it
                if (participantCount() <= 1)
                {
                    endSession("Everyone left the circle.");
                    return;
                }

                // Disable cypher mode if circle drops below 3
                if (g_cypherMode && participantCount() < 3)
                {
                    g_cypherMode = FALSE;
                    llSetTimerEvent(30.0);
                    broadcastToAll("TC_CYPHER_MODE|0|0");
                    llRegionSayTo(g_hostKey, 0,
                        "Cypher mode deactivated (fewer than 3 players).");
                }

                updateHoverText();
                llRegionSayTo(g_hostKey, 0,
                    leaverName + " left the session. " +
                    (string)participantCount() + " remaining.");
            }
        }

        // ---- Pass menu dialog responses ----
        else if (channel == DCHAN_PASS)
        {
            // Resume cypher tick or invite timer based on mode
            if (g_cypherMode) llSetTimerEvent(5.0);
            else llSetTimerEvent(30.0);
            if (g_listenPass) { llListenRemove(g_listenPass); g_listenPass = 0; }

            if (msg == "Close") return;

            if (msg == "Next In Rotation")
            {
                passToNext();
            }
            else if (msg == "End Session")
            {
                if (id == g_hostKey)
                    endSession(g_hostName + " ended the session.");
                else
                    llRegionSayTo(id, 0,
                        "Only " + g_hostName + " can end the session.");
            }
            else
            {
                // Named pass
                passToNamed(msg, id);
            }
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != SCHAN_CORE) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Effects script asking for current quality (for visual setup)
        if (cmd == "REQUEST_QUALITY")
        {
            llMessageLinked(LINK_SET, SCHAN_EFFECTS,
                "QUALITY|" + g_quality, NULL_KEY);
        }
    }
}
