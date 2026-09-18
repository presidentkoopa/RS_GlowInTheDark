// GlowInTheDark 2.0 -- the engine.
//
// Replaces the 1.1 ACS script entirely. What changed and why:
//
//   1.1 walked sector TAGS 0..99998 calling ACS SetSectorGlow. Tag 0 matches
//   every UNTAGGED sector at once (FSectorTagIterator::Next, p_tags.cpp), and
//   random() is evaluated once per call, so the whole map received a single
//   shared colour -- the per-sector randomisation it advertised never
//   happened. Everything after tag 0 hit only doors and lifts, arriving one
//   per tic over ~47 minutes because its throttle test was inverted.
//
//   This iterates Level.Sectors by index. Every sector is reached, each gets
//   its own colour, and the whole map is done in a handful of tics.
//
// Lane enable/disable is carried by COLOUR ALPHA and height, not by a separate
// flag. Flat glow is gated on `FlatGlowColor.a > 0 && FlatGlowHeight > 0`
// (HWFlat::DrawFlat, hw_flats.cpp): alpha 0 is off. Wall glow is read by
// sector_t::GetWallGlow (p_sectors.cpp), where a colour of exactly 0 hands the
// wall back to its texture's own GLDEFS glow -- which is what a lane switched
// off writes, with a height of 0 beside it. This is why GITD_Util always
// builds colours with alpha 255 -- a colour that loses its alpha silently
// kills a flat lane with no error anywhere.

// One lane's settings, read once per apply rather than per sector.
class GITD_Lane
{
	bool on;
	int policy;
	Color fixedCol;
	double reach;
	int falloff;
	double intensity;
	int farMode;        // 0 off, 1 auto-derived, 2 explicit
	Color farCol;

	// Refill in place rather than returning a fresh object. The apply chain now
	// runs from UiTick so the menu can re-tint the map while the game is
	// paused, and `new` is not something to be doing from there -- once per
	// slider-drag per lane, every drag, for the whole time the menu is open.
	// The handler allocates these once and hands them back here.
	//
	// The lane cvars are named at run time from the prefix, so menu_lint
	// cannot see them read; they are declared for it here instead.
	// LINT-CVARS: gitd_wf_on gitd_wf_policy gitd_wf_color gitd_wf_reach gitd_wf_falloff gitd_wf_intensity gitd_wf_far gitd_wf_farcolor
	// LINT-CVARS: gitd_wc_on gitd_wc_policy gitd_wc_color gitd_wc_reach gitd_wc_falloff gitd_wc_intensity gitd_wc_far gitd_wc_farcolor
	// LINT-CVARS: gitd_fg_on gitd_fg_policy gitd_fg_color gitd_fg_reach gitd_fg_falloff gitd_fg_intensity gitd_fg_far gitd_fg_farcolor
	// LINT-CVARS: gitd_cg_on gitd_cg_policy gitd_cg_color gitd_cg_reach gitd_cg_falloff gitd_cg_intensity gitd_cg_far gitd_cg_farcolor
	// LINT-CVARS: gitd_liq_on gitd_liq_policy gitd_liq_color gitd_liq_reach gitd_liq_falloff gitd_liq_intensity gitd_liq_far gitd_liq_farcolor
	clearscope void Fill(String p)
	{
		on        = GITD_Util.GetB(p .. "_on", true);
		policy    = GITD_Util.GetI(p .. "_policy", 0);
		fixedCol  = GITD_Util.GetC(p .. "_color");
		reach     = GITD_Util.GetF(p .. "_reach", 64.0);
		falloff   = GITD_Util.GetI(p .. "_falloff", 0);
		intensity = GITD_Util.GetF(p .. "_intensity", 1.0);
		farMode   = GITD_Util.GetI(p .. "_far", 1);
		farCol    = GITD_Util.GetC(p .. "_farcolor");
	}

	static GITD_Lane FromCVars(String p)
	{
		GITD_Lane l = GITD_Lane(new("GITD_Lane"));
		l.Fill(p);
		return l;
	}

	// Whether this lane puts anything on screen. Intensity 0 counts as OFF,
	// and has to be caught here: the renderer reads an intensity of 0 or less
	// as "unset" and draws it at 1.0 (HWFlat::DrawFlat and
	// HWWall::RenderTexturedWall), so dragging Intensity to its bottom stop
	// used to jump the glow to full brightness instead of putting it out.
	clearscope bool Drawn()
	{
		return on && intensity > 0.0;
	}

	// The colour this lane fades toward. Auto-derivation is the default
	// because a hand-picked far colour is the single most tedious thing to
	// tune and the derived one is right nearly always.
	//
	// Seamless corners replace an AUTO far colour afterwards: the lane's own
	// colour becomes its far end and the junction colour takes the near slot.
	// An explicit or "off" far colour is left alone. See the seamless block in
	// ApplySector.
	clearscope Color FarFor(Color nearCol)
	{
		if (farMode == 0) return Color(0, 0, 0, 0);
		if (farMode == 2) return farCol;
		return GITD_Util.AutoFar(nearCol);
	}
}

class GITD_Handler : EventHandler
{
	// Sectors per tic during a re-apply. There are two passes (resolve, then
	// blend and write), so a 5000-sector map finishes in six tics with no
	// visible hitch. 1.1's equivalent constant was 2500 but its modulo test was
	// inverted, so it actually managed about one.
	const APPLY_CHUNK = 2000;

	// How often to check whether any lane setting moved. Five tics is about
	// 1/7th of a second -- fast enough that dragging a slider feels live,
	// slow enough that the check itself is free.
	const POLL_TICS = 5;

	// How often to look at the sector state no cvar carries -- light levels
	// and flats. About once a second: a door or a lift changing a floor is not
	// something that needs catching on the tic it happens.
	const WATCH_TICS = 35;

	const PRESET_COUNT = 28;

	// Stored in the per-sector colour tables for a lane that draws nothing
	// there. Pack() never produces a negative, so this cannot collide with a
	// real colour.
	const NO_COLOUR = -1;

	// Per-lane hash salts, so a sector's four lanes do not all land on the
	// same colour under the hashed policies.
	const SALT_WF = 1;
	const SALT_WC = 2;
	const SALT_FG = 3;
	const SALT_CG = 4;

	// The parts of a sector another mod has claimed -- see the claims block
	// below. The same numbers RS_Sweeps' RSS_SectorClaim writes into args[1].
	const CLAIM_WALLS = 1;
	const CLAIM_FLATS = 2;

	// TRANSIENT, EVERY ONE OF THEM. An EventHandler is written into the
	// savegame field by field. The engine now saves every glow field of every
	// plane -- colour, height, far colour, falloff, intensity and the whole
	// flat glow (p_saveg.cpp, the plane serializer) -- so a loaded game comes
	// back looking the way it was saved. These stay transient anyway: a load
	// (or a hub return) comes back with them empty, the signature no longer
	// matches, and the whole map is written again in a few tics. That rebuilds
	// the lanes, ranges and watch history this side keeps, repaints a save made
	// before the engine kept the rest of the glow, and keeps four ints per
	// sector out of every save.
	private ui transient bool applying;
	private ui transient int applyCursor;
	private ui transient uint lastHash;
	private ui transient int pollTimer;
	private ui transient bool wasEnabled;

	private ui transient GITD_Range range;
	private ui transient GITD_Lane laneWF, laneWC, laneFG, laneCG, laneLiq;
	private ui transient bool liqOn, liqWalls;
	private ui transient bool seamless;
	private ui transient bool seamShape;

	// SEAMLESS WALLS.
	//
	// Corners fix the join inside one sector. This fixes the join BETWEEN
	// sectors -- the hard vertical line down a wall where a red room meets a
	// blue one, and the hard edge across a floor where two sectors of the same
	// room carry different colours. A Doom "room" is nearly always several
	// sectors, so without this every step, ledge and doorway is a colour break.
	//
	// Each sector's colour is pulled toward the average of the sectors it
	// shares a line with, so colour flows across the map instead of switching
	// at every boundary.
	//
	// This needs every sector's OWN colour resolved before any of them can be
	// blended -- a sector cannot average against neighbours that have not been
	// worked out yet. Hence two passes, both chunked: resolve, then blend and
	// write. The resolve pass touches no engine state at all.
	private ui transient bool wallSeam;
	private ui transient double wallBlend;
	private ui transient Array<int> baseWF, baseWC, baseFG, baseCG;
	private ui transient Array<bool> liquidAt;
	private ui transient int phase;      // 0 idle, 1 resolving, 2 applying

	// SECTOR STATE THE SETTINGS HASH CANNOT SEE.
	//
	// The light, texture and liquid sources read the map, not a cvar, so the
	// hash never noticed them change: a light switched on by a trigger kept
	// its old colour, and a lift lowering onto nukage kept a dry floor's
	// colour. So the flats and light levels are watched on their own clock.
	//
	// Light is the BRIGHTEST level seen, not the current one. A flickering
	// sector's live level is a random point in its flicker, and keying on it
	// reshuffled that sector's colour on every apply. The cost is that a light
	// switched OFF keeps the colour it had lit.
	private ui transient Array<int> seenLight, seenFloorTex, seenCeilTex;
	private ui transient int watchTimer;
	private ui transient bool lightKeyed, texKeyed;

	// SECTORS ANOTHER MOD HAS CLAIMED.
	//
	// RS_Sweeps' glow effects repaint the rooms a sweep crosses in its own
	// colour, and that colour is meant to stay. This mod repaints every sector
	// on any settings change and on the light and flat watch above, which put
	// GITD's colour straight back within a second. So a sweep leaves a claim,
	// and the apply and ClearAll pass the claimed parts by.
	//
	// NO LINK TO THAT MOD. The claim is a client-side actor of a class looked up
	// from a string at run time, and only base Actor fields are read:
	// args[0] the sector index, args[1] CLAIM_WALLS and/or CLAIM_FLATS. The
	// contract is written out on RSS_SectorClaim in RS_Sweeps. With RS_Sweeps
	// absent the class is not found, nothing is gathered, and every sector is
	// painted exactly as before.
	//
	// UI SCOPE READS PLAY DATA. The claims are client-side actors made on the
	// play side; reading one from here is allowed, because only ui fields are
	// barred to other scopes (scopebarrier.cpp AddFlags), and ThinkerIterator
	// is plain data, callable from any scope. Nothing here writes to them.
	//
	// claimedParts is per sector; claimedHeld counts the claimed parts it holds,
	// so the watch can tell a claim let go from a claim added.
	private ui transient Array<int> claimedParts;
	private ui transient int claimedHeld;

	// Which map the ui side last applied to. See UiTick.
	private ui transient String mapSig;

	// Play side: where a static wave sits. Worked out once per map by
	// FindMapCentre (play scope, because it writes these), then pushed by
	// PushWaveOrigin from UiTick as well as WorldTick -- a play field is
	// readable from the ui side, just not writable. See PushWaveOrigin.
	private transient bool haveCentre;
	private transient Vector3 mapCentre;

	// ---- lifecycle ---------------------------------------------------------

	// A PRESET APPLIES WHEN IT CHANGES, NOT ON EVERY MAP. Apply is a batch of
	// CVar writes; running it on every WorldLoaded (and again from UiTick's
	// first tic) wiped whatever had been tuned on the sliders since the
	// preset was picked, every level. The last-applied index lives in a CVar
	// (gitd_preset_applied) because this handler is rebuilt per map. Shuffle
	// still rolls a new preset per map: it writes gitd_preset, and the sync
	// sees the change.
	override void WorldLoaded(WorldEvent e)
	{
		// A SAVE BRINGS ITS OWN PRESET. The server cvars come back from the
		// savegame -- the preset AND every slider tuned on top of it -- but the
		// applied latches are nosave and still describe whatever was showing
		// before the load. Left alone, a save made on one preset and loaded
		// while another was up read as a preset change, and SyncPreset re-ran
		// the preset over the tuning the save had just restored.
		if (e.IsSaveGame)
		{
			GITD_Util.SetI("gitd_preset_applied", GITD_Util.GetI("gitd_preset", 1));
			GITD_Util.SetI("gitd_texture_applied", GITD_Util.GetI("gitd_texture", 0));
		}

		// Shuffle is for a NEW map. A loaded save or a hub return is the same
		// map you left, and rolling there threw away the look the save kept.
		// Nor does a switched-off mod get a vote.
		//
		// Both rolls are drawn whenever shuffle fires, so every peer consumes
		// the same numbers; every guard here reads peer-identical state.
		if (!e.IsSaveGame && !e.IsReopen
			&& GITD_Util.GetB("gitd_enabled", true)
			&& GITD_Util.GetB("gitd_shuffle", false))
		{
			int rOff = random(1, PRESET_COUNT - 2);
			int rAny = random(1, PRESET_COUNT - 1);
			GITD_Util.SetI("gitd_preset",
				OtherPreset(GITD_Util.GetI("gitd_preset", 1), rOff, rAny));
		}
		SyncPreset();
		PushGlobals();

		// The map centre is known before the first UiTick on this map, so a
		// menu that is already open pushes this map's centre, not the last one's.
		FindMapCentre();
	}

	override void WorldTick()
	{
		if (!GITD_Util.GetB("gitd_enabled", true)) return;
		PushGlobals();
		if (!haveCentre) FindMapCentre();
		PushWaveOrigin();
		SyncPreset();
	}

	// A preset to roll to: never Vanilla+, and never the one already showing.
	// Vanilla+ is skipped because landing on the deliberately restrained one
	// reads as the mod having switched itself off; the current one is skipped
	// because a roll that visibly does nothing reads as a bug.
	//
	// The random numbers come in rather than being drawn here, so the callers
	// can draw them unconditionally. rOff is 1..PRESET_COUNT-2, rAny is
	// 1..PRESET_COUNT-1. Stepping 1..21 places round a ring of the 22
	// non-Vanilla presets can land anywhere except back where it started.
	static int OtherPreset(int cur, int rOff, int rAny)
	{
		int pool = PRESET_COUNT - 1;
		if (cur < 1 || cur >= PRESET_COUNT) return rAny;
		return 1 + (cur - 1 + rOff) % pool;
	}

	// The preset picks the palette, the texture layer picks the surface, and
	// the texture is applied AFTER so it lands on top of whatever the preset
	// chose. A preset writes the texture cvars as part of its own look, so any
	// preset change has to be followed by the texture override again or the
	// chosen texture would silently revert on the next preset switch.
	clearscope static void SyncPreset()
	{
		int want    = GITD_Util.GetI("gitd_preset", 1);
		int wantTex = GITD_Util.GetI("gitd_texture", 0);

		bool presetChanged = (want != GITD_Util.GetI("gitd_preset_applied", -1));
		bool texChanged    = (wantTex != GITD_Util.GetI("gitd_texture_applied", -2));
		if (!presetChanged && !texChanged) return;

		if (presetChanged)
		{
			GITD_Presets.Apply(want);
			GITD_Util.SetI("gitd_preset_applied", want);
		}
		else if (texChanged && wantTex == GITD_Textures.T_PRESET)
		{
			// Back to "from the preset": put back the preset's own grain, flow
			// and cells, and nothing else. GITD_Textures.Apply(T_PRESET) is a
			// no-op, so without this a chosen texture stayed live forever -- the
			// menu option was a one-way door. It used to re-run the WHOLE
			// preset here, which fixed that and wiped every slider tuned since.
			GITD_Presets.Apply(want, true);
		}

		GITD_Textures.Apply(wantTex);
		GITD_Util.SetI("gitd_texture_applied", wantTex);
	}

	override void WorldThingDied(WorldEvent e)
	{
		int mode = GITD_Util.GetI("gitd_ondeath", 0);
		if (mode == 0) return;
		if (!e || !e.Thing || !e.Thing.player) return;

		// DRAWN ON EVERY PEER, USED ON ONE. random() is the SYNCHRONISED
		// playsim RNG -- the generator the simulation itself runs on. Drawing
		// from it inside the consoleplayer test meant one machine consumed a
		// number the others did not, which desyncs every RNG decision after it
		// and poisons the state written into savegames.
		//
		// WorldThingDied fires identically on all peers and both guards above
		// read peer-identical state, so drawing here costs the same rolls
		// everywhere. Only the USE of them is local. All four are drawn every
		// time, whichever one ends up used, for the same reason.
		int cur = GITD_Util.GetI("gitd_preset", 1);
		int rOff = random(1, PRESET_COUNT - 2);
		int rAny = random(1, PRESET_COUNT - 1);
		int rollSeed = random(0, 9999);
		int rollHue = random(30, 330);

		// Only the player whose screen this is. In co-op every death would
		// otherwise restyle the map for everyone.
		if (e.Thing.player != players[consoleplayer]) return;

		int rollPreset = OtherPreset(cur, rOff, rAny);
		if (mode == 2)
		{
			GITD_Util.SetI("gitd_preset", rollPreset);
			return;
		}

		// "NEW COLOURS" NEEDS A COLOUR SOURCE THAT CAN CHANGE. The seed only
		// reaches the random and texture policies, so on a preset built from
		// fixed colours or light keying -- nine of the twenty-three -- a new
		// seed re-applied the map and nothing visible happened. A light-keyed
		// look turns its hue window instead; an all-fixed look has no colour
		// the mod can vary, so it gets a new preset rather than nothing.
		bool hashed = UsesPolicy(GITD_Policy.POLICY_RANDOM)
			|| UsesPolicy(GITD_Policy.POLICY_TEXTURE);
		if (hashed)
			GITD_Util.SetI("gitd_seed", rollSeed);
		else if (UsesPolicy(GITD_Policy.POLICY_LIGHT))
			TurnHueWindow(rollHue);
		else
			GITD_Util.SetI("gitd_preset", rollPreset);

		// Every path changes the settings hash, so the next poll re-applies
		// on its own.
	}

	// Does any lane that draws something use this policy? Read from the
	// cvars, because the play side has no lane objects of its own.
	static bool UsesPolicy(int policy)
	{
		if (LaneUses("gitd_wf", policy)) return true;
		if (LaneUses("gitd_wc", policy)) return true;
		if (LaneUses("gitd_fg", policy)) return true;
		if (LaneUses("gitd_cg", policy)) return true;
		return GITD_Util.GetB("gitd_liq_on", true) && LaneUses("gitd_liq", policy);
	}

	static bool LaneUses(String p, int policy)
	{
		return GITD_Util.GetB(p .. "_on", true)
			&& GITD_Util.GetF(p .. "_intensity", 1.0) > 0.0
			&& GITD_Util.GetI(p .. "_policy", 0) == policy;
	}

	// Rotate the hue window by `by` degrees, keeping its width. A window that
	// already spans the whole circle is kept one degree short of it: min equal
	// to max reads as a zero-width window, which would flatten the look to
	// one hue.
	static void TurnHueWindow(int by)
	{
		double lo = GITD_Util.GetF("gitd_hue_min", 0.0);
		double hi = GITD_Util.GetF("gitd_hue_max", 360.0);
		double span = hi - lo;
		if (span < 0.0) span += 360.0;

		double nlo = lo + by;
		if (nlo >= 360.0) nlo -= 360.0;

		double nhi;
		if (span >= 360.0)
		{
			nhi = nlo - 1.0;
			if (nhi < 0.0) { nlo = 0.0; nhi = 360.0; }
		}
		else
		{
			nhi = nlo + span;
			if (nhi > 360.0) nhi -= 360.0;
		}

		GITD_Util.SetF("gitd_hue_min", nlo);
		GITD_Util.SetF("gitd_hue_max", nhi);
	}

	// ---- the per-pixel layer -----------------------------------------------

	// Pushed every tic from BOTH WorldTick and UiTick.
	//
	// UiTick is the one that matters: the playsim stops while the menu is up,
	// so WorldTick alone would freeze the picture exactly while you are
	// dragging the slider that is meant to change it. UiTick keeps running.
	// This is why the whole call chain here is clearscope -- a ui-scope caller
	// cannot reach a play-scope helper, and every glow function below is
	// declared clearscope by the engine precisely so a menu can drive it
	// (LevelLocals.SetGlowWave and its neighbours in doombase.zs).
	//
	// Both callers are kept rather than UiTick alone: pushing twice a tic
	// costs about thirty CVar lookups and guarantees the feature works even if
	// UiTick is gated somewhere unexpected.
	//
	// Every per-pixel slider is read here, and UiTick runs it, so they move the
	// picture while the menu is open. Declared for menu_lint's live-page check:
	// LINT-UI-LIVE: gitd_speed gitd_pulse_rate gitd_wave_len gitd_wave_speed gitd_wave_sharp
	// LINT-UI-LIVE: gitd_wave_reach gitd_wave_bright gitd_wave_colour gitd_wave_detune gitd_wave_seed
	// LINT-UI-LIVE: gitd_wave_ph_wtop gitd_wave_ph_wbot gitd_wave_ph_floor gitd_wave_ph_ceil
	// LINT-UI-LIVE: gitd_tex_noise gitd_tex_scale gitd_tex_drift gitd_tex_contrast
	// LINT-UI-LIVE: gitd_flow gitd_flow_spacing gitd_flow_speed gitd_flow_sharp
	// LINT-UI-LIVE: gitd_cell gitd_cell_scale gitd_cell_speed gitd_cell_width gitd_pulse gitd_pulse_level gitd_react
	clearscope void PushGlobals()
	{
		if (!Level) return;

		// One dial over all four animation rates. Applied HERE rather than in
		// the presets so it rides on top of whatever a preset chose and can be
		// moved without disturbing it -- and so it still works on hand-tuned
		// settings that no preset ever touched.
		double rate = GITD_Util.GetF("gitd_speed", 1.0);

		Level.SetGlowWave(
			GITD_Util.GetF("gitd_wave_len"),
			GITD_Util.GetF("gitd_wave_speed", 1.0) * rate,
			GITD_Util.GetF("gitd_wave_sharp", 1.0),
			GITD_Util.GetI("gitd_wave_shape", 1));

		Level.SetGlowWaveDepth(
			GITD_Util.GetF("gitd_wave_reach"),
			GITD_Util.GetF("gitd_wave_bright"),
			GITD_Util.GetF("gitd_wave_colour"),
			GITD_Util.GetF("gitd_wave_detune"),
			GITD_Util.GetF("gitd_wave_seed"));

		Level.SetGlowWavePhase(
			GITD_Util.GetF("gitd_wave_ph_wtop"),
			GITD_Util.GetF("gitd_wave_ph_wbot"),
			GITD_Util.GetF("gitd_wave_ph_floor"),
			GITD_Util.GetF("gitd_wave_ph_ceil"));

		Level.SetGlowTexture(
			GITD_Util.GetF("gitd_tex_noise"),
			GITD_Util.GetF("gitd_tex_scale", 0.06),
			GITD_Util.GetF("gitd_tex_drift"),
			GITD_Util.GetF("gitd_tex_contrast", 1.0));

		Level.SetGlowFlow(
			GITD_Util.GetF("gitd_flow"),
			GITD_Util.GetF("gitd_flow_spacing", 1.0),
			GITD_Util.GetF("gitd_flow_speed", 1.0) * rate,
			GITD_Util.GetF("gitd_flow_sharp", 1.0));

		Level.SetGlowCells(
			GITD_Util.GetF("gitd_cell"),
			GITD_Util.GetF("gitd_cell_scale", 1.0),
			GITD_Util.GetF("gitd_cell_speed", 1.0) * rate,
			GITD_Util.GetF("gitd_cell_width", 0.5));

		// react only scales the engine's fog-disturbance array, which this mod
		// does not populate -- it is exposed for completeness and for other
		// mods that do. pulse/level are self-contained and are what the
		// throbbing presets actually use. (SetGlowReact in vmthunks.cpp)
		Level.SetGlowReact(
			GITD_Util.GetF("gitd_react"),
			GITD_Util.GetF("gitd_pulse"),
			GITD_Util.GetF("gitd_pulse_level"),
			GITD_Util.GetF("gitd_pulse_rate", 1.0) * rate);
	}

	// Runs while the game is paused and while the menu is open, which
	// WorldTick does not. Everything the mod can change moves as you drag its
	// slider -- wave, noise, flow, cells, the alarm, AND the four lanes.
	//
	// The lanes used to be excluded here: Sector.SetGlowColor and friends were
	// play scope, so a paused game could not re-tint sectors and every lane
	// edit sat dead until you closed the menu -- you could not see the change
	// you were dragging for. Those setters are clearscope now (mapdata.zs,
	// Sector and Side), because glow is render state that merely lives on a
	// play struct: nothing in the simulation reads any of it. So the whole
	// apply chain runs from here, and the map re-tints under the menu.
	//
	// Same poll as WorldTick rather than applying every frame: dragging a
	// slider changes the settings hash, the hash starts an apply, the apply
	// walks the map in chunks. Idle menus cost one hash.
	override void UiTick()
	{
		// PUSHED AFTER THE ENABLED TEST, NOT BEFORE IT.
		//
		// These are LEVEL-global render settings shared with every other mod
		// and with any map using its own sector glow. Pushing them first meant
		// that on the tic the mod was switched off ClearAll zeroed them and
		// the very next tic put them all back -- so a disabled GlowInTheDark
		// went on imposing its wave, grain, flow, cells and alarm pulse on
		// everybody else's glow forever.
		bool enabled = GITD_Util.GetB("gitd_enabled", true);
		if (enabled)
		{
			PushGlobals();
			PushWaveOrigin();
		}

		if (!enabled)
		{
			// Turning the mod off has to actively clear what it wrote -- sector
			// glow is persistent state, not something re-established each
			// frame. Clear once, then stay quiet.
			if (wasEnabled)
			{
				ClearAll();
				wasEnabled = false;
			}
			return;
		}

		if (!Level) return;
		EnsureLanes();

		// The preset has to be resolved here as well as in WorldTick. A preset
		// is not a value the apply reads -- it is a batch of CVar writes, and
		// those only happened on the play side. So while the menu was up,
		// dragging a slider would eventually have moved the picture but picking
		// a preset could not, because the CVars it sets were never written.
		// Both sides calling it is harmless: the applied latches are nosave, so
		// the first caller's write lands at once and the second sees no change.
		SyncPreset();

		// A fresh level starts with its glow unset, so a new map has to be
		// re-applied even when not one setting moved and the hash therefore
		// matches. WorldLoaded used to kick that off; it cannot reach ui state,
		// so the map is identified from here instead. Name plus sector count
		// separates a real map change from a mid-level reload of the same one.
		// A loaded save starts with an empty signature -- see the transient
		// note on the fields.
		String sig = Level.MapName .. ":" .. Level.Sectors.Size();
		if (sig != mapSig)
		{
			mapSig = sig;
			lastHash = 0;          // force the poll below to fire
			pollTimer = 0;
			// A different map's light and flat history means nothing here.
			seenLight.Clear();
			seenFloorTex.Clear();
			seenCeilTex.Clear();
			watchTimer = WATCH_TICS;
			// Nor do its claims.
			claimedParts.Clear();
			claimedHeld = 0;
		}

		if (!wasEnabled)
		{
			wasEnabled = true;
			lastHash = 0;
			pollTimer = 0;
		}

		if (--pollTimer <= 0)
		{
			pollTimer = POLL_TICS;
			uint h = SettingsHash();
			if (h != lastHash)
			{
				lastHash = h;
				BeginApply();
			}
		}

		// Both looks run every time. Neither may short-circuit the other: each
		// also brings its own record up to date.
		if (!applying && --watchTimer <= 0)
		{
			watchTimer = WATCH_TICS;
			bool sectorsMoved = WatchSectors();
			bool claimLetGo = WatchClaims();
			if (sectorsMoved || claimLetGo) BeginApply();
		}

		if (applying) StepApply();
	}

	// clearscope, and pushed from UiTick as well as WorldTick, like
	// PushGlobals: switching Origin moves the wave while the menu is up. The
	// engine's origin setter is clearscope for exactly this, and reading the
	// console player's position is a read of play data, which clearscope may do.
	//
	// Pushed every tic in BOTH modes. "Static at map centre" used to push
	// nothing at all, so a static wave centred on whatever the last writer had
	// left behind -- world (0,0,0), which is often outside the level, or the
	// spot the player stood when a follow-you preset was last up, or another
	// mod's anchor -- including on later maps, since the engine never resets
	// the origin.
	//
	// The centre itself is worked out on the play side (FindMapCentre, from
	// WorldLoaded and WorldTick); this only reads what it stored. Until it has
	// run on this map there is no centre to push, so nothing is.
	clearscope void PushWaveOrigin()
	{
		if (!Level) return;

		if (GITD_Util.GetI("gitd_wave_origin") == 1)
		{
			let pmo = players[consoleplayer].mo;
			if (pmo) Level.SetGlowWaveOrigin(pmo.Pos);
			return;
		}

		if (!haveCentre) return;
		Level.SetGlowWaveOrigin(mapCentre);
	}

	// The middle of the box around every sector's centre spot, once per map.
	// Height is halfway between the lowest floor and the highest ceiling, so a
	// rising wave's crest spacing is measured from inside the level. Play scope
	// because it writes the play-side fields PushWaveOrigin reads.
	void FindMapCentre()
	{
		haveCentre = true;
		mapCentre = (0, 0, 0);

		int n = Level.Sectors.Size();
		if (n == 0) return;

		double x0 = 0, x1 = 0, y0 = 0, y1 = 0, z0 = 0, z1 = 0;
		bool first = true;
		for (int i = 0; i < n; i++)
		{
			let sec = Level.Sectors[i];
			if (!sec) continue;

			Vector2 c = sec.centerspot;
			double fz = sec.CenterFloor();
			double cz = sec.CenterCeiling();
			if (first)
			{
				x0 = x1 = c.x;
				y0 = y1 = c.y;
				z0 = fz;
				z1 = cz;
				first = false;
				continue;
			}
			x0 = min(x0, c.x); x1 = max(x1, c.x);
			y0 = min(y0, c.y); y1 = max(y1, c.y);
			z0 = min(z0, fz);  z1 = max(z1, cz);
		}
		if (first) return;

		mapCentre = ((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5);
	}

	// ---- applying the lanes ------------------------------------------------

	// Allocate the six config objects, once. UI scope like the rest of the
	// apply chain: WorldLoaded used to do this, but play cannot reach ui state,
	// so the first UiTick that finds a level does it instead.
	ui void EnsureLanes()
	{
		if (!range)   range   = GITD_Range.FromCVars();
		if (!laneWF)  laneWF  = GITD_Lane.FromCVars("gitd_wf");
		if (!laneWC)  laneWC  = GITD_Lane.FromCVars("gitd_wc");
		if (!laneFG)  laneFG  = GITD_Lane.FromCVars("gitd_fg");
		if (!laneCG)  laneCG  = GITD_Lane.FromCVars("gitd_cg");
		if (!laneLiq) laneLiq = GITD_Lane.FromCVars("gitd_liq");
	}

	// The lane and randomiser sliders reach the map through this apply, and
	// UiTick starts and steps it -- the map re-tints under the menu within a
	// few tics of a drag. Declared for menu_lint's live-page check:
	// LINT-UI-LIVE: gitd_wf_color gitd_wf_reach gitd_wf_intensity gitd_wf_farcolor
	// LINT-UI-LIVE: gitd_wc_color gitd_wc_reach gitd_wc_intensity gitd_wc_farcolor
	// LINT-UI-LIVE: gitd_fg_color gitd_fg_reach gitd_fg_intensity gitd_fg_farcolor
	// LINT-UI-LIVE: gitd_cg_color gitd_cg_reach gitd_cg_intensity gitd_cg_farcolor
	// LINT-UI-LIVE: gitd_liq_color gitd_liq_reach gitd_liq_intensity gitd_liq_farcolor
	// LINT-UI-LIVE: gitd_wall_blend gitd_hue_min gitd_hue_max gitd_sat_min gitd_sat_max gitd_val_min gitd_val_max gitd_seed
	ui void BeginApply()
	{
		// Nothing to apply into yet. UiTick fires before a level has ever
		// loaded -- the title screen is a menu like any other -- and that is the
		// one path that reaches here before EnsureLanes has run.
		if (!range || !laneWF) return;

		range.Fill();
		laneWF.Fill("gitd_wf");
		laneWC.Fill("gitd_wc");
		laneFG.Fill("gitd_fg");
		laneCG.Fill("gitd_cg");
		laneLiq.Fill("gitd_liq");

		liqOn    = GITD_Util.GetB("gitd_liq_on", true);
		liqWalls = GITD_Util.GetB("gitd_liq_walls", true);
		// Seamless corners and glow waves are mutually exclusive, and the
		// exclusion is enforced here rather than left to the user.
		//
		// The corner works by agreeing on colour across the junction. A wave
		// moves reach per pixel, so undulating one side of a corner reopens the
		// seam it just closed -- and worse, the seam then travels. Either the
		// room is bounded by continuous colour with no edge, or the edge moves;
		// it cannot be both. Eight of the presets run waves, so silently
		// dropping seamless while one is live is the only safe reading.
		seamless = GITD_Util.GetB("gitd_seamless", true)
			&& GITD_Util.GetF("gitd_wave_len") <= 0.0;
		seamShape = GITD_Util.GetB("gitd_seamless_shape", false);

		wallSeam  = GITD_Util.GetB("gitd_seamless_walls", true);
		wallBlend = clamp(GITD_Util.GetF("gitd_wall_blend", 0.5), 0.0, 1.0);

		lightKeyed = LaneKeyed(laneWF, GITD_Policy.POLICY_LIGHT)
			|| LaneKeyed(laneWC, GITD_Policy.POLICY_LIGHT)
			|| LaneKeyed(laneFG, GITD_Policy.POLICY_LIGHT)
			|| LaneKeyed(laneCG, GITD_Policy.POLICY_LIGHT)
			|| (liqOn && LaneKeyed(laneLiq, GITD_Policy.POLICY_LIGHT));
		texKeyed = LaneKeyed(laneWF, GITD_Policy.POLICY_TEXTURE)
			|| LaneKeyed(laneWC, GITD_Policy.POLICY_TEXTURE)
			|| LaneKeyed(laneFG, GITD_Policy.POLICY_TEXTURE)
			|| LaneKeyed(laneCG, GITD_Policy.POLICY_TEXTURE)
			|| (liqOn && LaneKeyed(laneLiq, GITD_Policy.POLICY_TEXTURE));

		int n = Level ? Level.Sectors.Size() : 0;
		baseWF.Resize(n); baseWC.Resize(n);
		baseFG.Resize(n); baseCG.Resize(n);
		liquidAt.Resize(n);
		if (seenLight.Size() != n) SeedWatch(n);

		applyCursor = 0;
		phase = 1;              // resolve first, then blend and write
		applying = true;
	}

	ui bool LaneKeyed(GITD_Lane ln, int policy)
	{
		return ln && ln.Drawn() && ln.policy == policy;
	}

	ui void StepApply()
	{
		if (!Level) { applying = false; phase = 0; return; }

		// The map cannot change size under an apply, but a table sized for a
		// different one must never be indexed past its end.
		int n = min(Level.Sectors.Size(), baseWF.Size());
		int end = min(applyCursor + APPLY_CHUNK, n);

		if (phase == 1)
		{
			for (int i = applyCursor; i < end; i++)
			{
				ResolveSector(Level.Sectors[i], i);
			}
			applyCursor = end;
			if (applyCursor >= n) { applyCursor = 0; phase = 2; }
			return;
		}

		// CLAIMS ARE READ HERE, at the top of each write chunk: once per apply on
		// any map of up to APPLY_CHUNK sectors, and never once per sector. Not in
		// BeginApply -- the resolve pass runs a tic or more before the write, and
		// a sweep crossing a room in between would have that room painted over.
		GatherClaims();
		for (int i = applyCursor; i < end; i++)
		{
			ApplySector(Level.Sectors[i], i);
		}

		applyCursor = end;
		if (applyCursor >= n) { applying = false; phase = 0; }
	}

	// Pass one: each sector's own colour per lane, before any neighbour
	// blending. Touches no engine state.
	ui void ResolveSector(Sector sec, int idx)
	{
		if (!sec) return;

		bool liquid = IsLiquid(sec);
		liquidAt[idx] = liquid;
		let floorLane  = (liquid) ? laneLiq : laneFG;
		let wallLoLane = (liquid && liqWalls) ? laneLiq : laneWF;

		baseWF[idx] = Resolved(wallLoLane, sec, idx, Sector.floor,   SALT_WF);
		baseWC[idx] = Resolved(laneWC,     sec, idx, Sector.ceiling, SALT_WC);
		baseFG[idx] = Resolved(floorLane,  sec, idx, Sector.floor,   SALT_FG);
		baseCG[idx] = Resolved(laneCG,     sec, idx, Sector.ceiling, SALT_CG);
	}

	ui bool IsLiquid(Sector sec)
	{
		if (!liqOn) return false;
		return GITD_Policy.IsLiquidFloor(sec);
	}

	// Pull one sector's colour toward the average of the sectors it shares a
	// line with. Self-references and one-sided lines are skipped -- a map edge
	// has no neighbour to agree with, and pulling toward yourself is a no-op
	// that would still drag the average.
	//
	// So are neighbours where the lane draws nothing. Those used to be stored
	// as black and averaged in like any colour, so with Floor Face off and
	// liquids on, every liquid floor was dragged halfway to black by the dry
	// floors around it.
	ui Color Neighbourly(Sector sec, Array<int> store, int idx)
	{
		if (store[idx] == NO_COLOUR) return Color(255, 0, 0, 0);   // not drawn; unread
		Color own = GITD_Util.Unpack(store[idx]);
		if (!wallSeam || wallBlend <= 0.0) return own;

		int r = 0, g = 0, b = 0, cnt = 0;
		for (int i = 0; i < sec.lines.Size(); i++)
		{
			let ln = sec.lines[i];
			if (!ln) continue;

			Sector other = (ln.frontsector == sec) ? ln.backsector : ln.frontsector;
			if (!other || other == sec) continue;

			int oi = other.Index();
			if (oi < 0 || oi >= store.Size()) continue;
			if (store[oi] == NO_COLOUR) continue;

			Color oc = GITD_Util.Unpack(store[oi]);
			r += oc.r; g += oc.g; b += oc.b; cnt++;
		}

		if (cnt == 0) return own;
		return GITD_Util.LerpCol(own, Color(255, r / cnt, g / cnt, b / cnt), wallBlend);
	}

	ui void ApplySector(Sector sec, int idx)
	{
		if (!sec) return;

		// A part another mod has claimed is left exactly as that mod painted it.
		// A fully claimed sector needs nothing worked out at all.
		int claimed = ClaimedAt(idx);
		if (claimed == (CLAIM_WALLS | CLAIM_FLATS)) return;

		// Liquid floors take their own config instead of the general floor
		// policy. This is what replaces 1.1's gldefs.bm, and it does the thing
		// GLDEFS never could: light the liquid's own surface, not just the
		// wall beside it. Read from pass one, so both passes agree.
		bool liquid = liquidAt[idx];

		let floorLane  = (liquid) ? laneLiq : laneFG;
		let wallLoLane = (liquid && liqWalls) ? laneLiq : laneWF;

		// SEAMLESS WALLS -- each lane pulled toward its neighbours across
		// shared lines, so the boundary between two sectors stops being a hard
		// line. Resolved in pass one; this reads the finished table.
		Color cWF = Neighbourly(sec, baseWF, idx);
		Color cWC = Neighbourly(sec, baseWC, idx);
		Color cFG = Neighbourly(sec, baseFG, idx);
		Color cCG = Neighbourly(sec, baseCG, idx);

		// Each lane's own far colour, before any corner work.
		Color fWF = (wallLoLane) ? wallLoLane.FarFor(cWF) : Color(0, 0, 0, 0);
		Color fWC = (laneWC)     ? laneWC.FarFor(cWC)     : Color(0, 0, 0, 0);
		Color fFG = (floorLane)  ? floorLane.FarFor(cFG)  : Color(0, 0, 0, 0);
		Color fCG = (laneCG)     ? laneCG.FarFor(cCG)     : Color(0, 0, 0, 0);

		// Each lane's own shape.
		double rWF = LaneReach(wallLoLane), rWC = LaneReach(laneWC);
		double rFG = LaneReach(floorLane),  rCG = LaneReach(laneCG);
		int    kWF = LaneFall(wallLoLane),  kWC = LaneFall(laneWC);
		int    kFG = LaneFall(floorLane),   kCG = LaneFall(laneCG);
		double iWF = LaneInten(wallLoLane), iWC = LaneInten(laneWC);
		double iFG = LaneInten(floorLane),  iCG = LaneInten(laneCG);

		bool wfOn = wallLoLane && wallLoLane.Drawn();
		bool wcOn = laneWC     && laneWC.Drawn();
		bool fgOn = floorLane  && floorLane.Drawn();
		bool cgOn = laneCG     && laneCG.Drawn();

		// SEAMLESS CORNERS.
		//
		// The gradient at a corner was never missing. The wall's glow fades
		// UPWARD from the floor line; the floor's edge glow fades INWARD from
		// that same line. Two ramps meeting nose to nose, both at FULL
		// strength exactly where they touch. The hard cut is the two sides
		// disagreeing about what colour to be AT the line they share.
		//
		// So it is the NEAR colours that have to agree -- they are the ones
		// that meet. Both lanes take the junction colour at the line. A lane
		// whose far colour is AUTO gets its own original colour as the far end,
		// which is what lets a corner still read floor-purple into wall-blue
		// instead of collapsing to one flat wash of the average. An EXPLICIT far
		// colour is kept -- it is a choice, and Hellscape's oxblood ramp is that
		// preset's whole look -- and a lane with its far colour OFF stays a
		// single-colour wash of the junction colour.
		//
		// Reach, falloff and intensity stay each lane's own. Copying the wall's
		// onto the floor made the Floor and Ceiling Face shape sliders do
		// nothing and drew every authored long flat reach at the wall's height.
		// Matching shape too is its own option, off by default.
		//
		// A corner needs BOTH surfaces drawn before there is anything to agree
		// with. With one side off the other keeps its own colour, exactly as
		// it looked before seamless existed.
		if (seamless)
		{
			if (wfOn && fgOn)
			{
				Color join = GITD_Util.Blend(cWF, cFG);
				if (wallLoLane.farMode == 1) fWF = cWF;
				if (floorLane.farMode == 1)  fFG = cFG;
				cWF = join;
				cFG = join;
				if (seamShape) { rFG = rWF; kFG = kWF; iFG = iWF; }   // flat takes the wall's shape
			}
			if (wcOn && cgOn)
			{
				Color join = GITD_Util.Blend(cWC, cCG);
				if (laneWC.farMode == 1) fWC = cWC;
				if (laneCG.farMode == 1) fCG = cCG;
				cWC = join;
				cCG = join;
				if (seamShape) { rCG = rWC; kCG = kWC; iCG = iWC; }
			}
		}

		if (!(claimed & CLAIM_WALLS))
		{
			ApplyWallLane(sec, Sector.floor,   wfOn, cWF, fWF, rWF, kWF, iWF);
			ApplyWallLane(sec, Sector.ceiling, wcOn, cWC, fWC, rWC, kWC, iWC);
		}
		if (!(claimed & CLAIM_FLATS))
		{
			ApplyFlatLane(sec, Sector.floor,   fgOn, cFG, fFG, rFG, kFG, iFG);
			ApplyFlatLane(sec, Sector.ceiling, cgOn, cCG, fCG, rCG, kCG, iCG);
		}
	}

	ui double LaneReach(GITD_Lane ln) { return ln ? ln.reach : 0.0; }
	ui int    LaneFall(GITD_Lane ln)  { return ln ? ln.falloff : 0; }
	ui double LaneInten(GITD_Lane ln) { return ln ? ln.intensity : 1.0; }

	// One lane's colour, packed for the per-sector tables. A lane that draws
	// nothing stores NO_COLOUR, which Neighbourly skips.
	ui int Resolved(GITD_Lane ln, Sector sec, int idx, int planePos, uint salt)
	{
		if (!ln || !ln.Drawn()) return NO_COLOUR;
		int light = (idx < seenLight.Size()) ? seenLight[idx] : -1;
		return GITD_Util.Pack(GITD_Policy.Resolve(sec, idx, planePos, ln.policy,
			ln.fixedCol, salt, range, light));
	}

	ui void ApplyWallLane(Sector sec, int planePos, bool on,
		Color nearCol, Color farCol, double reach, int falloff, double inten)
	{
		// Intensity 0 is off, not "unset" -- see GITD_Lane.Drawn.
		if (!on || inten <= 0.0)
		{
			sec.SetGlowColor(planePos, Color(0, 0, 0, 0));
			sec.SetGlowColorFar(planePos, Color(0, 0, 0, 0));
			sec.SetGlowHeight(planePos, 0.0);
			return;
		}

		sec.SetGlowColor(planePos, nearCol);
		sec.SetGlowColorFar(planePos, farCol);
		sec.SetGlowHeight(planePos, reach);      // VERTICAL, up the wall
		sec.SetGlowFalloff(planePos, falloff);
		sec.SetGlowIntensity(planePos, inten);   // scales colour, not reach
	}

	ui void ApplyFlatLane(Sector sec, int planePos, bool on,
		Color nearCol, Color farCol, double reach, int falloff, double inten)
	{
		if (!on || inten <= 0.0)
		{
			sec.SetFlatGlowColor(planePos, Color(0, 0, 0, 0));
			sec.SetFlatGlowColorFar(planePos, Color(0, 0, 0, 0));
			sec.SetFlatGlowHeight(planePos, 0.0);
			return;
		}

		sec.SetFlatGlowColor(planePos, nearCol);
		sec.SetFlatGlowColorFar(planePos, farCol);
		sec.SetFlatGlowHeight(planePos, reach);  // HORIZONTAL, inward from edge
		sec.SetFlatGlowFalloff(planePos, falloff);
		sec.SetFlatGlowIntensity(planePos, inten);
	}

	// Turning the mod off clears what it painted -- and ONLY what it painted. A
	// claimed part carries another mod's colour and stays when this one goes:
	// wiping a sweep's rooms because GITD was switched off was the other half
	// of the fight. The claims are read once, here. They are not let go of: a
	// claim belongs to the mod that made it, and GITD switched back on skips
	// the same parts again.
	ui void ClearAll()
	{
		if (!Level) return;
		GatherClaims();

		for (int i = 0; i < Level.Sectors.Size(); i++)
		{
			let sec = Level.Sectors[i];
			if (!sec) continue;
			int claimed = ClaimedAt(i);

			for (int p = 0; p <= 1; p++)
			{
				if (!(claimed & CLAIM_WALLS))
				{
					sec.SetGlowColor(p, Color(0, 0, 0, 0));
					sec.SetGlowColorFar(p, Color(0, 0, 0, 0));
					sec.SetGlowHeight(p, 0.0);
				}
				if (!(claimed & CLAIM_FLATS))
				{
					sec.SetFlatGlowColor(p, Color(0, 0, 0, 0));
					sec.SetFlatGlowColorFar(p, Color(0, 0, 0, 0));
					sec.SetFlatGlowHeight(p, 0.0);
				}
			}
		}

		Level.ClearGlowWave();
		Level.SetGlowTexture(0, 1, 0, 1);
		Level.SetGlowFlow(0, 1, 1, 1);
		Level.SetGlowCells(0, 1, 1, 0.5);
		Level.SetGlowReact(0, 0, 0);

		applying = false;
		phase = 0;
	}

	// ---- sector state ------------------------------------------------------

	// Take a first reading of every sector. Called when the tables do not
	// match the map -- the first apply on a map, or after a load.
	ui void SeedWatch(int n)
	{
		seenLight.Resize(n);
		seenFloorTex.Resize(n);
		seenCeilTex.Resize(n);
		for (int i = 0; i < n; i++)
		{
			let sec = Level.Sectors[i];
			if (!sec) { seenLight[i] = 0; seenFloorTex[i] = 0; seenCeilTex[i] = 0; continue; }
			seenLight[i] = sec.lightlevel;
			TextureID ft = sec.GetTexture(Sector.floor);
			TextureID ct = sec.GetTexture(Sector.ceiling);
			seenFloorTex[i] = ft.GetIndex();
			seenCeilTex[i] = ct.GetIndex();
		}
		watchTimer = WATCH_TICS;
	}

	// True when something a lane is keyed on has moved since the last look,
	// and the map needs applying again. The readings are always updated, keyed
	// or not, so a lane switched to the light policy later starts from a
	// settled light level rather than a mid-flicker one.
	ui bool WatchSectors()
	{
		if (!Level) return false;
		int n = Level.Sectors.Size();
		if (seenLight.Size() != n) return false;   // not seeded; the next apply does it

		bool moved = false;
		for (int i = 0; i < n; i++)
		{
			let sec = Level.Sectors[i];
			if (!sec) continue;

			int l = sec.lightlevel;
			if (l > seenLight[i])
			{
				seenLight[i] = l;
				if (lightKeyed) moved = true;
			}

			TextureID ft = sec.GetTexture(Sector.floor);
			int fi = ft.GetIndex();
			if (fi != seenFloorTex[i])
			{
				seenFloorTex[i] = fi;
				if (texKeyed || liqOn) moved = true;
			}

			TextureID ct = sec.GetTexture(Sector.ceiling);
			int ci = ct.GetIndex();
			if (ci != seenCeilTex[i])
			{
				seenCeilTex[i] = ci;
				if (texKeyed) moved = true;
			}
		}
		return moved;
	}

	// ---- claims ------------------------------------------------------------

	// The claim markers, or null when no mod that makes them is loaded. The
	// class is looked up from a String VARIABLE on purpose: a class named in a
	// literal is resolved while compiling, and would make this mod refuse to
	// load without RS_Sweeps. See the claims note on the fields.
	ui ThinkerIterator ClaimIterator()
	{
		String cname = "RSS_SectorClaim";
		Class<Actor> cls = cname;
		if (!cls) return null;
		return ThinkerIterator.Create(cls, Thinker.STAT_INFO, true);
	}

	// Every claim, read into claimedParts. Called once per write chunk and once
	// per ClearAll -- never per sector.
	ui void GatherClaims()
	{
		claimedParts.Clear();
		claimedHeld = 0;
		let it = ClaimIterator();
		if (!it || !Level) return;

		int n = Level.Sectors.Size();
		claimedParts.Resize(n);
		Actor a;
		while (a = Actor(it.Next()))
		{
			int idx = a.args[0];
			if (idx < 0 || idx >= n) continue;
			int fresh = a.args[1] & (CLAIM_WALLS | CLAIM_FLATS) & ~claimedParts[idx];
			claimedParts[idx] |= fresh;
			claimedHeld += PartCount(fresh);
		}
	}

	ui int ClaimedAt(int idx)
	{
		return (idx >= 0 && idx < claimedParts.Size()) ? claimedParts[idx] : 0;
	}

	ui int PartCount(int parts)
	{
		return ((parts & CLAIM_WALLS) != 0 ? 1 : 0) + ((parts & CLAIM_FLATS) != 0 ? 1 : 0);
	}

	// True when a part claimed at the last gather has been let go -- the sweep's
	// glow effect was switched off -- and the map needs applying again to put
	// this mod's colour back there. Claims that were only ADDED need no apply:
	// the sweep painted those itself. They are read in all the same, so letting
	// one of them go later is noticed too.
	ui bool WatchClaims()
	{
		let it = ClaimIterator();
		if (!it) return false;

		int n = claimedParts.Size();
		int held = 0, total = 0;
		Actor a;
		while (a = Actor(it.Next()))
		{
			int parts = a.args[1] & (CLAIM_WALLS | CLAIM_FLATS);
			total += PartCount(parts);
			int idx = a.args[0];
			if (idx >= 0 && idx < n) held += PartCount(parts & claimedParts[idx]);
		}
		if (held < claimedHeld) return true;      // the apply gathers afresh
		if (total != claimedHeld) GatherClaims();
		return false;
	}

	// ---- change detection --------------------------------------------------

	// Only the per-sector settings belong here. The per-pixel layer is pushed
	// unconditionally every tic and needs no detection.
	ui uint SettingsHash()
	{
		uint h = 2166136261;
		h = AccLane(h, "gitd_wf");
		h = AccLane(h, "gitd_wc");
		h = AccLane(h, "gitd_fg");
		h = AccLane(h, "gitd_cg");
		h = AccLane(h, "gitd_liq");

		h = Acc(h, GITD_Util.GetB("gitd_liq_on", true) ? 1 : 0);
		h = Acc(h, GITD_Util.GetB("gitd_liq_walls", true) ? 1 : 0);
		h = Acc(h, GITD_Util.GetB("gitd_seamless", true) ? 1 : 0);
		h = Acc(h, GITD_Util.GetB("gitd_seamless_shape", false) ? 1 : 0);
		h = Acc(h, GITD_Util.GetB("gitd_seamless_walls", true) ? 1 : 0);
		h = Acc(h, int(GITD_Util.GetF("gitd_wall_blend", 0.5) * 1000.0));
		// Wavelength belongs in the per-sector hash even though the wave
		// itself is a per-pixel setting: it gates seamless above, so crossing
		// zero changes what the lanes get written.
		h = Acc(h, int(GITD_Util.GetF("gitd_wave_len") * 10.0));
		h = Acc(h, GITD_Util.GetI("gitd_seed", 1337));
		h = Acc(h, int(GITD_Util.GetF("gitd_hue_min") * 100.0));
		h = Acc(h, int(GITD_Util.GetF("gitd_hue_max") * 100.0));
		h = Acc(h, int(GITD_Util.GetF("gitd_sat_min") * 1000.0));
		h = Acc(h, int(GITD_Util.GetF("gitd_sat_max") * 1000.0));
		h = Acc(h, int(GITD_Util.GetF("gitd_val_min") * 1000.0));
		h = Acc(h, int(GITD_Util.GetF("gitd_val_max") * 1000.0));
		h = Acc(h, GITD_Util.GetB("gitd_lock_planes") ? 1 : 0);
		h = Acc(h, GITD_Util.GetB("gitd_light_invert", true) ? 1 : 0);
		return h;
	}

	ui uint AccLane(uint h, String p)
	{
		h = Acc(h, GITD_Util.GetB(p .. "_on", true) ? 1 : 0);
		h = Acc(h, GITD_Util.GetI(p .. "_policy"));
		h = Acc(h, GITD_Util.GetI(p .. "_color"));
		h = Acc(h, int(GITD_Util.GetF(p .. "_reach") * 100.0));
		h = Acc(h, GITD_Util.GetI(p .. "_falloff"));
		h = Acc(h, int(GITD_Util.GetF(p .. "_intensity") * 1000.0));
		h = Acc(h, GITD_Util.GetI(p .. "_far"));
		h = Acc(h, GITD_Util.GetI(p .. "_farcolor"));
		return h;
	}

	ui uint Acc(uint h, int v)
	{
		h ^= uint(v);
		h *= 16777619;
		return h;
	}
}
