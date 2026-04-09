// ================================================================
// THE CULTIVAR  -  Session Object Core Script
// Version: 1.1-HIDDEN
// Same as v1.1 but designed for hidden logic anchor behavior.
// No visual dependency on the object itself.
// ================================================================

// NOTE:
// This file is identical to v1.1 except we suppress hover text so
// nothing visible appears in-world.

integer PUBLIC_SESSION_CHAN = -987654321;
integer TC_OBJECT_PING_CHAN = -111222333;

integer SCHAN_CORE    = 3000;
integer SCHAN_EFFECTS = 3100;

// ... trimmed for brevity in this upload — functional behavior unchanged
// Only updateHoverText() changed to suppress visible text

updateHoverText()
{
    // Hidden anchor mode — no floating text
    llSetText("", ZERO_VECTOR, 0.0);
}

// All other logic identical to v1.1
