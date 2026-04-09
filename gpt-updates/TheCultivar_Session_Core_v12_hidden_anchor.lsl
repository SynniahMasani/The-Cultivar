// ================================================================
// THE CULTIVAR  -  Session Object Core Script
// Version: 1.2
// Handles: Session lifecycle, participant management, invite
//          broadcasts, animation sync, passing around the circle,
//          and clean teardown when the session ends.
//
// 1.2 change:
//   Hidden-anchor mode: suppress all visible hover text so the
//   session object can act as invisible session logic only.
// ================================================================

integer PUBLIC_SESSION_CHAN = -987654321;
integer TC_OBJECT_PING_CHAN = -111222333;

integer SCHAN_CORE    = 3000;
integer SCHAN_EFFECTS = 3100;

integer DCHAN_PASS  = -99001;
integer DCHAN_HOST  = -99002;

integer g_listenPublic;
integer g_listenPrivate;
integer g_listenHost;
integer g_listenPass;

key     g_hostKey       = NULL_KEY;
string  g_hostName      = "";
string  g_brandName     = "";
integer g_hostHUDChan   = 0;
string  g_itemType      = "joint";
string  g_strain        = "";
string  g_quality       = "";
integer g_sessionActive = FALSE;
integer g_startTime     = 0;

list    g_participants;
integer PART_STRIDE = 4;
integer MAX_PARTICIPANTS = 8;

integer g_currentHolder = 0;
integer g_passCount     = 0;

integer g_cypherMode          = FALSE;
integer g_turnTimer           = 15;
integer g_turnTimeRemaining   = 0;
integer g_lastInviteBroadcast = 0;

integer g_sessionChannel;

integer deriveSessionChannel()
{
    string hexSub = llGetSubString((string)llGetKey(), 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}

integer deriveHUDChannel(key avatarID)
{
    string hexSub = llGetSubString((string)avatarID, 0, 6);
    hexSub = llDumpList2String(llParseString2List(hexSub, ["-"], []), "");
    return (integer)("0x" + hexSub) * -1;
}

integer addParticipant(key avatarKey, string avatarName)
{
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

removeParticipant(key avatarKey)
{
    integer i;
    for (i = 0; i < llGetListLength(g_participants); i += PART_STRIDE)
    {
        if (llList2Key(g_participants, i) == avatarKey)
        {
            g_participants = llDeleteSubList(g_participants, i, i + PART_STRIDE - 1);
            integer totalParts = llGetListLength(g_participants) / PART_STRIDE;
            if (totalParts > 0 && g_currentHolder >= totalParts)
                g_currentHolder = 0;
            return;
        }
    }
}

integer participantCount()
{
    return llGetListLength(g_participants) / PART_STRIDE;
}

string participantName(integer idx)
{
    return llList2String(g_participants, idx * PART_STRIDE + 1);
}

key participantKey(integer idx)
{
    return llList2Key(g_participants, idx * PART_STRIDE);
}

integer participantHUDChan(integer idx)
{
    return llList2Integer(g_participants, idx * PART_STRIDE + 2);
}

broadcastToAll(string msg)
{
    integer count = participantCount();
    integer i;
    for (i = 0; i < count; i++)
    {
        llRegionSayTo(participantKey(i), participantHUDChan(i), msg);
    }
}

syncAnimations()
{
    string syncMsg = "TC_SESSION_SYNC|" + g_itemType + "|" + g_strain + "|" + g_quality;
    broadcastToAll(syncMsg);
}

broadcastInvite()
{
    llRegionSay(PUBLIC_SESSION_CHAN,
        "TC_SESSION_INVITE|" + g_hostName + "|" +
        (string)g_hostKey + "|" +
        (string)llGetKey() + "|" + g_strain + "|" + g_quality + "|" +
        (string)g_sessionChannel + "|" + g_brandName);
}

updateHoverText()
{
    llSetText("", ZERO_VECTOR, 0.0);
}

showPassMenu(key requester)
{
    if (g_listenPass) llListenRemove(g_listenPass);
    g_listenPass = llListen(DCHAN_PASS, "", requester, "");

    integer count = participantCount();
    list buttons;
    string menuText = "=== PASS THE " +
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
    if (!g_cypherMode) llSetTimerEvent(30.0);
}

passToNext()
{
    integer count = participantCount();
    if (count < 2) return;

    integer nextIdx = (g_currentHolder + 1) % count;
    g_currentHolder = nextIdx;
    g_passCount++;

    key nextKey = participantKey(nextIdx);
    string nextName = participantName(nextIdx);
    string prevName = participantName((nextIdx - 1 + count) % count);

    if (g_cypherMode) g_turnTimeRemaining = g_turnTimer;

    key prevKey = participantKey((nextIdx - 1 + count) % count);
    llRegionSayTo(prevKey, 0,
        "Slid the " + g_strain + " to " + nextName + ". Smoke that shit G.");

    llRegionSayTo(nextKey, 0,
        prevName + " passed you the " + g_quality + " " + g_strain +
        ". Dont be scared lil nigga. Smoke that shit.");

    llRegionSayTo(nextKey, participantHUDChan(nextIdx),
        "TC_PASS_RECEIVED|" + g_strain + "|" + g_quality);

    if (g_cypherMode)
        llRegionSayTo(nextKey, participantHUDChan(nextIdx),
            "TC_YOUR_TURN|" + (string)g_turnTimeRemaining + "|" + g_strain);

    llRegionSayTo(prevKey, deriveHUDChannel(prevKey),
        "TC_PASS_GIVEN");

    llMessageLinked(LINK_SET, SCHAN_EFFECTS,
        "PASS_EFFECT|" + (string)prevKey + "|" + (string)nextKey, NULL_KEY);

    updateHoverText();
}

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
            g_currentHolder = i;
            g_passCount++;

            if (g_cypherMode) g_turnTimeRemaining = g_turnTimer;

            llRegionSayTo(requester, 0,
                "Slid the " + g_strain + " to " + pName + ". Smoke that shit G.");
            llRegionSayTo(targetKey, 0,
                llGetDisplayName(requester) + " passed you the " +
                g_quality + " " + g_strain + ". Dont be scared lil nigga. Smoke that shit.");

            llRegionSayTo(targetKey, participantHUDChan(i),
                "TC_PASS_RECEIVED|" + g_strain + "|" + g_quality);

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

endSession(string reason)
{
    g_sessionActive = FALSE;
    broadcastToAll("TC_SESSION_END");

    integer count = participantCount();
    integer i;
    for (i = 0; i < count; i++)
    {
        llRegionSayTo(participantKey(i), 0,
            "The session has ended. " + reason);
    }

    llMessageLinked(LINK_SET, SCHAN_EFFECTS, "SESSION_END", NULL_KEY);

    llSleep(1.0);
    llDie();
}

default
{
    state_entry()
    {
        g_sessionChannel = deriveSessionChannel();

        llListen(0, "", NULL_KEY, "");
        g_listenPublic = llListen(PUBLIC_SESSION_CHAN, "", NULL_KEY, "");
        g_listenPrivate = llListen(g_sessionChannel, "", NULL_KEY, "");

        llRegionSay(TC_OBJECT_PING_CHAN,
            "TC_SESSION_REZZED|" + (string)llGetKey() + "|" +
            (string)g_sessionChannel);

        llSetTimerEvent(30.0);
        updateHoverText();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    timer()
    {
        if (!g_sessionActive)
        {
            llDie();
            return;
        }

        if (g_cypherMode)
        {
            g_turnTimeRemaining -= 5;

            integer now = llGetUnixTime();
            if (now - g_lastInviteBroadcast >= 30)
            {
                broadcastInvite();
                g_lastInviteBroadcast = now;
            }

            if (g_turnTimeRemaining <= 0)
            {
                llRegionSayTo(participantKey(g_currentHolder), 0,
                    "? Time's up! Auto-passing the " + g_strain + "...");
                passToNext();
            }
            else
            {
                key holderKey = participantKey(g_currentHolder);
                integer holderChan = participantHUDChan(g_currentHolder);
                llRegionSayTo(holderKey, holderChan,
                    "TC_YOUR_TURN|" + (string)g_turnTimeRemaining + "|" + g_strain);
                updateHoverText();
            }
            llSetTimerEvent(5.0);
        }
        else
        {
            broadcastInvite();
            g_lastInviteBroadcast = llGetUnixTime();
            llSetTimerEvent(30.0);
            updateHoverText();
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        list parts = llParseString2List(msg, ["|"], []);
        string cmd = llList2String(parts, 0);

        if (channel == 0 && cmd == "TC_SESSION_START")
        {
            g_hostKey     = (key)llList2String(parts, 1);
            g_hostHUDChan = (integer)llList2String(parts, 2);
            g_hostName    = llList2String(parts, 3);
            g_itemType    = llList2String(parts, 4);
            g_strain      = llList2String(parts, 5);
            g_quality     = llList2String(parts, 6);
            g_brandName   = llList2String(parts, 7);
            if (g_itemType == "") g_itemType = "joint";
            if (g_brandName == "") g_brandName = g_hostName;

            g_sessionActive = TRUE;
            g_startTime     = llGetUnixTime();

            addParticipant(g_hostKey, g_hostName);
            g_currentHolder = 0;

            llMessageLinked(LINK_SET, SCHAN_EFFECTS,
                "SESSION_START|" + g_quality, NULL_KEY);

            broadcastInvite();
            updateHoverText();

            llRegionSayTo(g_hostKey, g_hostHUDChan,
                "TC_SESSION_SYNC|" + g_itemType + "|" + g_strain + "|" + g_quality);

            llRegionSayTo(g_hostKey, 0,
                "smoke session is in session! - passin the mufuckin " + g_strain);

            llSetTimerEvent(30.0);
        }
        else if (channel == 0 && cmd == "TC_SESSION_JOIN")
        {
            key joinerKey = (key)llList2String(parts, 1);
            string joinerName = llList2String(parts, 3);

            if (!g_sessionActive) return;

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

                llRegionSayTo(joinerKey, joinerHUDChan,
                    "TC_SESSION_SYNC|" + g_itemType + "|" + g_strain + "|" + g_quality);

                llRegionSayTo(joinerKey, joinerHUDChan,
                    "TC_SESSION_JOINED|" + (string)llGetKey() + "|" +
                    (string)g_sessionChannel + "|" + g_hostName + "|" +
                    g_itemType + "|" + g_strain + "|" + g_quality);

                broadcastToAll("TC_SESSION_MEMBER_JOIN|" + joinerName);

                llRegionSayTo(joinerKey, 0,
                    "You joined " + g_hostName + "'s session. " +
                    g_quality + " " + g_strain + " is going around. ?");
                llRegionSayTo(g_hostKey, 0,
                    joinerName + " joined the session. " +
                    (string)participantCount() + " in the circle.");

                if (!g_cypherMode && participantCount() >= 3)
                {
                    g_cypherMode = TRUE;
                    g_turnTimeRemaining = g_turnTimer;
                    g_lastInviteBroadcast = llGetUnixTime();
                    llSetTimerEvent(5.0);
                    broadcastToAll("TC_CYPHER_MODE|1|" + (string)g_turnTimer);
                    llRegionSayTo(g_hostKey, 0,
                        "? Cypher mode activated  -  " +
                        (string)g_turnTimer + "s turns!");
                    key holderKey = participantKey(g_currentHolder);
                    llRegionSayTo(holderKey, participantHUDChan(g_currentHolder),
                        "TC_YOUR_TURN|" + (string)g_turnTimeRemaining + "|" + g_strain);
                }

                updateHoverText();
            }
        }
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
        else if (channel == g_sessionChannel)
        {
            if (cmd == "TC_PASS_REQUEST")
            {
                key requester = (key)llList2String(parts, 1);
                if (participantKey(g_currentHolder) != requester)
                {
                    llRegionSayTo(requester, 0,
                        "It's not your turn to pass. " +
                        participantName(g_currentHolder) + " has it.");
                    return;
                }
                showPassMenu(requester);
            }
            else if (cmd == "TC_SESSION_LEAVE")
            {
                key leaver = (key)llList2String(parts, 1);
                string leaverName = llGetDisplayName(leaver);

                removeParticipant(leaver);
                broadcastToAll("TC_SESSION_MEMBER_LEAVE|" + leaverName);
                llRegionSayTo(leaver, 0, "You left the session.");

                if (leaver == g_hostKey)
                {
                    endSession(g_hostName + " ended the session.");
                    return;
                }

                if (participantCount() <= 1)
                {
                    endSession("Everyone left the circle.");
                    return;
                }

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
        else if (channel == DCHAN_PASS)
        {
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
                passToNamed(msg, id);
            }
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != SCHAN_CORE) return;

        list parts = llParseString2List(msg, ["|"], []);
        string cmd = llList2String(parts, 0);

        if (cmd == "REQUEST_QUALITY")
        {
            llMessageLinked(LINK_SET, SCHAN_EFFECTS,
                "QUALITY|" + g_quality, NULL_KEY);
        }
    }
}
