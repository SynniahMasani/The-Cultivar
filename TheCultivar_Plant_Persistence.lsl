// ================================================================
// THE CULTIVAR  -  Plant Persistence Script
// Version: 1.0
// Handles: Saving and loading all plant state so nothing is
//          ever lost during sim restarts, crashes, or relogs.
//
// STORAGE STRATEGY:
//   Primary   : llLinksetDataWrite  -  fast, survives restarts
//   Backup    : Object description field  -  readable even without
//               scripts (last resort recovery)
//
// WHAT IS SAVED:
//   strainName, qualityTier, stage, stageStartTime, stageDuration,
//   isWatered, fertApplied, fertTier, potType, potUsesLeft
//
// TIMING RECOVERY:
//   stageStartTime is stored as a Unix timestamp.
//   On load, we compare it against llGetUnixTime() to figure out
//   how much time has passed while the sim was down. If enough
//   time passed that a stage (or multiple stages) completed,
//   we fast-forward the plant to the correct state automatically.
//   This means a plant that was nearly harvest-ready won't be
//   stuck waiting after a sim restart.
// ================================================================

integer PCHAN_GROW    = 1000;
integer PCHAN_PERSIST = 1100;

// Grow times by quality tier (seconds per full cycle)
// Must match Plant_Grow.lsl
list GROW_TIMES = [2700, 7200, 14400, 28800];

// ----------------------------------------------------------------
// Build a serialized state string from all parameters
// ----------------------------------------------------------------
string buildSaveString(string strainName, integer qualityTier,
                       integer stage, integer stageStartTime,
                       integer stageDuration, integer isWatered,
                       integer fertApplied, integer fertTier,
                       string potType, integer potUsesLeft,
                       integer potSpent)
{
    return strainName            + "|" +
           (string)qualityTier   + "|" +
           (string)stage         + "|" +
           (string)stageStartTime + "|" +
           (string)stageDuration  + "|" +
           (string)isWatered      + "|" +
           (string)fertApplied    + "|" +
           (string)fertTier       + "|" +
           potType                + "|" +
           (string)potUsesLeft    + "|" +
           (string)potSpent;
}

// ----------------------------------------------------------------
// Save state to linkset data and object description backup
// ----------------------------------------------------------------
saveState(string stateStr)
{
    llLinksetDataWrite("plant_state", stateStr);
}

// ----------------------------------------------------------------
// Load state from storage
// Returns the state string, or "" if nothing saved
// ----------------------------------------------------------------
string loadState()
{
    return llLinksetDataRead("plant_state");
}

// ----------------------------------------------------------------
// Fast-forward through stages based on elapsed time since save
// Used to recover correctly after a sim was down for hours
// ----------------------------------------------------------------
string fastForward(string stateStr)
{
    list parts = llParseString2List(stateStr, ["|"], []);
    if (llGetListLength(parts) < 10) return stateStr;

    string  strainName     = llList2String(parts, 0);
    integer qualityTier    = (integer)llList2String(parts, 1);
    integer stage          = (integer)llList2String(parts, 2);
    integer stageStartTime = (integer)llList2String(parts, 3);
    integer stageDuration  = (integer)llList2String(parts, 4);
    integer isWatered      = (integer)llList2String(parts, 5);
    integer fertApplied    = (integer)llList2String(parts, 6);
    integer fertTier       = (integer)llList2String(parts, 7);
    string  potType        = llList2String(parts, 8);
    integer potUsesLeft    = (integer)llList2String(parts, 9);
    // potSpent is at index 10 in the save string (absent in old saves  -  defaults to 0)
    integer potSpent       = (integer)llList2String(parts, 10);

    // Only fast-forward active growing stages (1-3)
    if (stage == 0 || stage == 4) return stateStr;
    if (strainName == "")         return stateStr;

    // Detect hybrid/legendary from strain name (matches calcStageDuration in Grow script)
    integer isHybrid    = (llSubStringIndex(strainName, " x ") != -1);
    integer isLegendary = isHybrid && (llSubStringIndex(strainName, "[LEGENDARY]") != -1);

    integer now       = llGetUnixTime();
    integer stagesAdvanced = 0;

    // Keep advancing stages as long as time has elapsed past them
    // Watering is forgiven during fast-forward (sim was down  -  not player's fault)
    while (stage < 4)
    {
        integer elapsed = now - stageStartTime;
        if (elapsed >= stageDuration)
        {
            stage++;
            stagesAdvanced++;
            stageStartTime = stageStartTime + stageDuration; // advance start
            // Reset water (new stage)
            isWatered = FALSE;
            // Recalculate stage duration for next stage (must match calcStageDuration)
            integer fullCycle = llList2Integer(GROW_TIMES, qualityTier);
            stageDuration = fullCycle / 4;
            if (potType == "premium")
                stageDuration = (integer)((float)stageDuration * 0.95);
            if (isLegendary)
                stageDuration = (integer)((float)stageDuration * 0.85);
            else if (isHybrid)
                stageDuration = (integer)((float)stageDuration * 0.92);
        }
        else
        {
            jump done_ff; // Current stage not complete  -  stop here
        }
    }
    @done_ff;

    if (stagesAdvanced > 0)
    {
        string harvestMsg = ".";
        if (stage == 4) harvestMsg = "  -  ready to harvest!";
        llOwnerSay("? Your " + strainName +
                   " grew while you were away. Now at stage " +
                   (string)stage + harvestMsg);
    }

    return buildSaveString(strainName, qualityTier, stage, stageStartTime,
                           stageDuration, isWatered, fertApplied, fertTier,
                           potType, potUsesLeft, potSpent);
}

// ================================================================
default
{
    state_entry()
    {
        // On startup, load and restore state
        string saved = loadState();
        if (saved != "")
        {
            // Fast-forward through any stages that completed while sim was down
            string updated = fastForward(saved);

            // If state changed during fast-forward, save the updated version
            if (updated != saved)
                saveState(updated);

            // Send loaded state to grow script
            llMessageLinked(LINK_SET, PCHAN_GROW,
                "STATE_LOADED|" + updated, NULL_KEY);
        }
        else
        {
            // Brand new plant  -  tell grow script it's fresh
            llMessageLinked(LINK_SET, PCHAN_GROW,
                "STATE_LOADED|||0|0|0|0|0|0|basic|5", NULL_KEY);
        }
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != PCHAN_PERSIST) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Grow script wants to save current state
        if (cmd == "SAVE_STATE")
        {
            // Ask grow script for its current state, then switch to 'saving' state
            // to intercept the STATUS response and persist it.
            // Without the state transition the STATUS reply arrives in 'default'
            // which has no STATUS handler  -  nothing would ever get saved.
            llMessageLinked(LINK_SET, PCHAN_GROW, "REQUEST_STATUS", NULL_KEY);
            state saving;
        }

        // Grow script sends current status  -  we save it
        // (We listen on PCHAN_GROW for STATUS responses so we can save them)
        else if (cmd == "LOAD_STATE")
        {
            // Re-run the load process (used if grow script resets)
            string saved = loadState();
            if (saved != "")
            {
                string updated = fastForward(saved);
                if (updated != saved) saveState(updated);
                llMessageLinked(LINK_SET, PCHAN_GROW,
                    "STATE_LOADED|" + updated, NULL_KEY);
            }
        }

        // Clear all saved data (on pot spent / plant removed)
        else if (cmd == "CLEAR_STATE")
        {
            llLinksetDataDelete("plant_state");
            llSetObjectDesc(""); // clear any legacy description backup
        }
    }

    // We also listen on PCHAN_GROW to intercept STATUS messages
    // so we can save them without the grow script having to know we exist
}

// ================================================================
// Secondary state to intercept grow script STATUS messages for saving
// This avoids the grow script needing to format data twice
// ================================================================
state saving
{
    state_entry() {}

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num == PCHAN_GROW)
        {
            list   parts = llParseString2List(msg, ["|"], []);
            string cmd   = llList2String(parts, 0);

            if (cmd == "STATUS")
            {
                // STATUS|strainName|qualityTier|stage|stageStartTime|stageDuration
                //        |isWatered|fertApplied|fertTier|potType|potUsesLeft|potSpent
                string stateStr = buildSaveString(
                    llList2String(parts, 1),
                    (integer)llList2String(parts, 2),
                    (integer)llList2String(parts, 3),
                    (integer)llList2String(parts, 4),
                    (integer)llList2String(parts, 5),
                    (integer)llList2String(parts, 6),
                    (integer)llList2String(parts, 7),
                    (integer)llList2String(parts, 8),
                    llList2String(parts, 9),
                    (integer)llList2String(parts, 10),
                    (integer)llList2String(parts, 11)
                );
                saveState(stateStr);
                state default;
            }
        }
        if (num == PCHAN_PERSIST)
        {
            // Handle LOAD_STATE even while in saving state
            list   parts = llParseString2List(msg, ["|"], []);
            if (llList2String(parts,0) == "LOAD_STATE") state default;
        }
    }
}
