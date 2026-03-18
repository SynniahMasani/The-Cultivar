// ================================================================
// THE CULTIVAR  -  HUD Comms Script
// Version: 1.1
// Handles: ALL external communication between the HUD and world
//          objects (plants, jars, crafting tables, session objects,
//          other player HUDs). The switchboard.
//
// Channel Strategy:
//   g_privateChannel  -  derived from owner UUID, used for all
//                      direct HUD<->object communication. Private
//                      per player so objects can target the right HUD.
//   PUBLIC_SESSION_CHAN  -  used to broadcast/receive session invites
//                         in the region. Known channel, but messages
//                         carry UUID for verification.
// ================================================================

integer CHAN_UI        = 100;
integer CHAN_COMMS     = 200;
integer CHAN_INVENTORY = 300;
integer CHAN_IDENTITY  = 400;
integer CHAN_ANIMATION = 500;

// Session invites broadcast on a known public channel
// Objects listening for nearby HUDs use this
integer PUBLIC_SESSION_CHAN = -987654321;

// World objects ping on this channel when touched, HUD responds with TC_REGISTER
integer TC_OBJECT_PING_CHAN = -111222333;

// Derived private channel  -  unique per owner, hard to guess
integer g_privateChannel;
integer g_listenPrivate;
integer g_listenSession;

key     g_ownerKey;
string  g_ownerName;

// Wrapper inventory: stride-1 list, each entry "flavor|count"
// Populated by TC_WRAPPER_GIVE; queried by Rolling Table via TC_WRAPPER_QUERY
list g_wrapperInventory = [];

// Track active session if any
integer g_inSession = FALSE;
key     g_sessionObjectKey = NULL_KEY;
string  g_sessionHost = "";

// ----------------------------------------------------------------
// Derive a private channel from the owner's UUID
// Consistent across rezzings, unique per player
// ----------------------------------------------------------------
integer derivePrivateChannel(key ownerID)
{
    string hexSub = llGetSubString((string)ownerID, 0, 6);
    // Strip hyphens if present
    hexSub = llDumpList2String(llParseString2List(hexSub,["-"],[]),"");
    return (integer)("0x" + hexSub) * -1; // negative channel, avoids chat
}

// ----------------------------------------------------------------
// Register listeners
// ----------------------------------------------------------------
startListening()
{
    // Private channel for world objects addressing THIS HUD
    g_listenPrivate = llListen(g_privateChannel, "", NULL_KEY, "");
    // Public session channel for nearby invite broadcasts
    g_listenSession = llListen(PUBLIC_SESSION_CHAN, "", NULL_KEY, "");
    // World object ping channel  -  objects announce themselves here when touched
    llListen(TC_OBJECT_PING_CHAN, "", NULL_KEY, "");
}

// ----------------------------------------------------------------
// Tell a world object what channel to use to reach this HUD
// Called after touching a plant, jar, table, etc.
// ----------------------------------------------------------------
registerWithObject(key objectKey)
{
    // Send our private channel, owner key, and brand name to the object
    llRegionSayTo(objectKey, 0,
        "TC_REGISTER|" + (string)g_ownerKey + "|" +
        (string)g_privateChannel + "|" + g_ownerName + "|" +
        llLinksetDataRead("id_brand"));
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey  = llGetOwner();
        g_ownerName = llKey2Name(g_ownerKey);
        g_privateChannel = derivePrivateChannel(g_ownerKey);
        // Store so UI script can include it in TC_SESSION_START messages
        llLinksetDataWrite("hud_private_chan", (string)g_privateChannel);
        startListening();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    // ----------------------------------------------------------
    // INTERNAL: Messages from other HUD scripts going OUT
    // ----------------------------------------------------------
    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != CHAN_COMMS) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // UI tells comms to register with a world object the player just touched
        if (cmd == "REGISTER_OBJECT")
        {
            registerWithObject((key)llList2String(parts, 1));
        }

        // Player initiated a session as host  -  update state, notify UI
        else if (cmd == "START_SESSION")
        {
            key sessionObj = (key)llList2String(parts, 1);
            g_inSession        = TRUE;
            g_sessionObjectKey = sessionObj;
            g_sessionHost      = g_ownerName;
            // Store private channel in linkset data so UI can read it for TC_SESSION_START
            llLinksetDataWrite("hud_private_chan", (string)g_privateChannel);
            llMessageLinked(LINK_SET, CHAN_UI,
                "SESSION_STARTED|" + (string)sessionObj, NULL_KEY);
        }

        // Player accepted an invite  -  join the session object
        else if (cmd == "JOIN_SESSION")
        {
            // JOIN_SESSION|sessionObjectKey|hostName
            key    sessObjKey = (key)llList2String(parts, 1);
            string hostName   = llList2String(parts, 2);
            llRegionSayTo(sessObjKey, 0,
                "TC_SESSION_JOIN|" + (string)g_ownerKey + "|" +
                (string)g_privateChannel + "|" + g_ownerName);
            g_inSession        = TRUE;
            g_sessionObjectKey = sessObjKey;
            g_sessionHost      = hostName;
            // TC_SESSION_JOINED confirmation will come back from session object
        }

        // Player passing an item to another player
        else if (cmd == "PASS_TO_PLAYER")
        {
            // PASS_TO_PLAYER|targetUUID|itemType|strainName|quality|qty|packager
            key    targetKey = (key)llList2String(parts, 1);
            string passMsg   = "TC_RECEIVE_PASS|" +
                               llList2String(parts, 2) + "|" +  // itemType
                               llList2String(parts, 3) + "|" +  // strainName
                               llList2String(parts, 4) + "|" +  // quality
                               llList2String(parts, 5) + "|" +  // qty
                               llList2String(parts, 6) + "|" +  // packager
                               g_ownerName;                     // from
            integer targetChan = derivePrivateChannel(targetKey);
            llRegionSayTo(targetKey, targetChan, passMsg);

            // Update own identity stat
            llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_PASSED", NULL_KEY);
        }

        // Leave current session
        else if (cmd == "LEAVE_SESSION")
        {
            if (g_inSession && g_sessionObjectKey != NULL_KEY)
            {
                llRegionSayTo(g_sessionObjectKey, 0,
                    "TC_SESSION_LEAVE|" + (string)g_ownerKey);
            }
            g_inSession        = FALSE;
            g_sessionObjectKey = NULL_KEY;
            g_sessionHost      = "";
            llMessageLinked(LINK_SET, CHAN_ANIMATION, "STOP_SMOKE_ANIM", NULL_KEY);
        }

        // Relay any remove success/fail back to UI for feedback
        // If id is set, a world object is waiting  -  notify it on our private channel
        else if (cmd == "REMOVE_SUCCESS")
        {
            llMessageLinked(LINK_SET, CHAN_UI, "ITEM_USED|" + msg, NULL_KEY);
            if (id != NULL_KEY)
                llRegionSayTo(id, g_privateChannel, "TC_REMOVE_OK");
        }
        else if (cmd == "REMOVE_FAIL")
        {
            llMessageLinked(LINK_SET, CHAN_UI, "ITEM_FAILED|" + msg, NULL_KEY);
            if (id != NULL_KEY)
                llRegionSayTo(id, g_privateChannel, "TC_REMOVE_FAIL");
        }

        // Inventory manager responds with raw data  -  forward to requesting world object
        else if (cmd == "RAW_INVENTORY")
        {
            // RAW_INVENTORY|serializedData|filterType|requestingObjectKey
            string rawData   = llList2String(parts, 1);
            key    reqObject = (key)llList2String(parts, 3);
            // Send on our private channel  -  world objects listen on g_hudChannel
            // which equals g_privateChannel. Channel 0 is unreliable to objects.
            if (reqObject != NULL_KEY)
                llRegionSayTo(reqObject, g_privateChannel, "TC_INVENTORY_DATA|" + rawData);
        }
    }

    // ----------------------------------------------------------
    // EXTERNAL: Messages arriving FROM world objects
    // ----------------------------------------------------------
    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- World object announcing itself (any object that was just touched) ----
        if (channel == TC_OBJECT_PING_CHAN && cmd == "TC_PING")
        {
            // TC_PING|objectKey|objectType|replyChannel
            key     objectKey   = (key)llList2String(parts, 1);
            integer replyChannel = (integer)llList2String(parts, 3);
            if (replyChannel == 0) replyChannel = 0; // legacy fallback (should never be 0)
            llRegionSay(replyChannel,
                "TC_REGISTER|" + (string)g_ownerKey + "|" +
                (string)g_privateChannel + "|" + g_ownerName + "|" +
                llLinksetDataRead("id_brand"));
        }

        // ---- Session object rezzed  -  it announces itself so HUD can fire TC_SESSION_START ----
        else if (channel == TC_OBJECT_PING_CHAN && cmd == "TC_SESSION_REZZED")
        {
            // TC_SESSION_REZZED|sessionObjectKey|sessionChannel
            key sessObjKey = (key)llList2String(parts, 1);
            // Forward to UI so it can complete the session start flow
            llMessageLinked(LINK_SET, CHAN_UI,
                "SESSION_OBJECT_READY|" + (string)sessObjKey, NULL_KEY);
        }

        // ---- Messages on our private channel (from world objects) ----
        else if (channel == g_privateChannel)
        {
            // Plant reports a successful harvest
            if (cmd == "TC_HARVEST_RESULT")
            {
                // TC_HARVEST_RESULT|strainName|quality|qty
                string strain  = llList2String(parts, 1);
                string quality = llList2String(parts, 2);
                integer qty    = (integer)llList2String(parts, 3);
                string owner   = llKey2Name(g_ownerKey);

                // Apply grower level yield perk before adding to inventory
                integer growerLevel = (integer)llLinksetDataRead("grower_level");
                if (growerLevel >= 20)
                    qty = qty + (qty * 30 / 100);
                else if (growerLevel >= 10)
                    qty = qty + (qty * 15 / 100);

                // Add to inventory
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "ADD_ITEM|flower_raw|" + strain + "|" + quality + "|" +
                    (string)qty + "|" + owner, NULL_KEY);

                // Update grown stat and grant grower XP
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_GROWN", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_XP|grower|5", NULL_KEY);

                llOwnerSay("Harvest received: " + (string)qty + "g of " +
                           quality + " " + strain + "!");
            }

            // Jar or session object confirms a smokeable was consumed
            else if (cmd == "TC_SMOKED")
            {
                string strain  = llList2String(parts, 1);
                string quality = llList2String(parts, 2);
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_SMOKED|" + strain, NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_ANIMATION,
                    "START_SMOKE_ANIM|" + strain + "|" + quality, NULL_KEY);
                // Tell UI to light the smoke button and update state
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SMOKE_STARTED|" + strain + "|" + quality, NULL_KEY);
            }

            // Session object sends sync signal to start animation
            else if (cmd == "TC_SESSION_SYNC")
            {
                string strain  = llList2String(parts, 1);
                string quality = llList2String(parts, 2);
                llMessageLinked(LINK_SET, CHAN_ANIMATION,
                    "START_SMOKE_ANIM|" + strain + "|" + quality, NULL_KEY);
                llOwnerSay("Session started  -  passing the " + strain + ".");
            }

            // Session ended by host or item ran out
            else if (cmd == "TC_SESSION_END")
            {
                g_inSession        = FALSE;
                g_sessionObjectKey = NULL_KEY;
                llMessageLinked(LINK_SET, CHAN_ANIMATION, "STOP_SMOKE_ANIM", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_UI, "SESSION_ENDED", NULL_KEY);
                llOwnerSay("The session has ended.");
            }

            // Session object rejected our join (distance too far)
            else if (cmd == "TC_JOIN_REJECTED")
            {
                string reason = llList2String(parts, 1);
                if (reason == "distance")
                    llOwnerSay("Couldn't join: you're too far from the session object. Move closer.");
                else
                    llOwnerSay("Couldn't join the session.");
                g_inSession = FALSE;
            }

            // Session object confirms we joined a session as participant
            else if (cmd == "TC_SESSION_JOINED")
            {
                // TC_SESSION_JOINED|sessionObjectKey|sessionChannel|hostName|strain|quality
                g_sessionObjectKey = (key)llList2String(parts, 1);
                g_inSession        = TRUE;
                g_sessionHost      = llList2String(parts, 3);
                string strain      = llList2String(parts, 4);
                string quality     = llList2String(parts, 5);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SESSION_JOINED|" + g_sessionHost + "|" +
                    (string)g_sessionObjectKey, NULL_KEY);
                llOwnerSay("Joined " + g_sessionHost + "'s session  -  " +
                           quality + " " + strain + " is going around.");
            }

            // Someone passed to us  -  trigger receive animation
            else if (cmd == "TC_PASS_RECEIVED")
            {
                // TC_PASS_RECEIVED|strain|quality
                string strain  = llList2String(parts, 1);
                string quality = llList2String(parts, 2);
                llMessageLinked(LINK_SET, CHAN_ANIMATION, "PLAY_PASS_RECEIVE", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_SMOKED|" + strain, NULL_KEY);
            }

            // We passed to someone  -  trigger give animation
            else if (cmd == "TC_PASS_GIVEN")
            {
                llMessageLinked(LINK_SET, CHAN_ANIMATION, "PLAY_PASS_GIVE", NULL_KEY);
            }

            // Session object tells us a new member joined (UI notification)
            else if (cmd == "TC_SESSION_MEMBER_JOIN")
            {
                string joinerName = llList2String(parts, 1);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SESSION_MEMBER_JOIN|" + joinerName, NULL_KEY);
            }

            // Session object tells us a member left
            else if (cmd == "TC_SESSION_MEMBER_LEAVE")
            {
                string leaverName = llList2String(parts, 1);
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SESSION_MEMBER_LEAVE|" + leaverName, NULL_KEY);
            }

            // Plug board reports a sale completed
            else if (cmd == "TC_SALE_COMPLETE")
            {
                string salePrice  = llList2String(parts, 1);
                string buyerName  = llList2String(parts, 2);
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_SOLD", NULL_KEY);
                llMessageLinked(LINK_SET, CHAN_IDENTITY, "UPDATE_XP|seller|1", NULL_KEY);
                // Fire notification so player gets an IM even if AFK
                llMessageLinked(LINK_SET, CHAN_UI,
                    "NOTIFY|sale_made|Sale! L$" + salePrice +
                    " from " + buyerName + ".", NULL_KEY);
                llOwnerSay("Sale complete! L$" + salePrice +
                           " has been paid to you.");
            }

            // World object sending a notification to the player
            // TC_NOTIFY|type|message
            else if (cmd == "TC_NOTIFY")
            {
                llMessageLinked(LINK_SET, CHAN_UI,
                    "NOTIFY|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }

            // World object reporting XP earned (e.g. RollingTable after craft)
            // TC_XP_UPDATE|track|amount
            else if (cmd == "TC_XP_UPDATE")
            {
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_XP|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }

            // Session object sending cypher mode turn countdown to this player
            // TC_YOUR_TURN|secondsRemaining|strain
            else if (cmd == "TC_YOUR_TURN")
            {
                llMessageLinked(LINK_SET, CHAN_UI,
                    "YOUR_TURN_COUNTDOWN|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }

            // Session object broadcasting cypher mode change
            // TC_CYPHER_MODE|active|turnSeconds
            else if (cmd == "TC_CYPHER_MODE")
            {
                llMessageLinked(LINK_SET, CHAN_UI,
                    "CYPHER_MODE_CHANGE|" + llList2String(parts, 1) + "|" +
                    llList2String(parts, 2), NULL_KEY);
            }

            // Another player's HUD is passing us something
            else if (cmd == "TC_RECEIVE_PASS")
            {
                // TC_RECEIVE_PASS|itemType|strainName|quality|qty|packager|fromName
                string fromName = llList2String(parts, 6);
                string strain   = llList2String(parts, 2);
                string quality  = llList2String(parts, 3);
                // Add to inventory
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "ADD_ITEM|"     + llList2String(parts,1) + "|" +
                    strain          + "|" +
                    quality         + "|" +
                    llList2String(parts,4) + "|" +
                    llList2String(parts,5), NULL_KEY);
                // Play receive animation
                llMessageLinked(LINK_SET, CHAN_ANIMATION, "PLAY_PASS_RECEIVE", NULL_KEY);
                // Notify UI so it can display the message to the player
                llMessageLinked(LINK_SET, CHAN_UI,
                    "PASS_RECEIVED_NOTIFY|" + fromName + "|" + strain + "|" + quality,
                    NULL_KEY);
            }

            // Rep received from a buyer
            else if (cmd == "TC_REP_GIVEN")
            {
                integer delta = (integer)llList2String(parts,1);
                string  from  = llList2String(parts,2);
                llMessageLinked(LINK_SET, CHAN_IDENTITY,
                    "UPDATE_REP|" + (string)delta, NULL_KEY);
                llOwnerSay(from + " gave you a rep point!");
            }

            // World object requesting filtered inventory (bagging table, jar, etc.)
            // TC_INVENTORY_REQUEST|itemType|requestingObjectKey
            else if (cmd == "TC_INVENTORY_REQUEST")
            {
                string filterType = llList2String(parts, 1);
                string reqObjKey  = llList2String(parts, 2);
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "REQUEST_RAW_INVENTORY|" + filterType + "|" + reqObjKey,
                    NULL_KEY);
            }

            // World object telling HUD to add item to inventory
            // TC_ADD_ITEM|itemType|strainName|quality|qty|packager
            else if (cmd == "TC_ADD_ITEM")
            {
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "ADD_ITEM|"             +
                    llList2String(parts, 1) + "|" +
                    llList2String(parts, 2) + "|" +
                    llList2String(parts, 3) + "|" +
                    llList2String(parts, 4) + "|" +
                    llList2String(parts, 5), NULL_KEY);
            }

            // World object requesting item removal (bagging table consuming flower)
            // TC_REMOVE_ITEM|itemType|strainName|quality|qty|packager
            else if (cmd == "TC_REMOVE_ITEM")
            {
                // Pass 'id' (the object key) through so we can notify it of result
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "REMOVE_ITEM|"          +
                    llList2String(parts, 1) + "|" +
                    llList2String(parts, 2) + "|" +
                    llList2String(parts, 3) + "|" +
                    llList2String(parts, 4) + "|" +
                    llList2String(parts, 5), id);
            }

            // World object consuming a single item type by strain (breeding station)
            // TC_CONSUME_ITEM|itemType|strainName|qty
            else if (cmd == "TC_CONSUME_ITEM")
            {
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "REMOVE_ITEM|"          +
                    llList2String(parts, 1) + "|" +
                    llList2String(parts, 2) + "||" +
                    llList2String(parts, 3) + "|", id);
            }

            // World object requesting raw inventory list (breeding station, etc.)
            // TC_REQUEST_RAW_INVENTORY|itemType
            // Response will be sent back as TC_INVENTORY_DATA on channel 0 to sender
            else if (cmd == "TC_REQUEST_RAW_INVENTORY")
            {
                // Pass sender object key (id) so RAW_INVENTORY handler can relay it back
                llMessageLinked(LINK_SET, CHAN_INVENTORY,
                    "REQUEST_RAW_INVENTORY|" + llList2String(parts, 1) + "|" + (string)id,
                    NULL_KEY);
            }

            // Wrapper box gives wrappers to the player
            // TC_WRAPPER_GIVE|flavor|count|avatarKey
            else if (cmd == "TC_WRAPPER_GIVE")
            {
                string  flavor    = llList2String(parts, 1);
                integer count     = (integer)llList2String(parts, 2);
                key     avatarKey = (key)llList2String(parts, 3);

                if (avatarKey != g_ownerKey) return;
                if (flavor == "") return;
                if (count <= 0) return;

                // Find existing entry for this flavor and update count, or add new entry
                integer found = -1;
                integer wi;
                for (wi = 0; wi < llGetListLength(g_wrapperInventory); wi++)
                {
                    list entry = llParseString2List(llList2String(g_wrapperInventory, wi), ["|"], []);
                    if (llList2String(entry, 0) == flavor)
                        found = wi;
                }

                if (found >= 0)
                {
                    list   entry    = llParseString2List(llList2String(g_wrapperInventory, found), ["|"], []);
                    integer existing = (integer)llList2String(entry, 1);
                    g_wrapperInventory = llListReplaceList(g_wrapperInventory,
                        [flavor + "|" + (string)(existing + count)], found, found);
                }
                else
                {
                    g_wrapperInventory += [flavor + "|" + (string)count];
                }

                // ACK back to the wrapper box on private channel
                llRegionSayTo(id, g_privateChannel, "TC_WRAPPER_ACK");

                // Notify UI so wrapper count display can update
                llMessageLinked(LINK_SET, CHAN_UI,
                    "WRAPPER_ADDED|" + flavor + "|" + (string)count, NULL_KEY);
            }
        }

        // ---- Messages on public session channel ----
        else if (channel == PUBLIC_SESSION_CHAN)
        {
            // Another player's session object is inviting nearby avatars
            if (cmd == "TC_SESSION_INVITE")
            {
                // TC_SESSION_INVITE|hostName|hostKey|sessionObjectKey|strain|quality|sessionChannel
                string hostName  = llList2String(parts, 1);
                key    hostKey   = (key)llList2String(parts, 2);
                key    sessKey   = (key)llList2String(parts, 3);
                string strain    = llList2String(parts, 4);
                string quality   = llList2String(parts, 5);

                // Don't invite ourselves  -  compare by key, not name (names aren't unique)
                if (hostKey == g_ownerKey) return;
                // Don't invite if already in a session
                if (g_inSession) return;

                string brandName = llList2String(parts, 7);
                // Forward to UI to show invite dialog
                llMessageLinked(LINK_SET, CHAN_UI,
                    "SHOW_SESSION_INVITE|" + hostName + "|" +
                    (string)sessKey + "|" + strain + "|" + quality + "|" +
                    brandName, NULL_KEY);
            }
        }
    }
}
