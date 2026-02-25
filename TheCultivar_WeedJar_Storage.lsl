// ================================================================
// THE CULTIVAR — Weed Jar Storage Script
// Version: 1.0
// Lives inside: TC_WeedJar_Standard, TC_WeedJar_Premium
//
// Persistent storage layer for the jar, separate from the HUD's
// inventory. Uses llLinksetData for crash-safe persistence across
// sim restarts and region crossings.
//
// COMMUNICATION:
//   Receives commands from Main on JCHAN_STORAGE (2200)
//   Sends results back to Main on JCHAN_MAIN (2000)
//
// COMMANDS HANDLED:
//   FILL_JAR|strain|quality|grams|packager  — add flower, validate
//   TAKE_FROM_JAR                           — decrement 1g
//   EMPTY_JAR                               — clear all contents
//   SET_ACCESS|mode                         — 0=owner 1=group 2=open
//   REQUEST_CONTENTS                        — resend full state
//
// RESPONSES SENT (on JCHAN_MAIN):
//   CONTENTS_UPDATED|strain|quality|grams|capacity|packager|accessMode|jarType
//   TAKE_OK|strain|quality|gramsRemaining
//   TAKE_FAIL|reason
//   FILL_OK|gramsLoaded|overflow
//   FILL_FAIL|reason
//   EMPTIED|strain|quality|grams|packager
// ================================================================

integer JCHAN_MAIN    = 2000;
integer JCHAN_STORAGE = 2200;

// Jar contents
string  g_strain     = "";
string  g_quality    = "";
string  g_packager   = "";
integer g_grams      = 0;
integer g_capacity   = 28;   // standard = 28g, premium = 56g
integer g_accessMode = 0;    // 0=owner 1=group 2=open
string  g_jarType    = "standard";

// ----------------------------------------------------------------
// Persist all jar data to llLinksetData
// ----------------------------------------------------------------
saveState()
{
    llLinksetDataWrite("jar_strain",   g_strain);
    llLinksetDataWrite("jar_quality",  g_quality);
    llLinksetDataWrite("jar_packager", g_packager);
    llLinksetDataWrite("jar_grams",    (string)g_grams);
    llLinksetDataWrite("jar_capacity", (string)g_capacity);
    llLinksetDataWrite("jar_access",   (string)g_accessMode);
    llLinksetDataWrite("jar_type",     g_jarType);
}

// ----------------------------------------------------------------
// Load jar data from llLinksetData
// ----------------------------------------------------------------
loadState()
{
    string test = llLinksetDataRead("jar_strain");
    if (test != "")
    {
        g_strain     = test;
        g_quality    = llLinksetDataRead("jar_quality");
        g_packager   = llLinksetDataRead("jar_packager");
        g_grams      = (integer)llLinksetDataRead("jar_grams");
        g_capacity   = (integer)llLinksetDataRead("jar_capacity");
        g_accessMode = (integer)llLinksetDataRead("jar_access");
        g_jarType    = llLinksetDataRead("jar_type");
    }
    else
    {
        // Detect jar type from object name if fresh
        string objName = llGetObjectName();
        if (llSubStringIndex(objName, "Premium") != -1)
        {
            g_jarType  = "premium";
            g_capacity = 56;
        }
    }
}

// ----------------------------------------------------------------
// Broadcast current contents to Main for UI/visual updates
// ----------------------------------------------------------------
broadcastContents()
{
    llMessageLinked(LINK_SET, JCHAN_MAIN,
        "CONTENTS_UPDATED|" + g_strain   + "|" + g_quality + "|" +
        (string)g_grams    + "|" + (string)g_capacity + "|" +
        g_packager         + "|" + (string)g_accessMode + "|" +
        g_jarType, NULL_KEY);
}

// ================================================================
default
{
    state_entry()
    {
        loadState();
        broadcastContents();
    }

    on_rez(integer start_param)
    {
        loadState();
        broadcastContents();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            // New owner — clear personal data, keep jar type/capacity
            llLinksetDataDeleteFound("jar_", "");
            g_strain     = "";
            g_quality    = "";
            g_packager   = "";
            g_grams      = 0;
            g_accessMode = 0;
            saveState();
            broadcastContents();
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != JCHAN_STORAGE) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- FILL_JAR|strain|quality|grams|packager ----
        if (cmd == "FILL_JAR")
        {
            string  strain   = llList2String(parts, 1);
            string  quality  = llList2String(parts, 2);
            integer grams    = (integer)llList2String(parts, 3);
            string  packager = llList2String(parts, 4);

            integer space = g_capacity - g_grams;
            if (space <= 0)
            {
                llMessageLinked(LINK_SET, JCHAN_MAIN,
                    "FILL_FAIL|Jar is full (" +
                    (string)g_capacity + "g capacity).", NULL_KEY);
                return;
            }

            // Only one strain at a time — no mixing
            if (g_grams > 0 && g_strain != strain)
            {
                llMessageLinked(LINK_SET, JCHAN_MAIN,
                    "FILL_FAIL|Jar already contains " + g_strain +
                    ". Empty it first.", NULL_KEY);
                return;
            }

            integer toLoad  = grams;
            if (toLoad > space) toLoad = space;
            integer overflow = grams - toLoad;

            g_strain   = strain;
            g_quality  = quality;
            g_packager = packager;
            g_grams   += toLoad;
            saveState();

            llMessageLinked(LINK_SET, JCHAN_MAIN,
                "FILL_OK|" + (string)toLoad + "|" + (string)overflow,
                NULL_KEY);
            broadcastContents();
        }

        // ---- TAKE_FROM_JAR — decrement 1g ----
        else if (cmd == "TAKE_FROM_JAR")
        {
            if (g_grams <= 0)
            {
                llMessageLinked(LINK_SET, JCHAN_MAIN,
                    "TAKE_FAIL|empty", NULL_KEY);
                return;
            }

            g_grams--;
            saveState();

            llMessageLinked(LINK_SET, JCHAN_MAIN,
                "TAKE_OK|" + g_strain + "|" + g_quality + "|" +
                (string)g_grams, NULL_KEY);

            // Clear strain when empty
            if (g_grams <= 0)
            {
                g_strain   = "";
                g_quality  = "";
                g_packager = "";
                saveState();
            }
            broadcastContents();
        }

        // ---- EMPTY_JAR — return all contents, clear ----
        else if (cmd == "EMPTY_JAR")
        {
            string  oldStrain   = g_strain;
            string  oldQuality  = g_quality;
            integer oldGrams    = g_grams;
            string  oldPackager = g_packager;

            g_grams    = 0;
            g_strain   = "";
            g_quality  = "";
            g_packager = "";
            saveState();

            llMessageLinked(LINK_SET, JCHAN_MAIN,
                "EMPTIED|" + oldStrain + "|" + oldQuality + "|" +
                (string)oldGrams + "|" + oldPackager, NULL_KEY);
            broadcastContents();
        }

        // ---- SET_ACCESS|mode ----
        else if (cmd == "SET_ACCESS")
        {
            g_accessMode = (integer)llList2String(parts, 1);
            saveState();
            broadcastContents();
        }

        // ---- REQUEST_CONTENTS — resend current state ----
        else if (cmd == "REQUEST_CONTENTS")
        {
            broadcastContents();
        }
    }
}
