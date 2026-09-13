// GlowInTheDark 2.0 -- colour policies.
//
// Something has to decide what colour a given sector's given lane glows.
// That rule is a "policy". All four land in the same HSV window, so the
// hue/saturation/value range sliders govern every policy identically -- pick
// a moody teal window and the random, texture-keyed and light-keyed policies
// are all moody teal, differing only in what varies within it.

// The HSV window plus the seed. Read once per apply and passed down, rather
// than re-read per sector: a 5000-sector map with four lanes would otherwise
// do 140,000 CVar lookups per apply.
class GITD_Range
{
	double hMin, hMax, sMin, sMax, vMin, vMax;
	uint seed;
	bool lockPlanes;
	bool lightInvert;

	// Refilled in place, not reallocated -- see GITD_Lane.Fill for why.
	clearscope void Fill()
	{
		hMin = GITD_Util.GetF("gitd_hue_min", 0.0);
		hMax = GITD_Util.GetF("gitd_hue_max", 360.0);
		sMin = GITD_Util.GetF("gitd_sat_min", 0.35);
		sMax = GITD_Util.GetF("gitd_sat_max", 0.85);
		vMin = GITD_Util.GetF("gitd_val_min", 0.45);
		vMax = GITD_Util.GetF("gitd_val_max", 1.0);
		seed = uint(GITD_Util.GetI("gitd_seed", 1337));
		lockPlanes = GITD_Util.GetB("gitd_lock_planes", false);
		lightInvert = GITD_Util.GetB("gitd_light_invert", true);
	}

	static GITD_Range FromCVars()
	{
		GITD_Range r = GITD_Range(new("GITD_Range"));
		r.Fill();
		return r;
	}

	// Three independent 0..1 draws from one hash, mapped into the window.
	clearscope Color FromHash(uint h)
	{
		double t1 = GITD_Util.Unit(h);
		double t2 = GITD_Util.Unit(GITD_Util.Hash(h ^ 0x5bf03635));
		double t3 = GITD_Util.Unit(GITD_Util.Hash(h ^ 0x27d4eb2f));

		return GITD_Util.HSV(
			GITD_Util.LerpHue(hMin, hMax, t1),
			GITD_Util.Lerp(sMin, sMax, t2),
			GITD_Util.Lerp(vMin, vMax, t3));
	}

	// One driver value across the whole window -- used by the light policy,
	// where hue, saturation and value should all move together rather than
	// varying independently.
	clearscope Color FromScalar(double t)
	{
		t = clamp(t, 0.0, 1.0);
		return GITD_Util.HSV(
			GITD_Util.LerpHue(hMin, hMax, t),
			GITD_Util.Lerp(sMin, sMax, t),
			GITD_Util.Lerp(vMin, vMax, t));
	}
}

class GITD_Policy
{
	enum EPolicy
	{
		POLICY_FIXED   = 0,
		POLICY_RANDOM  = 1,
		POLICY_TEXTURE = 2,
		POLICY_LIGHT   = 3,
	}

	// planePos is Sector.floor or Sector.ceiling. salt separates the lanes so
	// a sector's floor and ceiling do not land on the same colour by accident
	// -- unless gitd_lock_planes says they should.
	//
	// light is the level the light policy keys on. The handler passes the
	// brightest level it has seen the sector at, not whatever lightlevel reads
	// this instant: a flickering or strobing sector sampled mid-flicker came out
	// a different colour on every apply, so dragging any unrelated slider
	// reshuffled it. -1 reads the sector live, for callers with no history.
	clearscope static Color Resolve(Sector sec, int secIndex, int planePos, int policy,
		Color fixedCol, uint salt, GITD_Range range, int light = -1)
	{
		if (!range) return fixedCol;
		if (range.lockPlanes) salt = 0;

		if (policy == POLICY_RANDOM)
		{
			return range.FromHash(GITD_Util.Mix(uint(secIndex), range.seed, salt));
		}

		if (policy == POLICY_TEXTURE)
		{
			// Locked lanes all key on the FLOOR's material. Zeroing the salt is
			// not enough on its own here: the ceiling lanes hash the ceiling
			// flat, so a room with a different ceiling kept two colours with
			// "All four lanes share one colour" switched on.
			int keyPlane = range.lockPlanes ? Sector.floor : planePos;
			String tn = TexMan.GetName(sec.GetTexture(keyPlane));
			// An empty or missing texture name would hash every such sector to
			// the same colour, which reads as a bug rather than a look. Fall
			// back to the sector index so they scatter instead.
			uint base = tn.Length() > 0
				? GITD_Util.HashString(tn)
				: uint(secIndex);
			return range.FromHash(GITD_Util.Mix(base, range.seed, salt));
		}

		if (policy == POLICY_LIGHT)
		{
			int lvl = (light >= 0) ? light : sec.lightlevel;
			double t = clamp(lvl / 255.0, 0.0, 1.0);
			if (range.lightInvert) t = 1.0 - t;
			return range.FromScalar(t);
		}

		return fixedCol;
	}

	// Is this floor a liquid?
	//
	// TerrainDef.IsLiquid is asked first and stays the authority: it is what a
	// map or a mod's own TERRAIN lump says, and Heretic, Hexen and Strife get
	// their liquids from the engine's terrain.txt that way.
	//
	// It cannot be the only test. The engine's terrain.txt maps floors only in
	// its Heretic, Hexen and Strife blocks -- there is no Doom block -- so in
	// Doom and Doom II every sector read as dry, and the Liquids page and every
	// preset's Liquid() call did nothing at all. The stock Doom liquid flats are
	// matched by name as the fallback. Prefixes, not whole names, so every frame
	// of an animated flat counts. SLIME is spelled out because SLIME13-16 are
	// plain metal floors, not slime.
	clearscope static bool IsLiquidFloor(Sector sec)
	{
		if (!sec) return false;

		let td = sec.GetFloorTerrain(Sector.floor);
		if (td && td.IsLiquid) return true;

		static const String liquidFlats[] =
		{
			"NUKAGE", "FWATER", "SWATER", "LAVA", "BLOOD",
			"SLIME0", "SLIME10", "SLIME11", "SLIME12",
			"RROCK05", "RROCK06", "RROCK07", "RROCK08"
		};

		String tn = TexMan.GetName(sec.GetTexture(Sector.floor));
		int len = tn.Length();
		if (len == 0) return false;

		for (int i = 0; i < liquidFlats.Size(); i++)
		{
			int pl = liquidFlats[i].Length();
			if (len >= pl && tn.Left(pl) ~== liquidFlats[i]) return true;
		}
		return false;
	}
}
