// ================================================================
// THE CULTIVAR — HUD Identity Script
// Version: 1.0
// Handles: Player identity, lifetime stats, strain history, rep score
// Persistence: llLinksetDataWrite (survives sim restarts)
// ================================================================

// --- Internal Link Message Channels ---
// All HUD scripts share these constants (copy into each script)
integer CHAN_UI        = 100;  // UI script events
integer CHAN_COMMS     = 200;  // External comms events
integer CHAN_INVENTORY = 300;  // Inventory events
integer CHAN_IDENTITY  = 400;  // Identity events
integer CHAN_ANIMATION = 500;  // Animation events

// --- Identity Data ---
string  g_playerName;
key     g_playerUUID;
integer g_totalSmoked;
integer g_totalGrown;
integer g_totalPassed;
integer g_totalSold;
string  g_favoriteStrain;
string  g_strainHistory;   // comma-delimited list of unique strains tried
integer g_repScore;
string  g_joinDate;
string  g_brandName;    // player's brand/label name (defaults to playerName)

// --- XP Tracking ---
integer g_growerXP   = 0;
integer g_rollerXP   = 0;
integer g_sellerXP   = 0;

// --- Titles / Achievements ---
string  g_earnedAchievements = "";  // comma-delimited list of earned achievement IDs

// ----------------------------------------------------------------
// Save all identity fields to persistent linkset storage
// ----------------------------------------------------------------
saveIdentity()
{
    llLinksetDataWrite("id_name",      g_playerName);
    llLinksetDataWrite("id_smoked",    (string)g_totalSmoked);
    llLinksetDataWrite("id_grown",     (string)g_totalGrown);
    llLinksetDataWrite("id_passed",    (string)g_totalPassed);
    llLinksetDataWrite("id_sold",      (string)g_totalSold);
    llLinksetDataWrite("id_fav",       g_favoriteStrain);
    llLinksetDataWrite("id_history",   g_strainHistory);
    llLinksetDataWrite("id_rep",       (string)g_repScore);
    llLinksetDataWrite("id_joined",    g_joinDate);
    llLinksetDataWrite("id_brand",     g_brandName);
    llLinksetDataWrite("id_grower_xp",    (string)g_growerXP);
    llLinksetDataWrite("id_roller_xp",    (string)g_rollerXP);
    llLinksetDataWrite("id_seller_xp",    (string)g_sellerXP);
    llLinksetDataWrite("id_achievements", g_earnedAchievements);
}

// ----------------------------------------------------------------
// XP/Level helpers
// ----------------------------------------------------------------
integer levelFromXP(integer xp)
{
    if (xp <= 0) return 0;
    return (integer)llSqrt((float)xp);
}

notifyLevelUp(string track, integer level)
{
    string perkMsg = "";
    if (track == "grower")
    {
        if (level == 10) perkMsg = "Perk: +15% harvest yield!";
        else if (level == 20) perkMsg = "Perk: +30% harvest yield!";
    }
    else if (track == "roller")
    {
        if (level == 10) perkMsg = "Perk: Backwood option unlocked at rolling table!";
        else if (level == 20) perkMsg = "Perk: -1g rolling cost reduction!";
    }
    else if (track == "seller")
    {
        if (level == 10) perkMsg = "Perk: 5% PlugBoard fee reduction!";
        else if (level == 20) perkMsg = "Perk: 10% PlugBoard fee reduction!";
    }
    string msg = "Level Up! " + llToUpper(track) + " Level " + (string)level + "!";
    if (perkMsg != "") msg += "  " + perkMsg;
    llOwnerSay(msg);
    llMessageLinked(LINK_SET, CHAN_UI,
        "XP_LEVEL_UP|" + track + "|" + (string)level + "|" + perkMsg, NULL_KEY);
}

grantXP(string track, integer amount)
{
    integer oldLevel;
    integer newLevel;
    if (track == "grower")
    {
        oldLevel = levelFromXP(g_growerXP);
        g_growerXP += amount;
        newLevel = levelFromXP(g_growerXP);
        llLinksetDataWrite("grower_level", (string)newLevel);
        llLinksetDataWrite("id_grower_xp", (string)g_growerXP);
    }
    else if (track == "roller")
    {
        oldLevel = levelFromXP(g_rollerXP);
        g_rollerXP += amount;
        newLevel = levelFromXP(g_rollerXP);
        llLinksetDataWrite("roller_level", (string)newLevel);
        llLinksetDataWrite("id_roller_xp", (string)g_rollerXP);
    }
    else if (track == "seller")
    {
        oldLevel = levelFromXP(g_sellerXP);
        g_sellerXP += amount;
        newLevel = levelFromXP(g_sellerXP);
        llLinksetDataWrite("seller_level", (string)newLevel);
        llLinksetDataWrite("id_seller_xp", (string)g_sellerXP);
    }
    else return;
    if (newLevel > oldLevel)
        notifyLevelUp(track, newLevel);
}

// ----------------------------------------------------------------
// Load identity from persistent storage, or initialize fresh
// ----------------------------------------------------------------
loadIdentity()
{
    string test = llLinksetDataRead("id_name");

    if (test == "")
    {
        // First time this HUD has been used — initialize fresh
        g_playerName     = llKey2Name(llGetOwner());
        g_playerUUID     = llGetOwner();
        g_totalSmoked    = 0;
        g_totalGrown     = 0;
        g_totalPassed    = 0;
        g_totalSold      = 0;
        g_favoriteStrain = "None";
        g_strainHistory  = "";
        g_repScore       = 0;
        g_joinDate       = llGetDate();
        g_brandName           = g_playerName;
        g_growerXP            = 0;
        g_rollerXP            = 0;
        g_sellerXP            = 0;
        g_earnedAchievements  = "";
        saveIdentity();
        llOwnerSay("Welcome to the The Cultivar! Your profile has been created.");
    }
    else
    {
        g_playerName     = llLinksetDataRead("id_name");
        g_playerUUID     = llGetOwner();
        g_totalSmoked    = (integer)llLinksetDataRead("id_smoked");
        g_totalGrown     = (integer)llLinksetDataRead("id_grown");
        g_totalPassed    = (integer)llLinksetDataRead("id_passed");
        g_totalSold      = (integer)llLinksetDataRead("id_sold");
        g_favoriteStrain = llLinksetDataRead("id_fav");
        g_strainHistory  = llLinksetDataRead("id_history");
        g_repScore       = (integer)llLinksetDataRead("id_rep");
        g_joinDate       = llLinksetDataRead("id_joined");
        g_brandName      = llLinksetDataRead("id_brand");
        if (g_brandName == "") g_brandName = g_playerName;
        g_growerXP       = (integer)llLinksetDataRead("id_grower_xp");
        g_rollerXP       = (integer)llLinksetDataRead("id_roller_xp");
        g_sellerXP       = (integer)llLinksetDataRead("id_seller_xp");
        // Restore level caches so world objects get current levels via TC_REGISTER
        llLinksetDataWrite("grower_level", (string)levelFromXP(g_growerXP));
        llLinksetDataWrite("roller_level", (string)levelFromXP(g_rollerXP));
        llLinksetDataWrite("seller_level", (string)levelFromXP(g_sellerXP));
        g_earnedAchievements = llLinksetDataRead("id_achievements");
    }
}

// ----------------------------------------------------------------
// Derive player title from current stats
// ----------------------------------------------------------------
string titleFromStats()
{
    integer growerLevel = levelFromXP(g_growerXP);
    integer rollerLevel = levelFromXP(g_rollerXP);
    list    history     = llParseString2List(g_strainHistory, [","], []);
    integer strainCount = llGetListLength(history);

    if (growerLevel >= 20)   return "The Cultivar";
    if (growerLevel >= 10)   return "Cultivator";
    if (g_totalSold >= 25)   return "Head Plug";
    if (rollerLevel >= 10)   return "Blunt Boss";
    if (strainCount >= 25)   return "Connoisseur";
    if (g_totalSold >= 5)    return "Plug";
    if (g_totalGrown >= 25)  return "Master Grower";
    if (g_totalGrown >= 10)  return "Green Thumb";
    if (g_totalSmoked >= 10) return "Novice Smoker";
    return "Seedling";
}

// ----------------------------------------------------------------
// Human-readable label for an achievement ID
// ----------------------------------------------------------------
string achievementLabel(string aId)
{
    if (aId == "first_smoke")       return "First Smoke — Welcome to the culture!";
    if (aId == "decade_smoked")     return "Decade Smoked — 10 sessions logged!";
    if (aId == "century_smoked")    return "Century Smoked — 100 sessions logged!";
    if (aId == "first_grow")        return "First Harvest — Grew your first plant!";
    if (aId == "green_thumb")       return "Green Thumb — 10 harvests completed!";
    if (aId == "first_pass")        return "Good Vibes — First time passing the piece!";
    if (aId == "first_sale")        return "First Sale — Made your first deal!";
    if (aId == "strain_explorer")   return "Strain Explorer — Tried 5 different strains!";
    if (aId == "strain_collector")  return "Strain Collector — Tried 15 different strains!";
    return aId;
}

// ----------------------------------------------------------------
// Check for newly unlocked achievements; announce and persist
// ----------------------------------------------------------------
checkAchievements()
{
    list earned = llParseString2List(g_earnedAchievements, [","], []);
    list newOnes;
    list history = llParseString2List(g_strainHistory, [","], []);
    integer strainCount = llGetListLength(history);

    if (g_totalSmoked >= 1   && llListFindList(earned, ["first_smoke"])      == -1) newOnes += ["first_smoke"];
    if (g_totalSmoked >= 10  && llListFindList(earned, ["decade_smoked"])    == -1) newOnes += ["decade_smoked"];
    if (g_totalSmoked >= 100 && llListFindList(earned, ["century_smoked"])   == -1) newOnes += ["century_smoked"];
    if (g_totalGrown  >= 1   && llListFindList(earned, ["first_grow"])       == -1) newOnes += ["first_grow"];
    if (g_totalGrown  >= 10  && llListFindList(earned, ["green_thumb"])      == -1) newOnes += ["green_thumb"];
    if (g_totalPassed >= 1   && llListFindList(earned, ["first_pass"])       == -1) newOnes += ["first_pass"];
    if (g_totalSold   >= 1   && llListFindList(earned, ["first_sale"])       == -1) newOnes += ["first_sale"];
    if (strainCount   >= 5   && llListFindList(earned, ["strain_explorer"])  == -1) newOnes += ["strain_explorer"];
    if (strainCount   >= 15  && llListFindList(earned, ["strain_collector"]) == -1) newOnes += ["strain_collector"];

    integer n = llGetListLength(newOnes);
    if (n == 0) return;

    integer i;
    for (i = 0; i < n; i++)
    {
        string aId    = llList2String(newOnes, i);
        string aLabel = achievementLabel(aId);
        llOwnerSay("Achievement Unlocked: " + aLabel);
        llMessageLinked(LINK_SET, CHAN_UI,
            "ACHIEVEMENT_UNLOCKED|" + aId + "|" + aLabel, NULL_KEY);
        earned += [aId];
    }
    g_earnedAchievements = llDumpList2String(earned, ",");
    llLinksetDataWrite("id_achievements", g_earnedAchievements);
}

// ----------------------------------------------------------------
// Broadcast current identity to all other HUD scripts
// ----------------------------------------------------------------
broadcastIdentity()
{
    string payload = g_playerName    + "|" +
                     (string)g_playerUUID + "|" +
                     (string)g_totalSmoked  + "|" +
                     (string)g_totalGrown   + "|" +
                     (string)g_totalPassed  + "|" +
                     (string)g_totalSold    + "|" +
                     g_favoriteStrain       + "|" +
                     (string)g_repScore     + "|" +
                     g_joinDate             + "|" +
                     g_brandName            + "|" +
                     (string)levelFromXP(g_growerXP) + "|" +
                     (string)levelFromXP(g_rollerXP) + "|" +
                     (string)levelFromXP(g_sellerXP) + "|" +
                     titleFromStats();

    // Must send on CHAN_UI — that is the channel the UI script listens on.
    // CHAN_IDENTITY is for commands sent TO this script, not broadcasts FROM it.
    llMessageLinked(LINK_SET, CHAN_UI, "IDENTITY_DATA|" + payload, NULL_KEY);
}

// ----------------------------------------------------------------
// Add a strain to history if not already recorded
// ----------------------------------------------------------------
recordStrain(string strainName)
{
    list history = llParseString2List(g_strainHistory, [","], []);
    if (llListFindList(history, [strainName]) == -1)
    {
        if (g_strainHistory == "")
            g_strainHistory = strainName;
        else
            g_strainHistory += "," + strainName;
    }
    // Simple favorite logic: most recently smoked
    // A future version could track counts per strain
    g_favoriteStrain = strainName;
}

// ================================================================
default
{
    state_entry()
    {
        g_playerUUID = llGetOwner();
        loadIdentity();
        broadcastIdentity();
    }

    on_rez(integer start_param)
    {
        loadIdentity();
        broadcastIdentity();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            // Wipe all data for new owner, then reset
            llLinksetDataReset();
            llResetScript();
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != CHAN_IDENTITY) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // Another script requesting identity data (e.g. UI on open)
        if (cmd == "REQUEST_IDENTITY")
        {
            broadcastIdentity();
        }

        // Plant/jar reports a completed smoke
        else if (cmd == "UPDATE_SMOKED")
        {
            string strain = llList2String(parts, 1);
            g_totalSmoked++;
            recordStrain(strain);
            checkAchievements();
            saveIdentity();
            broadcastIdentity();
        }

        // Plant reports a completed harvest
        else if (cmd == "UPDATE_GROWN")
        {
            g_totalGrown++;
            checkAchievements();
            saveIdentity();
        }

        // Pass system reports a successful pass
        else if (cmd == "UPDATE_PASSED")
        {
            g_totalPassed++;
            checkAchievements();
            saveIdentity();
        }

        // Plug board reports a sale
        else if (cmd == "UPDATE_SOLD")
        {
            g_totalSold++;
            checkAchievements();
            saveIdentity();
        }

        // Buyer leaves rep after a transaction
        else if (cmd == "UPDATE_REP")
        {
            integer delta = (integer)llList2String(parts, 1);
            g_repScore += delta;
            if (g_repScore < 0) g_repScore = 0; // floor at zero
            saveIdentity();
            broadcastIdentity();
        }

        // XP grant from HUD_Comms or other internal scripts
        else if (cmd == "UPDATE_XP")
        {
            // UPDATE_XP|track|amount
            grantXP(llList2String(parts, 1), (integer)llList2String(parts, 2));
        }

        // UI sets a custom brand/label name
        else if (cmd == "SET_BRAND_NAME")
        {
            g_brandName = llList2String(parts, 1);
            llLinksetDataWrite("id_brand", g_brandName);
            broadcastIdentity();
        }

        // UI requests a formatted stats card for display
        else if (cmd == "REQUEST_STATS_CARD")
        {
            list    history    = llParseString2List(g_strainHistory, [","], []);
            list    earned     = llParseString2List(g_earnedAchievements, [","], []);
            string  brandLine  = "";
            if (g_brandName != "" && g_brandName != g_playerName)
                brandLine = "Brand Name: " + g_brandName + "\n";
            string card = "\n=== " + g_playerName + "'s Stats ===\n" +
                          "Title: "           + titleFromStats()       + "\n" +
                          brandLine +
                          "Member Since: "    + g_joinDate             + "\n" +
                          "Times Smoked: "    + (string)g_totalSmoked  + "\n" +
                          "Total Grown: "     + (string)g_totalGrown   + "\n" +
                          "Times Passed: "    + (string)g_totalPassed  + "\n" +
                          "Items Sold: "      + (string)g_totalSold    + "\n" +
                          "Favorite Strain: " + g_favoriteStrain       + "\n" +
                          "Strains Tried: "   + (string)llGetListLength(history) + "\n" +
                          "Rep Score: "       + (string)g_repScore     + "\n" +
                          "Achievements: "    + (string)llGetListLength(earned)  + "\n" +
                          "Grower: Lvl "      + (string)levelFromXP(g_growerXP) +
                            "  (" + (string)g_growerXP + " XP)\n" +
                          "Roller: Lvl "      + (string)levelFromXP(g_rollerXP) +
                            "  (" + (string)g_rollerXP + " XP)\n" +
                          "Seller: Lvl "      + (string)levelFromXP(g_sellerXP) +
                            "  (" + (string)g_sellerXP + " XP)";
            llMessageLinked(LINK_SET, CHAN_UI, "SHOW_STATS|" + card, NULL_KEY);
        }

        // UI requests full achievement list
        else if (cmd == "REQUEST_ACHIEVEMENTS")
        {
            list earned = llParseString2List(g_earnedAchievements, [","], []);
            integer n   = llGetListLength(earned);
            if (n == 0)
            {
                llOwnerSay("No achievements unlocked yet. Keep playing!");
                return;
            }
            string out = "=== ACHIEVEMENTS (" + (string)n + ") ===\n";
            integer i;
            for (i = 0; i < n; i++)
                out += "✓ " + achievementLabel(llList2String(earned, i)) + "\n";
            llOwnerSay(out);
        }
    }
}
