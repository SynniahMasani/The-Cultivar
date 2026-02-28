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

// ----------------------------------------------------------------
// Save all identity fields to persistent linkset storage
// ----------------------------------------------------------------
saveIdentity()
{
    llLinksetDataWrite("id_name",    g_playerName);
    llLinksetDataWrite("id_smoked",  (string)g_totalSmoked);
    llLinksetDataWrite("id_grown",   (string)g_totalGrown);
    llLinksetDataWrite("id_passed",  (string)g_totalPassed);
    llLinksetDataWrite("id_sold",    (string)g_totalSold);
    llLinksetDataWrite("id_fav",     g_favoriteStrain);
    llLinksetDataWrite("id_history", g_strainHistory);
    llLinksetDataWrite("id_rep",     (string)g_repScore);
    llLinksetDataWrite("id_joined",  g_joinDate);
    llLinksetDataWrite("id_brand",   g_brandName);
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
        g_brandName      = g_playerName;
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
    }
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
                     g_brandName;

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
            // Wipe data for new owner
            llLinksetDataDeleteFound("id_", "");
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
            saveIdentity();
            broadcastIdentity();
        }

        // Plant reports a completed harvest
        else if (cmd == "UPDATE_GROWN")
        {
            g_totalGrown++;
            saveIdentity();
        }

        // Pass system reports a successful pass
        else if (cmd == "UPDATE_PASSED")
        {
            g_totalPassed++;
            saveIdentity();
        }

        // Plug board reports a sale
        else if (cmd == "UPDATE_SOLD")
        {
            g_totalSold++;
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
            list history = llParseString2List(g_strainHistory, [","], []);
            string brandLine = "";
            if (g_brandName != "" && g_brandName != g_playerName)
                brandLine = "Brand Name: " + g_brandName + "\n";
            string card = "\n=== " + g_playerName + "'s Stats ===\n" +
                          brandLine +
                          "Member Since: "    + g_joinDate           + "\n" +
                          "Times Smoked: "    + (string)g_totalSmoked  + "\n" +
                          "Total Grown: "     + (string)g_totalGrown   + "\n" +
                          "Times Passed: "    + (string)g_totalPassed  + "\n" +
                          "Items Sold: "      + (string)g_totalSold    + "\n" +
                          "Favorite Strain: " + g_favoriteStrain       + "\n" +
                          "Strains Tried: "   + (string)llGetListLength(history) + "\n" +
                          "Rep Score: "       + (string)g_repScore;
            llMessageLinked(LINK_SET, CHAN_UI, "SHOW_STATS|" + card, NULL_KEY);
        }
    }
}
