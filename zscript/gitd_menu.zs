// GlowInTheDark -- the main page says whether corners are actually agreeing.
//
// "Seamless corners: On" was true and meaningless: two separate conditions
// switch the agreement off underneath it, and neither said so.
//
//   * a WAVE was running, and corners used to give up whenever one was;
//   * a preset had switched one side of a junction OFF, and an agreement needs
//     two sides -- Bioluminescent and Moss have no wall-from-ceiling lane,
//     Ember no ceiling face, Cathedral neither of the lower two.
//
// The second one is why every wall/ceiling join in the owner's screenshot was a
// hard line while the menu said seamless was on. Both are fixed now, but the
// page should never again claim a thing it is not doing, so it reports.

class GITD_MainMenu : OptionMenu
{
	private OptionMenuItemStaticText status;

	private String LaneWord(String p)
	{
		let c = CVar.FindCVar(p .. "_on");
		let i = CVar.FindCVar(p .. "_intensity");
		bool on = c ? c.GetBool() : true;
		double inten = i ? i.GetFloat() : 1.0;
		return (on && inten > 0.0) ? "on" : "off";
	}

	private String Report()
	{
		let en = CVar.FindCVar("gitd_enabled");
		if (en && !en.GetBool()) return "";

		let seam = CVar.FindCVar("gitd_seamless");
		if (seam && !seam.GetBool()) return "Corners: not agreeing, because the row above is off.";

		let len = CVar.FindCVar("gitd_wave_len");
		let underWave = CVar.FindCVar("gitd_seamless_wave");
		if (len && len.GetFloat() > 0.0 && underWave && !underWave.GetBool())
			return "Corners: NOT agreeing -- this preset runs a wave and the wave row is off.";

		// A junction needs both of its sides drawn.
		bool wf = LaneWord("gitd_wf") == "on", wc = LaneWord("gitd_wc") == "on";
		bool fg = LaneWord("gitd_fg") == "on", cg = LaneWord("gitd_cg") == "on";
		String half = "";
		if (wc != cg) half = "the ceiling join has one side only";
		if (wf != fg) half = (half.Length() > 0) ? "both joins have one side only" : "the floor join has one side only";

		if (half.Length() == 0) return "Corners: agreeing on both joins.";
		return String.Format("Corners: NOT agreeing -- %s;"
			.. " this preset draws one side of it.", half);
	}

	override void Ticker()
	{
		Super.Ticker();
		if (!mDesc) return;

		// Appended once, at the bottom, so nothing on the page moves.
		if (!status)
		{
			status = new("OptionMenuItemStaticText");
			status.Init("", Font.CR_GOLD, false);
			mDesc.mItems.Push(status);
		}
		status.mLabel = Report();
	}
}
