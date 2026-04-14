// ================================================================
// THE CULTIVAR  -  Session Object Core Script
// Version: 1.4
// Preserves the full original session logic while replacing floating
// object hover text with a HUD overhead relay.
//
// Changes from original:
//   - removes floating object llSetText usage
//   - preserves join distance checks
//   - preserves cypher mode activation/deactivation
//   - preserves REQUEST_QUALITY link_message path
//   - preserves invite / pass / join / leave / end behavior
//   - sends SESSION_OVERHEAD text to participant HUDs instead
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
integer g_listenLocal;

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
integer g_birthTime          = 0;
integer g_activationDeadline = 0;
integer PENDING_TIMEOUT_SEC  = 20;
integer g_lastHostPing       = 0;
integer HOST_PING_TIMEOUT_SEC = 70;

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

cleanupListens()
{
    if (g_listenPublic)  { llListenRemove(g_listenPublic);  g_listenPublic  = 0; }
    if (g_listenPrivate) { llListenRemove(g_listenPrivate); g_listenPrivate = 0; }
    if (g_listenHost)    { llListenRemove(g_listenHost);    g_listenHost    = 0; }
    if (g_listenPass)    { llListenRemove(g_listenPass);    g_listenPass    = 0; }
    if (g_listenLocal)   { llListenRemove(g_listenLocal);   g_listenLocal   = 0; }
}

resetSessionState()
{
    g_hostKey       = NULL_KEY;
    g_hostName      = "";
    g_brandName     = "";
    g_hostHUDChan   = 0;
    g_itemType      = "joint";
    g_strain        = "";
    g_quality       = "";
    g_sessionActive = FALSE;
    g_startTime     = 0;
    g_participants  = [];
    g_currentHolder = 0;
    g_passCount     = 0;
    g_cypherMode    = FALSE;
    g_turnTimeRemaining   = 0;
    g_lastInviteBroadcast = 0;
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
    if (!g_sessionActive) return;
    llRegionSay(PUBLIC_SESSION_CHAN,
        "TC_SESSION_INVITE|" + g_hostName + "|" +
        (string)g_hostKey + "|" +
        (string)llGetKey() + "|" + g_strain + "|" + g_quality + "|" +
        (string)g_sessionChannel + "|" + g_brandName);
}

string sessionText()
{
    string holderName = participantName(g_currentHolder);
    string text = "THE CULTIVAR  -  Session ?\n";
    text += g_quality + " " + g_strain + " " + g_itemType + "\n";
    text += (string)participantCount() + " in the circle\n";
    text += "With: " + holderName;
    if (g_cypherMode) text += "\n? CYPHER  -  " + (string)g_turnTimeRemaining + "s";
    return text;
}

updateHoverText()
{
    string text = "";
    if (g_sessionActive) text = sessionText();
    broadcastToAll("SESSION_OVERHEAD|" + text);
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

hardEndSession(string reason, integer notifyParticipants)
{
    g_sessionActive = FALSE;
    updateHoverText();
    broadcastToAll("TC_SESSION_END");

    if (notifyParticipants)
    {
        integer count = participantCount();
        integer i;
        for (i = 0; i < count; i++)
        {
            llRegionSayTo(participantKey(i), 0,
                "The session has ended. " + reason);
        }
    }

    llMessageLinked(LINK_SET, SCHAN_EFFECTS, "SESSION_END", NULL_KEY);
    llSetTimerEvent(0.0);
    cleanupListens();
    llSleep(0.5);
    llDie();
}

endSession(string reason)
{
    hardEndSession(reason, TRUE);
}

default
{
    state_entry()
    {
        resetSessionState();
        g_birthTime = llGetUnixTime();
        g_activationDeadline = g_birthTime + PENDING_TIMEOUT_SEC;
        g_sessionChannel = deriveSessionChannel();

        g_listenLocal = llListen(0, "", NULL_KEY, "");
        g_listenPublic = llListen(PUBLIC_SESSION_CHAN, "", NULL_KEY, "");
        g_listenPrivate = llListen(g_sessionChannel, "", NULL_KEY, "");

        llRegionSay(TC_OBJECT_PING_CHAN,
            "TC_SESSION_REZZED|" + (string)llGetKey() + "|" +
            (string)g_sessionChannel);

        llSetTimerEvent(5.0);
        llSetText("", ZERO_VECTOR, 0.0);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    timer()
    {
        if (!g_sessionActive)
        {
            if (llGetUnixTime() >= g_activationDeadline)
            {
                llMessageLinked(LINK_SET, SCHAN_EFFECTS, "SESSION_END", NULL_KEY);
                cleanupListens();
                llDie();
            }
            else
                llSetTimerEvent(5.0);
            return;
        }

        if (g_hostKey == NULL_KEY)
        {
            hardEndSession("Host session data became invalid.", FALSE);
            return;
        }

        integer nowActive = llGetUnixTime();
        if (g_lastHostPing > 0 && (nowActive - g_lastHostPing) > HOST_PING_TIMEOUT_SEC)
        {
            hardEndSession("Host HUD heartbeat timed out.", FALSE);
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
            if (g_hostKey == NULL_KEY) { llDie(); return; }

            g_sessionActive = TRUE;
            g_startTime     = llGetUnixTime();
            g_activationDeadline = 0;
            g_lastHostPing = g_startTime;

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
        else if (channel == 0 && cmd == "TC_SESSION_CANCEL")
        {
            // Spark flow was cancelled before activation.
            if (!g_sessionActive)
            {
                llDie();
                return;
            }
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
        else if (channel == 0 && cmd == "TC_SESSION_LEAVE")
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
        else if (channel == 0 && cmd == "TC_SESSION_PING")
        {
            key pinger = (key)llList2String(parts, 1);
            if (g_sessionActive && pinger == g_hostKey)
                g_lastHostPing = llGetUnixTime();
        }
        else if (channel == g_sessionChannel)
        {
            if (cmd == "TC_SESSION_CANCEL")
            {
                llMessageLinked(LINK_SET, SCHAN_EFFECTS, "SESSION_END", NULL_KEY);
                cleanupListens();
                llDie();
                return;
            }
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
