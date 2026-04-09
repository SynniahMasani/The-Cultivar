// ================================================================
// THE CULTIVAR - HUD UI Glow Fix
// Version: GlowFix
// Fixes translucent smoke button and enforces solid glow.
// ================================================================

integer g_smokingActive = FALSE;

setSmokeButtonGlow(integer on)
{
    float glow = 0.0;
    if (on) glow = 0.08; // subtle solid glow

    llSetLinkPrimitiveParamsFast(LINK_THIS,
    [
        PRIM_GLOW, ALL_SIDES, glow,
        PRIM_FULLBRIGHT, ALL_SIDES, on
    ]);
}

default
{
    state_entry()
    {
        setSmokeButtonGlow(FALSE);
    }

    link_message(integer sender, integer num, string msg, key id)
    {
        if (msg == "START_SMOKE_ANIM")
        {
            g_smokingActive = TRUE;
            setSmokeButtonGlow(TRUE);
        }
        else if (msg == "STOP_SMOKE_ANIM")
        {
            g_smokingActive = FALSE;
            setSmokeButtonGlow(FALSE);
        }
    }
}
