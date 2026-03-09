// ================================================================
// THE CULTIVAR  -  Strain Drop Machine Script
// Version: 1.0
//
// An in-world terminal that polls a central HTTP server for
// currently active limited strain drops. When a drop is live,
// players can claim one seed pack. The server tracks who claimed
// what and prevents double-claiming.
//
// HTTP FLOW:
//   Every POLL_INTERVAL seconds the machine polls:
//   GET https://[your-server]/drops/current
//   Response: JSON { active: bool, strain: str, quality: str,
//                    remaining: int, endsAt: int (unix timestamp),
//                    dropId: str }
//
//   When a player claims:
//   POST https://[your-server]/drops/claim
//   Body: { dropId: str, avatarKey: str, avatarName: str,
//           region: str, timestamp: int }
//   Response: { success: bool, reason: str }
//
//   On success: machine gives seed from inventory, logs to server
//   On fail: show reason (already claimed, drop over, etc.)
//
// SEED OBJECTS IN MACHINE INVENTORY:
//   One object per strain, named exactly as the strain name.
//   e.g. "Lemon Cherry Gelato", "Purple Punch", etc.
//   Must be Copy/Transfer so the machine can give multiples.
//
// PRIM LINK STRUCTURE:
//   Link 1 (root) : Machine body / terminal
//   Link 2        : Screen prim (color changes by drop status)
//   Link 3        : Strain preview prim (quality color glow)
//   Link 4        : Particle emitter (hype effect when drop is live)
//   Link 5        : Countdown display prim
// ================================================================

string  SERVER_BASE    = "https://your-cultivar-server.com"; // SET THIS
float   POLL_INTERVAL  = 60.0;  // seconds between server polls
integer MAX_CLAIM_WAIT = 15;    // seconds to wait for claim response

// Drop state from last poll
integer g_dropActive   = FALSE;
string  g_dropStrain   = "";
string  g_dropQuality  = "";
integer g_dropRemaining = 0;
integer g_dropEndsAt   = 0;
string  g_dropId       = "";

// HTTP request keys
key     g_pollRequest  = NULL_KEY;
key     g_claimRequest = NULL_KEY;

// Pending claim
key     g_claimingAvatar = NULL_KEY;
string  g_claimingName   = "";

// Dialog
integer DCHAN_CLAIM = -140001;
integer g_listenClaim;

integer g_busy = FALSE;
integer g_celebrateUntil = 0; // unix time after which idle particles should be restored

// ----------------------------------------------------------------
vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0, 0.85, 0.2>;
    if (quality == "loud")   return <0.2, 0.85, 0.3>;
    if (quality == "exotic") return <0.7, 0.3,  1.0>;
    return <0.55, 0.45, 0.3>;
}

// ----------------------------------------------------------------
// Poll server for current drop status
// ----------------------------------------------------------------
pollServer()
{
    if (g_pollRequest != NULL_KEY) return; // already waiting
    g_pollRequest = llHTTPRequest(
        SERVER_BASE + "/drops/current",
        [HTTP_METHOD, "GET",
         HTTP_MIMETYPE, "application/json",
         HTTP_VERIFY_CERT, TRUE],
        "");
}

// ----------------------------------------------------------------
// Send claim request to server
// ----------------------------------------------------------------
sendClaimRequest(key avatarKey, string avatarName)
{
    if (g_claimRequest != NULL_KEY) return;
    g_claimingAvatar = avatarKey;
    g_claimingName   = avatarName;

    string body = "{" +
        "\"dropId\":\""     + g_dropId                            + "\"," +
        "\"avatarKey\":\""  + (string)avatarKey                   + "\"," +
        "\"avatarName\":\"" + avatarName                          + "\"," +
        "\"region\":\""     + llGetRegionName()                   + "\"," +
        "\"timestamp\":"    + (string)llGetUnixTime()             +
    "}";

    g_claimRequest = llHTTPRequest(
        SERVER_BASE + "/drops/claim",
        [HTTP_METHOD, "POST",
         HTTP_MIMETYPE, "application/json",
         HTTP_VERIFY_CERT, TRUE],
        body);

    llSetTimerEvent((float)MAX_CLAIM_WAIT);
}

// ----------------------------------------------------------------
// Parse a JSON value by key (minimal parser for expected responses)
// Returns the string value for "key":"value" or "key":value
// ----------------------------------------------------------------
string jsonGet(string json, string key)
{
    string search = "\"" + key + "\":";
    integer idx = llSubStringIndex(json, search);
    if (idx == -1) return "";

    integer start = idx + llStringLength(search);
    string  rest  = llGetSubString(json, start, -1);

    // Trim leading whitespace
    while (llGetSubString(rest, 0, 0) == " ")
        rest = llGetSubString(rest, 1, -1);

    // Quoted string value
    if (llGetSubString(rest, 0, 0) == "\"")
    {
        rest = llGetSubString(rest, 1, -1);
        integer endQ = llSubStringIndex(rest, "\"");
        if (endQ == -1) return rest;
        return llGetSubString(rest, 0, endQ - 1);
    }

    // Unquoted (bool/int) value  -  read until , or }
    integer endC = llSubStringIndex(rest, ",");
    integer endB = llSubStringIndex(rest, "}");
    integer end  = endC;
    if (endB != -1 && (end == -1 || endB < end)) end = endB;
    if (end == -1) return rest;
    return llGetSubString(rest, 0, end - 1);
}

// ----------------------------------------------------------------
// Update all visuals based on current drop state
// ----------------------------------------------------------------
updateVisuals()
{
    if (g_dropActive)
    {
        vector col = qualColor(g_dropQuality);

        // Screen prim  -  lit up with quality color
        llSetLinkPrimitiveParamsFast(2, [
            PRIM_COLOR, ALL_SIDES, col, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.12
        ]);

        // Strain preview prim
        llSetLinkPrimitiveParamsFast(3, [
            PRIM_COLOR, ALL_SIDES, col, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.18,
            PRIM_TEXT,
                "? DROP LIVE ?\n" +
                g_dropQuality + " " + g_dropStrain + "\n" +
                (string)g_dropRemaining + " remaining",
            col, 1.0
        ]);

        // Countdown prim
        integer secsLeft = g_dropEndsAt - llGetUnixTime();
        string  timeStr;
        if (secsLeft > 3600)
            timeStr = (string)(secsLeft / 3600) + "h " +
                      (string)((secsLeft % 3600) / 60) + "m left";
        else if (secsLeft > 60)
            timeStr = (string)(secsLeft / 60) + "m left";
        else
            timeStr = (string)secsLeft + "s left";

        llSetLinkPrimitiveParamsFast(5, [
            PRIM_TEXT, timeStr, <1.0, 1.0, 0.4>, 1.0
        ]);

        // Hype particles (link 4)
        llLinkParticleSystem(4, [
            PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                       PSYS_PART_INTERP_SCALE_MASK |
                                       PSYS_PART_EMISSIVE_MASK,
            PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
            PSYS_PART_START_COLOR,     col,
            PSYS_PART_END_COLOR,       <1.0, 1.0, 1.0>,
            PSYS_PART_START_ALPHA,     0.7,
            PSYS_PART_END_ALPHA,       0.0,
            PSYS_PART_START_SCALE,     <0.04, 0.04, 0.0>,
            PSYS_PART_END_SCALE,       <0.02, 0.02, 0.0>,
            PSYS_PART_MAX_AGE,         3.0,
            PSYS_SRC_BURST_RATE,       0.8,
            PSYS_SRC_BURST_PART_COUNT, 5,
            PSYS_SRC_BURST_SPEED_MIN,  0.04,
            PSYS_SRC_BURST_SPEED_MAX,  0.1
        ]);

        llSetText("THE CULTIVAR  -  DROP TERMINAL\n? " +
                  g_dropQuality + " " + g_dropStrain + " DROP LIVE ?\n" +
                  "Touch to claim your seed!",
                  col, 1.0);
    }
    else
    {
        // No active drop
        llSetLinkPrimitiveParamsFast(2, [
            PRIM_COLOR, ALL_SIDES, <0.2, 0.2, 0.25>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.01
        ]);
        llSetLinkPrimitiveParamsFast(3, [
            PRIM_COLOR, ALL_SIDES, <0.3, 0.3, 0.35>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.0,
            PRIM_TEXT,  "No active drop\nCheck back soon", <0.6, 0.6, 0.6>, 0.8
        ]);
        llSetLinkPrimitiveParamsFast(5, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);
        llLinkParticleSystem(4, []);
        llSetText("THE CULTIVAR  -  DROP TERMINAL\nNo active drop right now.\nCheck back soon.",
                  <0.5, 0.5, 0.5>, 0.7);
    }
}

// ----------------------------------------------------------------
// Give seed to claimer after server confirms
// ----------------------------------------------------------------
giveSeed(key claimer, string strain)
{
    if (llGetInventoryType(strain) != INVENTORY_OBJECT)
    {
        // Seed object not found in machine inventory
        llRegionSayTo(claimer, 0,
            "[Drop Machine] Seed asset '" + strain +
            "' missing from machine. Please notify the owner.");
        return;
    }
    llGiveInventory(claimer, strain);

    // Notify claimer
    llRegionSayTo(claimer, 0,
        "? DROP CLAIMED! " + g_dropQuality + " " + strain +
        " seed added to your inventory. Grow something special.");

    // Brief celebration burst  -  PSYS_SRC_MAX_AGE auto-stops the source at 0.5s.
    // g_celebrateUntil causes the timer to restore idle particles after 2.5s
    // without calling llSleep() inside an http_response handler.
    llLinkParticleSystem(4, [
        PSYS_PART_FLAGS,           PSYS_PART_EMISSIVE_MASK,
        PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_EXPLODE,
        PSYS_PART_START_COLOR,     qualColor(g_dropQuality),
        PSYS_PART_START_ALPHA,     1.0,
        PSYS_PART_END_ALPHA,       0.0,
        PSYS_PART_START_SCALE,     <0.08, 0.08, 0.0>,
        PSYS_PART_END_SCALE,       <0.02, 0.02, 0.0>,
        PSYS_PART_MAX_AGE,         2.0,
        PSYS_SRC_BURST_RATE,       0.05,
        PSYS_SRC_BURST_PART_COUNT, 20,
        PSYS_SRC_BURST_SPEED_MIN,  0.1,
        PSYS_SRC_BURST_SPEED_MAX,  0.25,
        PSYS_SRC_MAX_AGE,          0.5
    ]);
    llPlaySound("drop_claimed", 0.8);
    g_celebrateUntil = llGetUnixTime() + 3;
    llSetTimerEvent(3.0); // restore idle particles after celebration
}

// ================================================================
default
{
    state_entry()
    {
        llSetTimerEvent(5.0); // initial poll shortly after rez
        updateVisuals();
        // Per-toucher listener opened in touch_start; no always-on listen needed.
        // An always-on NULL_KEY listener here would cause double processing
        // (unfiltered + key-filtered both fire for the same dialog response).
    }

    on_rez(integer start_param) { llResetScript(); }
    changed(integer change)     { if (change & CHANGED_OWNER) llResetScript(); }

    timer()
    {
        // Restore idle particles after celebration burst
        if (g_celebrateUntil > 0 && llGetUnixTime() >= g_celebrateUntil)
        {
            g_celebrateUntil = 0;
            updateVisuals();
            llSetTimerEvent(POLL_INTERVAL);
            return;
        }

        // Claim request timed out
        if (g_claimRequest != NULL_KEY)
        {
            g_claimRequest = NULL_KEY;
            // Notify BEFORE clearing  -  once cleared, the key is lost
            llRegionSayTo(g_claimingAvatar, 0,
                "Claim timed out  -  server didn't respond. Try again.");
            g_claimingAvatar = NULL_KEY;
            g_claimingName   = "";
            g_busy           = FALSE;
        }

        // Poll for drop status
        pollServer();
        llSetTimerEvent(POLL_INTERVAL);
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);

        if (g_busy)
        {
            llRegionSayTo(toucher, 0, "Busy  -  try again in a moment.");
            return;
        }

        if (!g_dropActive)
        {
            llRegionSayTo(toucher, 0,
                "No drop is active right now. Follow The Cultivar group " +
                "for drop announcements.");
            return;
        }

        if (g_dropRemaining <= 0)
        {
            llRegionSayTo(toucher, 0,
                "This drop is sold out. Better luck next time.");
            return;
        }

        if (g_dropEndsAt > 0 && llGetUnixTime() > g_dropEndsAt)
        {
            llRegionSayTo(toucher, 0,
                "This drop has ended. Check back for the next one.");
            g_dropActive = FALSE;
            updateVisuals();
            return;
        }

        // Show claim dialog
        if (g_listenClaim) llListenRemove(g_listenClaim);
        g_listenClaim = llListen(DCHAN_CLAIM, "", toucher, "");

        llDialog(toucher,
            "? DROP: " + g_dropQuality + " " + g_dropStrain + " ?\n\n" +
            (string)g_dropRemaining + " seed packs remaining\n" +
            "One per avatar. No exceptions.\n\n" +
            "Claim your free seed pack?",
            ["Claim It!", "No Thanks"], DCHAN_CLAIM);
        llSetTimerEvent(20.0);
    }

    http_response(key requestId, integer status, list metadata, string body)
    {
        // Poll response
        if (requestId == g_pollRequest)
        {
            g_pollRequest = NULL_KEY;

            if (status != 200)
            {
                // Server error  -  keep existing state, retry next interval
                llSetTimerEvent(POLL_INTERVAL);
                return;
            }

            // Parse response
            string activeStr = jsonGet(body, "active");
            g_dropActive = (activeStr == "true" || activeStr == "1");

            if (g_dropActive)
            {
                g_dropStrain    = jsonGet(body, "strain");
                g_dropQuality   = jsonGet(body, "quality");
                g_dropRemaining = (integer)jsonGet(body, "remaining");
                g_dropEndsAt    = (integer)jsonGet(body, "endsAt");
                g_dropId        = jsonGet(body, "dropId");
            }
            else
            {
                g_dropStrain    = "";
                g_dropQuality   = "";
                g_dropRemaining = 0;
                g_dropEndsAt    = 0;
                g_dropId        = "";
            }

            updateVisuals();
            llSetTimerEvent(POLL_INTERVAL);
        }

        // Claim response
        else if (requestId == g_claimRequest)
        {
            g_claimRequest = NULL_KEY;
            llSetTimerEvent(POLL_INTERVAL);

            if (status != 200)
            {
                llRegionSayTo(g_claimingAvatar, 0,
                    "Server error during claim. Try again shortly.");
                g_busy = FALSE;
                g_claimingAvatar = NULL_KEY;
                return;
            }

            string success = jsonGet(body, "success");
            string reason  = jsonGet(body, "reason");

            if (success == "true" || success == "1")
            {
                giveSeed(g_claimingAvatar, g_dropStrain);
                // Decrement local remaining count (server is authoritative)
                g_dropRemaining--;
                if (g_dropRemaining <= 0)
                {
                    g_dropActive = FALSE;
                    llRegionSay(0,
                        "? THE CULTIVAR DROP: " + g_dropStrain +
                        " is now SOLD OUT. Follow the group for the next drop!");
                }
                updateVisuals();
            }
            else
            {
                string displayReason = reason;
                if (reason == "already_claimed")
                    displayReason = "You already claimed this drop. One per avatar.";
                else if (reason == "drop_ended")
                    displayReason = "This drop just ended.";
                else if (reason == "sold_out")
                    displayReason = "Sold out while you were deciding. Better luck next time.";

                llRegionSayTo(g_claimingAvatar, 0, displayReason);
            }

            g_busy           = FALSE;
            g_claimingAvatar = NULL_KEY;
            g_claimingName   = "";
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel != DCHAN_CLAIM) return;
        if (g_listenClaim) { llListenRemove(g_listenClaim); g_listenClaim = 0; }
        llSetTimerEvent(POLL_INTERVAL);

        if (msg == "No Thanks") return;

        if (msg == "Claim It!")
        {
            if (!g_dropActive || g_dropRemaining <= 0)
            {
                llRegionSayTo(id, 0, "Drop is no longer available.");
                return;
            }
            g_busy = TRUE;
            sendClaimRequest(id, name);
            llRegionSayTo(id, 0, "Verifying with server... one moment.");
        }
    }
}
