// ================================================================
// THE CULTIVAR  -  Stash Box Script
// Version: 1.1
//
// A lockable display container for weed jars and bags.
// Owner drops items in, it reads and displays the contents.
// Visitors can browse what's inside. Owner controls access.
//
// HOW IT WORKS:
//   Owner drops TC_Bag_* or TC_WeedJar_* objects into the box.
//   Box reads its inventory on CHANGED_INVENTORY and builds a
//   display of what's inside, organized by item type and quality.
//   Owner can also use the "Store" button to deposit raw flower
//   directly from their HUD virtual inventory. Stored flower is
//   persisted in linkset data ("stash_v_items") and displayed
//   alongside physical bag/jar objects. Taking a virtual item
//   returns it to the owner's HUD inventory.
//   Visitors can browse. Owner can lock the box.
//
// DISPLAY MODE:
//   The box shows a visual summary via hover text and slot prims.
//   Slot prims (links 2 - 5) light up with quality colors as items
//   are stocked, giving it a jewel-box feel on a shelf.
//
// PRIM LINK STRUCTURE:
//   Link 1 (root)   : Box body
//   Links 2 - 5       : Display window prims (4 visible slots)
//   Link 6          : Lock indicator prim (green=open, red=locked)
//   Link 7          : Particle emitter (faint ambient wisp when stocked)
//
// PERMISSIONS NOTE:
//   Items inside need Transfer permissions if you want to give
//   them to visitors. Copy permissions let you give without losing
//   your own copy  -  good for personal display boxes.
// ================================================================

integer TC_OBJECT_PING_CHAN = -111222333;
integer HOVER_FADE_SECS = 30;

integer DCHAN_OWNER        = -120001;
integer DCHAN_VISITOR      = -120002;
integer DCHAN_ITEM         = -120003;
integer DCHAN_STORE        = -120004;
integer DCHAN_VISITOR_ITEM = -120005;

integer g_listenOwner;
integer g_listenVisitor;
integer g_listenVisitorItem;       // picks specific item to take
integer g_listenItem;
integer g_listenRegister;
integer g_listenStore;
integer g_listenHUD;               // permanent listen on derived HUD channel
integer g_replyChannel = 0;

key     g_ownerKey   = NULL_KEY;
string  g_ownerName  = "";
integer g_hudChannel = 0;
integer g_registered = FALSE;
integer g_locked     = FALSE;

// Contents parsed from inventory
// Stride 4: [invName, displayName, quality, itemCategory]
// itemCategory: "bag" | "jar" | "virtual" | "other"
// For virtual items invName encodes: "virtual|itemType|strain|quality|qty|packager"
list    g_contents;
integer CONT_STRIDE = 4;

// Pending visitor request
key     g_pendingVisitor  = NULL_KEY;
string  g_pendingItemName = "";

// Visitors who have already taken one item this session
// Resets whenever inventory changes
list    g_visitorsTaken = [];

// Pending virtual store (waiting for TC_REMOVE_OK from HUD before committing)
string  g_pendingVirtType    = "";
string  g_pendingVirtStrain  = "";
string  g_pendingVirtQuality = "";
integer g_pendingVirtQty     = 0;
string  g_pendingVirtPackager = "";

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
    g_replyChannel   = (integer)(llFrand(1000000.0) + 1000000) * -1;
    g_listenRegister = llListen(g_replyChannel, "", NULL_KEY, "");
    llRegionSay(TC_OBJECT_PING_CHAN,
        "TC_PING|" + (string)llGetKey() + "|stash_box|" +
        (string)g_replyChannel);
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
// Virtual stash helpers  -  persist flower from HUD inventory
// Format per slot: itemType~strain~quality~qty~packager
// Multiple slots separated by "^", stored under "stash_v_items"
// ----------------------------------------------------------------
list readVirtualStash()
{
    string data = llLinksetDataRead("stash_v_items");
    if (data == "") return [];
    list result;
    list slots = llParseString2List(data, ["^"], []);
    integer i;
    for (i = 0; i < llGetListLength(slots); i++)
    {
        list f = llParseStringKeepNulls(llList2String(slots, i), ["~"], []);
        if (llGetListLength(f) == 5)
            result += f;
    }
    return result;
}

saveVirtualStash(list items)
{
    string serial = "";
    integer i;
    for (i = 0; i < llGetListLength(items); i += 5)
    {
        string slot = llList2String(items, i)   + "~" +
                      llList2String(items, i+1) + "~" +
                      llList2String(items, i+2) + "~" +
                      llList2String(items, i+3) + "~" +
                      llList2String(items, i+4);
        if (serial == "") serial = slot;
        else serial += "^" + slot;
    }
    llLinksetDataWrite("stash_v_items", serial);
}

addToVirtualStash(string itemType, string strain, string quality,
                  integer qty, string packager)
{
    list items = readVirtualStash();
    integer found = -1;
    integer i;
    for (i = 0; i < llGetListLength(items); i += 5)
    {
        if (llList2String(items, i)   == itemType &&
            llList2String(items, i+1) == strain   &&
            llList2String(items, i+2) == quality  &&
            llList2String(items, i+4) == packager)
        {
            found = i;
            i = llGetListLength(items); // break
        }
    }
    if (found != -1)
    {
        integer current = (integer)llList2String(items, found + 3);
        items = llListReplaceList(items, [(string)(current + qty)], found+3, found+3);
    }
    else
    {
        items += [itemType, strain, quality, (string)qty, packager];
    }
    saveVirtualStash(items);
}

// Removes a virtual item identified by its encoded invName key.
// invName format: "virtual|itemType|strain|quality|qty|packager"
removeVirtualItem(string invName)
{
    list kp    = llParseString2List(invName, ["|"], []);
    string iType    = llList2String(kp, 1);
    string iStrain  = llList2String(kp, 2);
    string iQuality = llList2String(kp, 3);
    string iPacker  = llList2String(kp, 5);

    list items = readVirtualStash();
    integer i;
    for (i = 0; i < llGetListLength(items); i += 5)
    {
        if (llList2String(items, i)   == iType    &&
            llList2String(items, i+1) == iStrain  &&
            llList2String(items, i+2) == iQuality &&
            llList2String(items, i+4) == iPacker)
        {
            items = llDeleteSubList(items, i, i + 4);
            saveVirtualStash(items);
            return;
        }
    }
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
            if (llGetListLength(parts) >= 4)
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

    // Jar: TC_WeedJar or TC_Jar  -  read description for strain data
    if (llSubStringIndex(invName, "TC_Jar") == 0 ||
        llSubStringIndex(invName, "TC_WeedJar") == 0)
    {
        return [invName, "mixed", "jar"];
    }

    return [invName, "reggie", "other"];
}

// ----------------------------------------------------------------
// Rebuild contents list from physical inventory + virtual stash
// ----------------------------------------------------------------
rebuildContents()
{
    g_contents = [];

    // Physical SL inventory objects
    integer count = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i;
    for (i = 0; i < count; i++)
    {
        string invName = llGetInventoryName(INVENTORY_OBJECT, i);
        // Skip TC system objects
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

    // Virtual stash items (flower deposited from HUD)
    list vItems = readVirtualStash();
    for (i = 0; i < llGetListLength(vItems); i += 5)
    {
        string iType    = llList2String(vItems, i);
        string iStrain  = llList2String(vItems, i+1);
        string iQuality = llList2String(vItems, i+2);
        string iQty     = llList2String(vItems, i+3);
        string iPacker  = llList2String(vItems, i+4);

        string dname;
        if (iType == "flower_raw")
            dname = iStrain + " " + iQty + "g";
        else
            dname = iStrain + " x" + iQty;

        // Encode all fields into invName so the take handler can decode it
        string vKey = "virtual|" + iType + "|" + iStrain + "|" +
                      iQuality + "|" + iQty + "|" + iPacker;

        g_contents += [vKey, dname, iQuality, "virtual"];
    }
}

// ----------------------------------------------------------------
// Update display slot prims (links 2 - 5) and ambient particles
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
            string  catIcon = "[bag]";
            if (cat == "jar") catIcon = "[jar]";

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
            PRIM_TEXT,  "LOCKED", <0.9, 0.2, 0.2>, 1.0
        ]);
    else
        llSetLinkPrimitiveParamsFast(6, [
            PRIM_COLOR, ALL_SIDES, <0.2, 0.9, 0.3>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.04,
            PRIM_TEXT,  "OPEN", <0.2, 0.9, 0.3>, 1.0
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

    string lockLabel;
    vector lockColor;
    if (g_locked)
    {
        lockLabel = "[LOCKED]";
        lockColor = <0.9, 0.4, 0.4>;
    }
    else
    {
        lockLabel = "[OPEN]";
        lockColor = <0.4, 0.9, 0.4>;
    }

    if (count == 0)
    {
        llSetText("THE CULTIVAR\nStash Box [Empty] " + lockLabel +
                  "\nOwner: " + g_ownerName,
                  lockColor, 0.8);
        return;
    }

    // Count by category
    integer bags = 0; integer jars = 0; integer virtuals = 0;
    integer i;
    for (i = 0; i < count; i++)
    {
        string cat = llList2String(g_contents, i * CONT_STRIDE + 3);
        if (cat == "bag")         bags++;
        else if (cat == "jar")    jars++;
        else if (cat == "virtual") virtuals++;
    }

    string contents = "";
    if (bags > 0)
    {
        string bagPl = "";
        if (bags > 1) bagPl = "s";
        contents += (string)bags + " bag" + bagPl;
    }
    if (jars > 0)
    {
        if (contents != "") contents += " | ";
        string jarPl = "";
        if (jars > 1) jarPl = "s";
        contents += (string)jars + " jar" + jarPl;
    }
    if (virtuals > 0)
    {
        if (contents != "") contents += " | ";
        contents += (string)virtuals + " stash'd";
    }

    llSetText("THE CULTIVAR\nStash Box " + lockLabel + "\n" +
              contents + "\nOwner: " + g_ownerName,
              lockColor, 1.0);
}

// ----------------------------------------------------------------
// OWNER MENU
// ----------------------------------------------------------------
showOwnerMenu()
{
    if (g_listenOwner) llListenRemove(g_listenOwner);
    g_listenOwner = llListen(DCHAN_OWNER, "", g_ownerKey, "");

    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    string itemPl = "";
    if (count != 1) itemPl = "s";
    string lockStatus = "UNLOCKED  -  visitors can view";
    if (g_locked) lockStatus = "LOCKED  -  visitors can't browse";
    string lockBtn = "Lock";
    if (g_locked) lockBtn = "Unlock";
    llDialog(g_ownerKey,
        "=== YOUR STASH BOX ===\n" +
        (string)count + " item" + itemPl + " stored\n" +
        lockStatus,
        [lockBtn, "View Contents", "Take Item", "Store", "Close"],
        DCHAN_OWNER);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// CONTENTS LIST  -  shown to owner or visitor
// ----------------------------------------------------------------
showContentsList(key viewer, integer ownerView)
{
    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    if (count == 0)
    {
        if (ownerView)
            llRegionSayTo(viewer, 0,
                "The stash box is empty.\n" +
                "Use 'Store' from the menu to deposit flower from your HUD,\n" +
                "or drag TC_Bag_* / TC_WeedJar_* objects into the box via Edit.");
        else
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
        string catIcon = "[bag]";
        if (cat == "jar") catIcon = "[jar]";
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
// STORE MENU  -  owner picks flower to deposit from HUD inventory
// invData is the raw TC_INVENTORY_DATA payload (flower_raw slots)
// ----------------------------------------------------------------
showStoreMenu(string invData)
{
    if (invData == "")
    {
        llRegionSayTo(g_ownerKey, 0,
            "No flower in your inventory to stash. Harvest some first.");
        return;
    }

    list   slots   = llParseString2List(invData, ["^"], []);
    list   buttons;
    string menuText = "=== STASH FLOWER ===\nChoose what to store:\n\n";
    list qualNames  = ["reggie","mids","loud","exotic"];
    list qualLabels = ["[R]","[M]","[L]","[E]"];

    integer i;
    for (i = 0; i < llGetListLength(slots) && llGetListLength(buttons) < 9; i++)
    {
        list fields = llParseStringKeepNulls(llList2String(slots, i), ["~"], []);
        if (llGetListLength(fields) < 4) jump skip_ss;
        if (llList2String(fields, 0) != "flower_raw") jump skip_ss;

        string iStrain  = llList2String(fields, 1);
        string iQuality = llList2String(fields, 2);
        integer iQty    = (integer)llList2String(fields, 3);
        if (iQty <= 0) jump skip_ss;

        integer qIdx   = llListFindList(qualNames, [iQuality]);
        string  qLabel = llList2String(qualLabels, qIdx);
        buttons  += [llGetSubString(iStrain, 0, 10)];
        menuText += qLabel + " " + iStrain + "  -  " + (string)iQty + "g\n";
        @skip_ss;
    }

    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(g_ownerKey, 0,
            "No raw flower in your inventory to stash.");
        return;
    }

    buttons += ["Cancel"];

    if (g_listenStore) llListenRemove(g_listenStore);
    g_listenStore = llListen(DCHAN_STORE, "", g_ownerKey, "");
    llDialog(g_ownerKey, menuText, buttons, DCHAN_STORE);
    llSetTimerEvent(30.0);

    // Cache raw data so the response handler can match the selection
    llLinksetDataWrite("stash_temp_inv", invData);
}

// ----------------------------------------------------------------
// VISITOR MENU  -  only shown if unlocked
// ----------------------------------------------------------------
showVisitorMenu(key visitor)
{
    if (g_listenVisitor) llListenRemove(g_listenVisitor);
    g_listenVisitor = llListen(DCHAN_VISITOR, "", visitor, "");

    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    string visItemPl = "";
    if (count != 1) visItemPl = "s";

    // Count physical (giveable) items
    integer physCount = 0;
    integer i;
    for (i = 0; i < count; i++)
    {
        string cat = llList2String(g_contents, i * CONT_STRIDE + 3);
        if (cat == "bag" || cat == "jar") physCount++;
    }

    list buttons = ["View Contents", "Close"];
    if (physCount > 0)
        buttons = ["View Contents", "Take One", "Close"];

    llDialog(visitor,
        "=== " + g_ownerName + "'s Stash Box ===\n" +
        (string)count + " item" + visItemPl + " inside\n" +
        "Browse or grab something.",
        buttons, DCHAN_VISITOR);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
// VISITOR ITEM PICKER  -  shows physical items for visitor to take
// ----------------------------------------------------------------
showVisitorItemPicker(key visitor)
{
    integer count = llGetListLength(g_contents) / CONT_STRIDE;
    list   buttons;
    string menuText = "=== TAKE ONE ===\n" +
                      g_ownerName + "'s stash\nChoose an item:\n\n";
    integer i;
    for (i = 0; i < count && llGetListLength(buttons) < 9; i++)
    {
        string cat    = llList2String(g_contents, i * CONT_STRIDE + 3);
        string dname  = llList2String(g_contents, i * CONT_STRIDE + 1);
        if (cat == "bag" || cat == "jar")
        {
            buttons  += [llGetSubString(dname, 0, 11)];
            menuText += dname + "\n";
        }
    }
    if (llGetListLength(buttons) == 0)
    {
        llRegionSayTo(visitor, 0, "Nothing left to take.");
        return;
    }
    buttons += ["Cancel"];

    g_pendingVisitor = visitor;
    if (g_listenVisitorItem) llListenRemove(g_listenVisitorItem);
    // Key the listener to g_pendingVisitor to prevent channel injection by others
    g_listenVisitorItem = llListen(DCHAN_VISITOR_ITEM, "", g_pendingVisitor, "");
    llDialog(visitor, menuText, buttons, DCHAN_VISITOR_ITEM);
    llSetTimerEvent(30.0);
}

// ----------------------------------------------------------------
closeAllListens()
{
    if (g_listenRegister)    { llListenRemove(g_listenRegister);    g_listenRegister    = 0; }
    if (g_listenOwner)       { llListenRemove(g_listenOwner);       g_listenOwner       = 0; }
    if (g_listenVisitor)     { llListenRemove(g_listenVisitor);     g_listenVisitor     = 0; }
    if (g_listenVisitorItem) { llListenRemove(g_listenVisitorItem); g_listenVisitorItem = 0; }
    if (g_listenItem)        { llListenRemove(g_listenItem);        g_listenItem        = 0; }
    if (g_listenStore)       { llListenRemove(g_listenStore);       g_listenStore       = 0; }
    // g_listenHUD is permanent  -  never closed here
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey   = llGetOwner();
        g_ownerName  = llGetDisplayName(g_ownerKey);
        g_hudChannel = deriveHUDChannel(g_ownerKey);
        // Permanent listen so TC_INVENTORY_DATA and TC_REMOVE_OK/FAIL arrive
        if (g_listenHUD) llListenRemove(g_listenHUD);
        g_listenHUD = llListen(g_hudChannel, "", NULL_KEY, "");
        rebuildContents();
        updateDisplay();
        updateHoverText();
        llSetTimerEvent(HOVER_FADE_SECS);
    }

    on_rez(integer start_param) { llResetScript(); }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llLinksetDataReset();
            llResetScript();
        }
        if (change & CHANGED_INVENTORY)
        {
            // Reset per-session visitor take tracking on every restock
            g_visitorsTaken = [];
            rebuildContents();
            updateDisplay();
            updateHoverText();
            llSetTimerEvent(HOVER_FADE_SECS);
        }
    }

    timer()
    {
        // Idle fade: no dialog listens open — fade hover text and stop timer
        if (!g_listenOwner && !g_listenVisitor && !g_listenVisitorItem &&
            !g_listenItem && !g_listenRegister && !g_listenStore)
        {
            integer count = llGetListLength(g_contents) / CONT_STRIDE;
            string lockLabel;
            vector lockColor;
            if (g_locked) { lockLabel = "[LOCKED]"; lockColor = <0.9, 0.4, 0.4>; }
            else           { lockLabel = "[OPEN]";   lockColor = <0.4, 0.9, 0.4>; }
            if (count == 0)
                llSetText("THE CULTIVAR\nStash Box [Empty] " + lockLabel +
                          "\nOwner: " + g_ownerName,
                          lockColor, 0.0);
            else
                llSetText("THE CULTIVAR\nStash Box " + lockLabel +
                          "\nOwner: " + g_ownerName,
                          lockColor, 0.0);
            llSetTimerEvent(0.0);
            return;
        }

        closeAllListens();
        g_pendingVisitor  = NULL_KEY;
        g_pendingItemName = "";
        if (!g_registered)
            llRegionSayTo(g_ownerKey, 0,
                "Couldn't reach your HUD. Make sure it's worn.");
        llSetTimerEvent(HOVER_FADE_SECS);
    }

    touch_start(integer nd)
    {
        updateHoverText();
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

        if (channel == g_replyChannel && cmd == "TC_REGISTER")
        {
            key regOwner = (key)llList2String(parts, 1);
            if (regOwner != g_ownerKey) return;
            g_hudChannel = (integer)llList2String(parts, 2);
            g_registered = TRUE;
            if (g_listenRegister) { llListenRemove(g_listenRegister); g_listenRegister = 0; }
            llSetTimerEvent(0.0);

            string intent = llLinksetDataRead("stash_intent");
            llLinksetDataDelete("stash_intent");
            if (intent == "owner_menu")
                showOwnerMenu();
            else if (intent == "store_menu")
                llRegionSayTo(g_ownerKey, g_hudChannel,
                    "TC_INVENTORY_REQUEST|flower_raw|" + (string)llGetKey());
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
                llOwnerSay("Stash box unlocked  -  visitors can browse.");
            }
            else if (msg == "View Contents" || msg == "Take Item")
                showContentsList(g_ownerKey, TRUE);

            else if (msg == "Store")
            {
                llLinksetDataWrite("stash_intent", "store_menu");
                pingHUD();
            }
        }

        else if (channel == DCHAN_ITEM && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenItem) { llListenRemove(g_listenItem); g_listenItem = 0; }

            if (msg == "Back")  { showOwnerMenu(); return; }
            if (msg == "Close") return;

            // Match truncated name to inventory item (physical or virtual)
            integer count = llGetListLength(g_contents) / CONT_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string dname   = llList2String(g_contents, i * CONT_STRIDE + 1);
                string invName = llList2String(g_contents, i * CONT_STRIDE + 0);
                if (llGetSubString(dname, 0, 11) == msg)
                {
                    if (llSubStringIndex(invName, "virtual|") == 0)
                    {
                        // Virtual stash item  -  return grams to HUD
                        list kp       = llParseString2List(invName, ["|"], []);
                        string iType  = llList2String(kp, 1);
                        string iStrain= llList2String(kp, 2);
                        string iQual  = llList2String(kp, 3);
                        string iQty   = llList2String(kp, 4);
                        string iPack  = llList2String(kp, 5);
                        removeVirtualItem(invName);
                        llRegionSayTo(g_ownerKey, g_hudChannel,
                            "TC_ADD_ITEM|" + iType + "|" + iStrain + "|" +
                            iQual + "|" + iQty + "|" + iPack);
                        llOwnerSay("Retrieved " + iQty + "g of " + iQual +
                                   " " + iStrain + " from stash.");
                        rebuildContents();
                        updateDisplay();
                        updateHoverText();
                    }
                    else if (llGetInventoryType(invName) == INVENTORY_OBJECT)
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
            else if (msg == "Take One")
            {
                // One-per-session check
                if (llListFindList(g_visitorsTaken, [(string)id]) != -1)
                {
                    llRegionSayTo(id, 0,
                        "You already grabbed from this stash.");
                    return;
                }
                showVisitorItemPicker(id);
            }
        }

        else if (channel == DCHAN_VISITOR_ITEM)
        {
            llSetTimerEvent(0.0);
            if (g_listenVisitorItem)
            {
                llListenRemove(g_listenVisitorItem);
                g_listenVisitorItem = 0;
            }

            // Only respond to the visitor we opened the picker for
            if (id != g_pendingVisitor) return;
            g_pendingVisitor = NULL_KEY;

            if (msg == "Cancel") return;

            // Match truncated label to a physical item and give it
            integer count = llGetListLength(g_contents) / CONT_STRIDE;
            integer i;
            for (i = 0; i < count; i++)
            {
                string cat     = llList2String(g_contents, i * CONT_STRIDE + 3);
                string dname   = llList2String(g_contents, i * CONT_STRIDE + 1);
                string invName = llList2String(g_contents, i * CONT_STRIDE + 0);
                if ((cat == "bag" || cat == "jar") &&
                    llGetSubString(dname, 0, 11) == msg)
                {
                    if (llGetInventoryType(invName) == INVENTORY_OBJECT)
                    {
                        llGiveInventory(id, invName);
                        g_visitorsTaken += [(string)id];
                        llRegionSayTo(id, 0,
                            "Enjoy the " + dname + ". ?");
                    }
                    else
                    {
                        llRegionSayTo(id, 0,
                            "That item is no longer available.");
                    }
                    return;
                }
            }
            llRegionSayTo(id, 0, "Couldn't find that item. Try again.");
        }

        // ---- Store picker response ----
        else if (channel == DCHAN_STORE && id == g_ownerKey)
        {
            llSetTimerEvent(0.0);
            if (g_listenStore) { llListenRemove(g_listenStore); g_listenStore = 0; }

            if (msg == "Cancel") return;

            string tempInv = llLinksetDataRead("stash_temp_inv");
            llLinksetDataDelete("stash_temp_inv");
            list slots = llParseString2List(tempInv, ["^"], []);

            integer si;
            for (si = 0; si < llGetListLength(slots); si++)
            {
                list fields = llParseStringKeepNulls(llList2String(slots, si), ["~"], []);
                if (llGetListLength(fields) < 5) jump skip_sp;
                if (llList2String(fields, 0) != "flower_raw") jump skip_sp;

                string iStrain = llList2String(fields, 1);
                if (llGetSubString(iStrain, 0, 10) == msg)
                {
                    string  iQuality = llList2String(fields, 2);
                    integer iQty     = (integer)llList2String(fields, 3);
                    string  iPacker  = llList2String(fields, 4);

                    if (iQty <= 0)
                    {
                        llRegionSayTo(g_ownerKey, 0, "Nothing to stash.");
                        return;
                    }

                    // Save pending data; commit only after HUD confirms removal
                    g_pendingVirtType     = "flower_raw";
                    g_pendingVirtStrain   = iStrain;
                    g_pendingVirtQuality  = iQuality;
                    g_pendingVirtQty      = iQty;
                    g_pendingVirtPackager = iPacker;

                    llRegionSayTo(g_ownerKey, g_hudChannel,
                        "TC_REMOVE_ITEM|flower_raw|" + iStrain + "|" +
                        iQuality + "|" + (string)iQty + "|" + iPacker);
                    return;
                }
                @skip_sp;
            }
            llRegionSayTo(g_ownerKey, 0, "Couldn't find that item. Try again.");
        }

        // ---- HUD replies (inventory data, remove confirmation) ----
        else if (channel == g_hudChannel)
        {
            if (cmd == "TC_INVENTORY_DATA")
            {
                // HUD is responding to our TC_INVENTORY_REQUEST for the store menu
                showStoreMenu(llList2String(parts, 1));
            }
            else if (cmd == "TC_REMOVE_OK")
            {
                if (g_pendingVirtType == "") return;
                // HUD confirmed the removal  -  now save to stash
                addToVirtualStash(g_pendingVirtType, g_pendingVirtStrain,
                                  g_pendingVirtQuality, g_pendingVirtQty,
                                  g_pendingVirtPackager);
                llOwnerSay("Stashed " + (string)g_pendingVirtQty + "g of " +
                           g_pendingVirtQuality + " " + g_pendingVirtStrain + ".");
                g_pendingVirtType = "";
                rebuildContents();
                updateDisplay();
                updateHoverText();
            }
            else if (cmd == "TC_REMOVE_FAIL")
            {
                g_pendingVirtType = "";
                llRegionSayTo(g_ownerKey, 0,
                    "Couldn't stash that item  -  not enough in your inventory.");
            }
        }
    }
}
