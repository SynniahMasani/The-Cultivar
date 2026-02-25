// ================================================================
// THE CULTIVAR — Stash Box Script
// Version: 1.0
//
// A lockable display container for weed jars and bags.
// Owner drops items in, it reads and displays the contents.
// Visitors can browse what's inside. Owner controls access.
//
// HOW IT WORKS:
//   Owner drops TC_Bag_* or TC_WeedJar_* objects into the box.
//   Box reads its inventory on CHANGED_INVENTORY and builds a
//   display of what's inside, organized by item type and quality.
//   Visitors can browse. If unlocked, they can request items
//   (owner gets a notification and can approve or decline).
//   Owner can lock the box — no visitor interaction at all.
//
// DISPLAY MODE:
//   The box shows a visual summary via hover text and slot prims.
//   Slot prims (links 2–5) light up with quality colors as items
//   are stocked, giving it a jewel-box feel on a shelf.
//
// PRIM LINK STRUCTURE:
//   Link 1 (root)   : Box body
//   Links 2–5       : Display window prims (4 visible slots)
//   Link 6          : Lock indicator prim (green=open, red=locked)
//   Link 7          : Particle emitter (faint ambient wisp when stocked)
//
// PERMISSIONS NOTE:
//   Items inside need Transfer permissions if you want to give
//   them to visitors. Copy permissions let you give without losing
//   your own copy — good for personal display boxes.
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;

integer DCHAN_OWNER   = -120001;
integer DCHAN_VISITOR = -120002;
integer DCHAN_ITEM    = -120003;

integer g_listenOwner;
integer g_listenVisitor;
integer g_listenItem;
integer g_listenRegister;

key     g_ownerKey   = NULL_KEY;
string  g_ownerName  = "";
integer g_hudChannel = 0;
integer g_registered = FALSE;
integer g_locked     = FALSE;

// Contents parsed from inventory
// Stride 4: [invName, displayName, quality, itemCategory]
// itemCategory: "bag" | "jar" | "other"
list    g_contents;
integer CONT_STRIDE = 4;

// Pending visitor request
key     g_pendingVisitor  = NULL_KEY;
string  g_pendingItemName = "";

// ----------------------------------------------------------------
integer deriveHUDChannel(key id)
{
    string h = llGetSubString((string)id, 0, 6);
    h = llDumpList2String(llParseString2List(h, ["-"], []), "");
    return (integer)("0x" + h) * -1;
}

pingHUD()
{
    g_registered = FALSE;
    if (g_listenRegister) llListenRemove(g_listenRegister);
    g_listenRegister = llListen(0, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|stash_box");
    llSetTimerEvent(8.0);
}

vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0, 0.85, 0.2>;
    if (quality == "loud")   return <0.2, 0.85, 0.3>;
    if (quality == "exotic") return <0.7, 0.3,  1.0>;
    if (quality == "mixed")  return <0.6, 0.6,  0.8>;
    return <0.55, 0.45, 0.3>;
}

// ----------------------------------------------------------------
// Parse inventory name to extract quality and category
// Returns [displayName, quality, category]
// ----------------------------------------------------------------
list parseItemName(string invName)
{
    // Bag: TC_Bag_[Size]:[strain]:[quality]:[packager]:[weight]g
    if (llSubStringIndex(invName, "TC_Bag_") == 0)
    {
        integer colonIdx = llSubStringIndex(invName, ":");
        if (colonIdx != -1)
        {
            list parts = llParseString2List(
                llGetSubString(invName, colonIdx + 1, -1), [":"], []);
            if (llGetListLength(parts) >= 3)
            {
                string strain   = llList2String(parts, 0);
                string quality  = llList2String(parts, 1);
                string weight   = llList2String(parts, 3);
                // Get size from "TC_Bag_[Size]" prefix
                string sizeStr  = llGetSubString(invName, 7, colonIdx - 1);
                return [sizeStr + " of " + strain + " " + weight,
                        quality, "bag"];
            }
        }
        return [invName, "reggie", "bag"];
    }

    // Jar: TC_WeedJar or TC_Jar — read description for strain data
    if (llSubStringIndex(invName, "TC_Jar") == 0 ||
        llSubStringIndex(invName, "TC_WeedJar") == 0)
    {
        return [invName, "mixed", "jar"];
    }

    return [invName, "reggie", "other"];
}

// ----------------------------------------------------------------
// Rebuild contents list from inventory
// ----------------------------------------------------------------
rebuildContents()
{
    g_contents = [];
    integer count = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i;
    for (i = 0; i < count; i++)
    {
        string invName = llGetInventoryName(INVENTORY_OBJECT, i);
        // Skip the session object and other TC_ system objects
        if (llSubStringIndex(invName, "TC_Session") == 0) jump skip;
        if (llSubStringIndex(invName, "TC_Smoke")   == 0) jump skip;

        list parsed = parseItemName(invName);
        g_contents += [
            invName,
            llList2String(parsed, 0),  // display name
            llList2String(parsed, 1),  // quality
            llList2String(parsed, 2)   // category
        ];
        @skip;
    }
}

// ----------------------------------------------------------------
// Update display slot prims (links 2–5) and ambient particles
// ----------------------------------------------------------------
updateDisplay()
{
    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    integer i;

    // Update the 4 visible slot prims
    for (i = 0; i < 4; i++)
    {
        integer linkNum = i + 2;
        if (i < count)
        {
            string  quality = llList2String(g_contents, i * CONT_STRIDE + 2);
            vector  col     = qualColor(quality);
            string  dname   = llList2String(g_contents, i * CONT_STRIDE + 1);
            string  cat     = llList2String(g_contents, i * CONT_STRIDE + 3);
            string  catIcon = (cat == "jar") ? "🫙" : "📦";

            llSetLinkPrimitiveParamsFast(linkNum, [
                PRIM_COLOR, ALL_SIDES, col, 1.0,
                PRIM_GLOW,  ALL_SIDES, 0.07,
                PRIM_TEXT,  catIcon + " " + llGetSubString(dname, 0, 18),
                            col, 0.9
            ]);
        }
        else
        {
            // Empty slot
            llSetLinkPrimitiveParamsFast(linkNum, [
                PRIM_COLOR, ALL_SIDES, <0.25, 0.25, 0.25>, 0.5,
                PRIM_GLOW,  ALL_SIDES, 0.0,
                PRIM_TEXT,  "", ZERO_VECTOR, 0.0
            ]);
        }
    }

    // If more than 4 items, indicate overflow on last slot
    if (count > 4)
        llSetLinkPrimitiveParamsFast(5, [
            PRIM_TEXT, "+ " + (string)(count - 3) + " more...",
                       <0.8, 0.8, 0.8>, 0.8
        ]);

    // Lock indicator (link 6)
    if (g_locked)
        llSetLinkPrimitiveParamsFast(6, [
            PRIM_COLOR, ALL_SIDES, <0.9, 0.2, 0.2>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.05,
            PRIM_TEXT,  "🔒", <0.9, 0.2, 0.2>, 1.0
        ]);
    else
        llSetLinkPrimitiveParamsFast(6, [
            PRIM_COLOR, ALL_SIDES, <0.2, 0.9, 0.3>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.04,
            PRIM_TEXT,  "🔓", <0.2, 0.9, 0.3>, 1.0
        ]);

    // Ambient particles when stocked (link 7)
    if (count > 0)
    {
        // Find the "best" quality present for particle color
        string bestQuality = "reggie";
        list qualRank = ["reggie", "mids", "loud", "exotic"];
        for (i = 0; i < count; i++)
        {
            string q = llList2String(g_contents, i * CONT_STRIDE + 2);
            if (llListFindList(qualRank, [q]) >
                llListFindList(qualRank, [bestQuality]))
                bestQuality = q;
        }
        vector col = qualColor(bestQuality);
        llLinkParticleSystem(7, [
            PSYS_PART_FLAGS,           PSYS_PART_INTERP_COLOR_MASK |
                                       PSYS_PART_INTERP_SCALE_MASK |
                                       PSYS_PART_EMISSIVE_MASK,
            PSYS_SRC_PATTERN,          PSYS_SRC_PATTERN_ANGLE_CONE,
            PSYS_PART_START_COLOR,     col,
            PSYS_PART_END_COLOR,       <0.9, 0.9, 0.9>,
            PSYS_PART_START_ALPHA,     0.15,
            PSYS_PART_END_ALPHA,       0.0,
            PSYS_PART_START_SCALE,     <0.01, 0.01, 0.0>,
            PSYS_PART_END_SCALE,       <0.004, 0.004, 0.0>,
            PSYS_PART_MAX_AGE,         4.0,
            PSYS_SRC_BURST_RATE,       2.5,
            PSYS_SRC_BURST_PART_COUNT, 1,
            PSYS_SRC_BURST_SPEED_MIN,  0.005,
            PSYS_SRC_BURST_SPEED_MAX,  0.015,
            PSYS_SRC_ANGLE_BEGIN,      0.0,
            PSYS_SRC_ANGLE_END,        0.15
        ]);
    }
    else
    {
        llLinkParticleSystem(7, []);
    }
}

// ----------------------------------------------------------------
// Main hover text
// ----------------------------------------------------------------
updateHoverText()
{
    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    string  lockStr = g_locked ? " 🔒" : "";
    if (count == 0)
    {
        llSetText("THE CULTIVAR\nStash Box [Empty]" + lockStr +
                  "\nOwner: " + g_ownerName,
                  <0.5, 0.5, 0.5>, 0.8);
        return;
    }

    // Count by category
    integer bags = 0; integer jars = 0;
    integer i;
    for (i = 0; i < count; i++)
    {
        string cat = llList2String(g_contents, i * CONT_STRIDE + 3);
        if (cat == "bag") bags++;
        else if (cat == "jar") jars++;
    }

    string contents = "";
    if (bags > 0) contents += (string)bags + " bag" + (bags > 1 ? "s" : "");
    if (jars > 0)
    {
        if (contents != "") contents += "  •  ";
        contents += (string)jars + " jar" + (jars > 1 ? "s" : "");
    }

    llSetText("THE CULTIVAR\nStash Box" + lockStr + "\n" +
              contents + "\nOwner: " + g_ownerName,
              <0.4, 0.9, 0.4>, 1.0);
}

// ----------------------------------------------------------------
// OWNER MENU
// ----------------------------------------------------------------
showOwnerMenu()
{
    if (g_listenOwner) llListenRemove(g_listenOwner);
    g_listenOwner = llListen(DCHAN_OWNER, "", g_ownerKey, "");

    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    llDialog(g_ownerKey,
        "=== YOUR STASH BOX ===\n" +
        (string)count + " item" + (count != 1 ? "s" : "") + " stored\n" +
        (g_locked ? "LOCKED — visitors can't browse" :
                    "UNLOCKED — visitors can view"),
        [g_locked ? "Unlock" : "Lock",
         "View Contents", "Take Item", "Close"],
        DCHAN_OWNER);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// CONTENTS LIST — shown to owner or visitor
// ----------------------------------------------------------------
showContentsList(key viewer, integer ownerView)
{
    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    if (count == 0)
    {
        llRegionSayTo(viewer, 0, "The stash box is empty.");
        return;
    }

    string msg = "=== STASH BOX CONTENTS ===\n";
    integer i;
    for (i = 0; i < count; i++)
    {
        string dname   = llList2String(g_contents, i * CONT_STRIDE + 1);
        string quality = llList2String(g_contents, i * CONT_STRIDE + 2);
        string cat     = llList2String(g_contents, i * CONT_STRIDE + 3);
        string catIcon = (cat == "jar") ? "🫙" : "📦";
        msg += catIcon + " " + quality + " " + dname + "\n";
    }

    if (ownerView)
    {
        // Owner sees item picker to take things back
        list   buttons;
        integer j;
        for (j = 0; j < count && j < 9; j++)
        {
            string dname = llList2String(g_contents, j * CONT_STRIDE + 1);
            buttons += [llGetSubString(dname, 0, 11)];
        }
        buttons += ["Back", "Close"];
        if (g_listenItem) llListenRemove(g_listenItem);
        g_listenItem = llListen(DCHAN_ITEM, "", g_ownerKey, "");
        llDialog(g_ownerKey, msg, buttons, DCHAN_ITEM);
    }
    else
    {
        // Visitor just sees a text read-out
        llRegionSayTo(viewer, 0, msg);
    }
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// VISITOR MENU — only shown if unlocked
// ----------------------------------------------------------------
showVisitorMenu(key visitor)
{
    if (g_listenVisitor) llListenRemove(g_listenVisitor);
    g_listenVisitor = llListen(DCHAN_VISITOR, "", visitor, "");

    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    llDialog(visitor,
        "=== " + g_ownerName + "'s Stash Box ===\n" +
        (string)count + " item" + (count != 1 ? "s" : "") + " inside\n" +
        "Touch to browse contents.",
        ["View Contents", "Close"], DCHAN_VISITOR);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenOwner)   { llListenRemove(g_listenOwner);   g_listenOwner   = 0; }
    if (g_listenVisitor) { llListenRemove(g_listenVisitor); g_listenVisitor = 0; }
    if (g_listenItem)    { llListenRemove(g_listenItem);    g_listenItem    = 0; }
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey   = llGetOwner();
        g_ownerName  = llKey2Name(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);
        if (g_listenRegister) llListenRemove(g_listenRegister);
        g_listenRegister = llListen(0, "", NULL_KEY, "");
        rebuildContents();
        updateDisplay();
        updateHoverText();
    }

    on_rez(integer start_param) { llResetScript(); }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llLinksetDataDeleteFound("stash_", "");
            llResetScript();
        }
        if (change & CHANGED_INVENTORY)
        {
            rebuildContents();
            updateDisplay();
            updateHoverText();
        }
    }

    timer()
    {
        closeAllListens();
        llSetTimerEvent(0.0);
        g_pendingVisitor  = NULL_KEY;
        g_pendingItemName = "";
        if (!g_registered)
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't reach your HUD. Make sure it's worn.");
    }

    touch_start(integer nd)
    {
        key toucher = llDetectedKey(0);

        if (toucher == g_ownerKey)
        {
            pingHUD();
            llLinksetDataWrite("stash_intent", "owner_menu");
            return;
        }

        if (g_locked)
        {
            llRegionSayTo(toucher, 0,
                g_ownerName + "'s stash box is locked.");
            return;
        }

        showVisitorMenu(toucher);
    }

    listen(integer channel, string name, key id, string msg)
    {
        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (channel == 0 && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            llSetTimerEvent(0.0);

            string intent = llLinksetDataRead("stash_intent");
            llLinksetDataDelete("stash_intent");
            if (intent == "owner_menu") showOwnerMenu();
        }

        else if (channel == DCHAN_OWNER && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenOwner) { llListenRemove(g_listenOwner); g_listenOwner = 0; }

            if (msg == "Lock")
            {
                g_locked = TRUE;
                updateDisplay();
                updateHoverText();
                llOwnerSay("Stash box locked.");
            }
            else if (msg == "Unlock")
            {
                g_locked = FALSE;
                updateDisplay();
                updateHoverText();
                llOwnerSay("Stash box unlocked — visitors can browse.");
            }
            else if (msg == "View Contents")
                showContentsList(g_ownerKey, TRUE);
        }

        else if (channel == DCHAN_ITEM && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenItem) { llListenRemove(g_listenItem); g_listenItem = 0; }

            if (msg == "Back")  { showOwnerMenu(); return; }
            if (msg == "Close") return;

            // Match truncated name to actual inventory item
            integer count = llGetListLength(g_contents) / CONT_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string dname   = llList2String(g_contents, i * CONT_STRIDE + 1);
                string invName = llList2String(g_contents, i * CONT_STRIDE + 0);
                if (llGetSubString(dname, 0, 11) == msg)
                {
                    if (llGetInventoryType(invName) == INVENTORY_OBJECT)
                    {
                        llGiveInventory(g_ownerKey, invName);
                        llOwnerSay("Returned " + dname + " to your inventory.");
                    }
                    return;
                }
            }
        }

        else if (channel == DCHAN_VISITOR)
        {
            llSetTimerEvent(0.0);
            if (g_listenVisitor) { llListenRemove(g_listenVisitor); g_listenVisitor = 0; }

            if (msg == "View Contents")
                showContentsList(id, FALSE);
        }
    }
}
