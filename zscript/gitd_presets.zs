// GlowInTheDark 2.0 -- presets.
//
// Nobody tunes ninety sliders. The presets are the mod; the sliders are for
// afterwards. Each one is built around a DIFFERENT mechanism rather than a
// different palette -- if two of these read the same on screen, that is a bug
// in the preset, because the levers they pull do not overlap.
//
// Every preset starts from Base(), which zeroes the whole per-pixel layer.
// Without that, switching presets would leave the previous one's cells or
// flow running underneath the new one's colours.
//
// SURFACE FIRST, THEN EVERYTHING ELSE. Every preset writes its surface
// texture -- Tex, Flow, Cells, the three terms GITD_Textures owns -- before
// anything else, and then stops if surfaceOnly is set. That split is what lets
// Texture "From the preset" put back just the preset's own grain, flow and
// cells. It used to re-run the whole preset instead, which rewrote the lanes,
// the colour window, the wave and the liquids and threw away every slider
// tuned since the preset was picked. Keep a new preset in the same order, or
// its surface will not come back and its palette will.

class GITD_Presets
{
	// ---- writers -----------------------------------------------------------

	static void Lane(String p, bool on, int policy, int r, int g, int b,
		double reach, int falloff, double inten, int farMode = 1,
		int farR = 0, int farG = 0, int farB = 0)
	{
		GITD_Util.SetB(p .. "_on", on);
		GITD_Util.SetI(p .. "_policy", policy);
		GITD_Util.SetC(p .. "_color", r, g, b);
		GITD_Util.SetF(p .. "_reach", reach);
		GITD_Util.SetI(p .. "_falloff", falloff);
		GITD_Util.SetF(p .. "_intensity", inten);
		GITD_Util.SetI(p .. "_far", farMode);
		GITD_Util.SetC(p .. "_farcolor", farR, farG, farB);
	}

	static void Window(double hMin, double hMax, double sMin, double sMax,
		double vMin, double vMax)
	{
		GITD_Util.SetF("gitd_hue_min", hMin);
		GITD_Util.SetF("gitd_hue_max", hMax);
		GITD_Util.SetF("gitd_sat_min", sMin);
		GITD_Util.SetF("gitd_sat_max", sMax);
		GITD_Util.SetF("gitd_val_min", vMin);
		GITD_Util.SetF("gitd_val_max", vMax);
	}

	static void LightDir(bool darkGlowsMore)
	{
		GITD_Util.SetB("gitd_light_invert", darkGlowsMore);
	}

	// shape follows the menu's GITD_WaveShape list, which starts at 1. The
	// engine draws 0 the same as 1, but a 0 in the cvar left the Shape row
	// blank, so nothing here writes 0 any more.
	static void Wave(double len, double speed, double sharp, int shape,
		double reach, double bright, double colour,
		double detune = 0.0, double seed = 0.0)
	{
		GITD_Util.SetF("gitd_wave_len", len);
		GITD_Util.SetF("gitd_wave_speed", speed);
		GITD_Util.SetF("gitd_wave_sharp", sharp);
		GITD_Util.SetI("gitd_wave_shape", shape);
		GITD_Util.SetF("gitd_wave_reach", reach);
		GITD_Util.SetF("gitd_wave_bright", bright);
		GITD_Util.SetF("gitd_wave_colour", colour);
		GITD_Util.SetF("gitd_wave_detune", detune);
		GITD_Util.SetF("gitd_wave_seed", seed);
	}

	static void Phase(double wTop, double wBot, double fl, double ce)
	{
		GITD_Util.SetF("gitd_wave_ph_wtop", wTop);
		GITD_Util.SetF("gitd_wave_ph_wbot", wBot);
		GITD_Util.SetF("gitd_wave_ph_floor", fl);
		GITD_Util.SetF("gitd_wave_ph_ceil", ce);
	}

	static void Tex(double noise, double scale, double drift, double contrast)
	{
		GITD_Util.SetF("gitd_tex_noise", noise);
		GITD_Util.SetF("gitd_tex_scale", scale);
		GITD_Util.SetF("gitd_tex_drift", drift);
		GITD_Util.SetF("gitd_tex_contrast", contrast);
	}

	static void Flow(double amount, double spacing, double speed, double sharp)
	{
		GITD_Util.SetF("gitd_flow", amount);
		GITD_Util.SetF("gitd_flow_spacing", spacing);
		GITD_Util.SetF("gitd_flow_speed", speed);
		GITD_Util.SetF("gitd_flow_sharp", sharp);
	}

	static void Cells(double amount, double scale, double speed, double width)
	{
		GITD_Util.SetF("gitd_cell", amount);
		GITD_Util.SetF("gitd_cell_scale", scale);
		GITD_Util.SetF("gitd_cell_speed", speed);
		GITD_Util.SetF("gitd_cell_width", width);
	}

	// react is inert here by design -- it only scales the engine's
	// fog-disturbance array, which this mod never populates. The throb comes
	// from pulse/level. See SetGlowReact in vmthunks.cpp.
	// `rate` scales the beat independently of `level`. The engine works the
	// throb's speed out from the level, so without this a preset that wanted a
	// bright alarm had no way to ask for a slow one.
	static void Throb(double pulse, double level, double rate = 1.0)
	{
		GITD_Util.SetF("gitd_react", 0.0);
		GITD_Util.SetF("gitd_pulse", pulse);
		GITD_Util.SetF("gitd_pulse_level", level);
		GITD_Util.SetF("gitd_pulse_rate", rate);
	}

	static void Liquid(bool on, int policy, int r, int g, int b,
		double reach, int falloff, double inten, bool walls)
	{
		Lane("gitd_liq", on, policy, r, g, b, reach, falloff, inten, 1);
		GITD_Util.SetB("gitd_liq_on", on);
		GITD_Util.SetB("gitd_liq_walls", walls);
	}

	static void Origin(int mode)
	{
		GITD_Util.SetI("gitd_wave_origin", mode);
	}

	// Neutral ground. Every preset starts here so none of them inherit the
	// last one's leftovers.
	static void Base(bool surfaceOnly)
	{
		Tex(0, 0.06, 0, 1);
		Flow(0, 12, 1, 1);
		Cells(0, 24, 1, 0.5);
		if (surfaceOnly) return;

		Window(0, 360, 0.5, 0.85, 0.45, 0.9);
		LightDir(true);
		Wave(0, 1, 1, 1, 0, 0, 0, 0, 0);
		Phase(0, 0, 0, 0);
		Throb(0, 0);
		Origin(0);
		GITD_Util.SetB("gitd_lock_planes", false);
		Liquid(true, 0, 60, 220, 70, 150, 2, 1.2, true);
	}

	// surfaceOnly re-writes only the preset's Tex/Flow/Cells. See the note at
	// the top of the file.
	static void Apply(int idx, bool surfaceOnly = false)
	{
		Base(surfaceOnly);

		switch (idx)
		{
		case 0:  VanillaPlus(surfaceOnly);     break;
		case 1:  Bioluminescent(surfaceOnly);  break;
		case 2:  Reactor(surfaceOnly);         break;
		case 3:  Neon(surfaceOnly);            break;
		case 4:  Ember(surfaceOnly);           break;
		case 5:  Frostbite(surfaceOnly);       break;
		case 6:  Blacklight(surfaceOnly);      break;
		case 7:  Cathedral(surfaceOnly);       break;
		case 8:  PulseWave(surfaceOnly);       break;
		case 9:  Hazard(surfaceOnly);          break;
		case 10: Circuitry(surfaceOnly);       break;
		case 11: DeepWater(surfaceOnly);       break;
		case 12: Furnace(surfaceOnly);         break;
		case 13: Hellscape(surfaceOnly);       break;
		case 14: RedAlert(surfaceOnly);        break;
		case 15: Spore(surfaceOnly);           break;
		case 16: Signal(surfaceOnly);          break;
		case 17: Prism(surfaceOnly);           break;
		case 18: Ascent(surfaceOnly);          break;
		case 19: Beacon(surfaceOnly);          break;
		case 20: Trawler(surfaceOnly);         break;
		case 21: Filament(surfaceOnly);        break;
		case 22: Tide(surfaceOnly);            break;
		case 23: Crosswind(surfaceOnly);       break;
		case 24: HueDrift(surfaceOnly);        break;
		case 25: Moss(surfaceOnly);            break;
		case 26: BadBallast(surfaceOnly);      break;
		case 27: Sump(surfaceOnly);            break;
		case 28: Vaporwave(surfaceOnly);       break;
		case 29: Strobe(surfaceOnly);          break;
		case 30: Chromawave(surfaceOnly);      break;
		case 31: Overdrive(surfaceOnly);       break;
		case 32: Veins(surfaceOnly);           break;
		case 33: LostSignal(surfaceOnly);      break;
		case 34: Abyssal(surfaceOnly);         break;
		case 35: Glacier(surfaceOnly);         break;
		case 36: Klaxon(surfaceOnly);          break;
		case 37: Inferno(surfaceOnly);         break;
		case 38: Ultraviolet(surfaceOnly);     break;
		case 39: Acid(surfaceOnly);            break;
		case 40: Bubblegum(surfaceOnly);       break;
		case 41: Voltage(surfaceOnly);         break;
		case 42: Nave(surfaceOnly);            break;
		default: VanillaPlus(surfaceOnly);     break;
		}
	}

	// ---- 0-17: the first eighteen ------------------------------------------

	// 0 -- signature: deliberately none. The restrained one.
	static void VanillaPlus(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Lane("gitd_wf", true,  0, 255, 170,  90,  56, 0, 0.60);
		Lane("gitd_wc", true,  0, 150, 140, 120,  48, 0, 0.45);
		Lane("gitd_fg", false, 0, 128, 128, 128,   0, 0, 0.00);
		Lane("gitd_cg", false, 0, 128, 128, 128,   0, 0, 0.00);
		Liquid(true, 0, 70, 210, 80, 120, 2, 1.0, true);
	}

	// 1 -- signature: cells, and the colour climbing every surface it touches.
	//
	// RETUNED 2026-09-20, at the owner's word. It used to be a floors-and-
	// ceilings look: a 40-unit band at half intensity up from the floor seam and
	// NO wall-from-ceiling lane at all. Two things followed, and both of them
	// were the preset's fault rather than the engine's -- the walls read as
	// unlit in a preset whose whole point is that the room is alive, and every
	// wall/ceiling join was a hard line, because a join needs a glow on both
	// sides and one side was switched off.
	//
	// So the walls now carry it: the floor seam climbs 110 units at nearly full
	// intensity and the ceiling seam comes down 100 at 0.85. The flat faces keep
	// their old numbers, so the floor is still the brightest surface in the room
	// and the cells still do the work -- what changes is that the colour reaches
	// the walls instead of stopping at the skirting.
	static void Bioluminescent(bool surfaceOnly)
	{
		Cells(0.70, 20.0, 0.25, 0.45);
		if (surfaceOnly) return;
		Window(150, 200, 0.55, 0.90, 0.45, 0.85);
		Lane("gitd_wf", true, 2, 0, 0, 0, 110, 2, 0.95);
		Lane("gitd_wc", true, 2, 0, 0, 0, 100, 2, 0.85);
		Lane("gitd_fg", true, 2, 0, 0, 0, 140, 2, 1.20);
		Lane("gitd_cg", true, 2, 0, 0, 0,  90, 2, 0.70);
		Wave(220, 0.35, 0.6, 1, 0.30, 0.40, 0.20);
		Liquid(true, 0, 40, 255, 190, 180, 2, 1.5, true);
	}

	// 2 -- signature: flow, plus a floor/ceiling phase offset so the light
	// visibly climbs the room.
	static void Reactor(bool surfaceOnly)
	{
		Flow(0.80, 44.0, 0.9, 1.4);
		if (surfaceOnly) return;
		Lane("gitd_wf", true, 0, 255, 140,  30,  80, 1, 1.30);
		Lane("gitd_wc", true, 0, 255,  90,  20,  70, 1, 1.00);
		Lane("gitd_fg", true, 0, 255, 120,  25, 110, 1, 1.10);
		Lane("gitd_cg", true, 0, 200,  70,  15,  80, 1, 0.80);
		Wave(160, 1.2, 1.0, 1, 0.35, 0.60, 0.15);
		Phase(0.0, 0.5, 0.0, 0.5);
		Liquid(true, 0, 255, 110, 20, 200, 1, 1.8, true);
	}

	// 3 -- signature: exponential falloff and near-max saturation. Hard edges.
	static void Neon(bool surfaceOnly)
	{
		Tex(0.15, 0.070, 0.0, 1.6);
		if (surfaceOnly) return;
		Window(0, 360, 0.95, 1.00, 0.75, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  70, 3, 1.40);
		Lane("gitd_wc", true, 1, 0, 0, 0,  70, 3, 1.40);
		Lane("gitd_fg", true, 1, 0, 0, 0,  80, 3, 1.40);
		Lane("gitd_cg", true, 1, 0, 0, 0,  70, 3, 1.40);
	}

	// 4 -- signature: light-keyed inverted, so the darkest rooms burn warmest.
	static void Ember(bool surfaceOnly)
	{
		Tex(0.35, 0.045, 0.15, 1.2);
		if (surfaceOnly) return;
		Window(10, 40, 0.70, 1.00, 0.25, 0.75);
		LightDir(true);
		Lane("gitd_wf", true,  3, 0, 0, 0,  60, 1, 1.00);
		Lane("gitd_wc", true,  3, 0, 0, 0,  45, 1, 0.50);
		Lane("gitd_fg", true,  3, 0, 0, 0, 120, 1, 0.90);
		Lane("gitd_cg", false, 3, 0, 0, 0,   0, 0, 0.00);
		Throb(0.25, 0.50);
		Liquid(true, 0, 255, 90, 20, 180, 1, 1.5, true);
	}

	// 5 -- signature: sqrt falloff over a very long flat reach. Spreads wide
	// and dies slowly, rather than hugging the wall.
	static void Frostbite(bool surfaceOnly)
	{
		Cells(0.35, 32.0, 0.08, 0.70);
		if (surfaceOnly) return;
		Window(185, 215, 0.30, 0.60, 0.60, 1.00);
		Lane("gitd_wf", true, 2, 0, 0, 0,  90, 2, 0.50);
		Lane("gitd_wc", true, 2, 0, 0, 0,  90, 2, 0.50);
		Lane("gitd_fg", true, 2, 0, 0, 0, 220, 2, 0.80);
		Lane("gitd_cg", true, 2, 0, 0, 0, 160, 2, 0.60);
		Liquid(true, 0, 150, 220, 255, 200, 2, 0.9, true);
	}

	// 6 -- signature: glow-texture contrast cranked, so lit detail pops and
	// everything between it drops away.
	static void Blacklight(bool surfaceOnly)
	{
		Tex(0.80, 0.085, 0.05, 3.0);
		if (surfaceOnly) return;
		Window(275, 300, 0.85, 1.00, 0.35, 0.85);
		Lane("gitd_wf", true, 2, 0, 0, 0,  70, 3, 1.10);
		Lane("gitd_wc", true, 2, 0, 0, 0,  70, 3, 1.10);
		Lane("gitd_fg", true, 2, 0, 0, 0, 110, 3, 1.20);
		Lane("gitd_cg", true, 2, 0, 0, 0,  90, 3, 0.90);
		Liquid(true, 0, 190, 90, 255, 170, 3, 1.6, true);
	}

	// 7 -- signature: vertical asymmetry. Ceiling lanes only, tall reach,
	// explicit deep-blue far colour. Light arrives from above.
	static void Cathedral(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Lane("gitd_wf", false, 0, 0, 0, 0,     0, 0, 0.00);
		Lane("gitd_fg", false, 0, 0, 0, 0,     0, 0, 0.00);
		Lane("gitd_wc", true,  0, 255, 205, 120, 200, 2, 1.10, 2, 12, 18, 60);
		Lane("gitd_cg", true,  0, 255, 190, 110, 180, 2, 0.90, 2, 12, 18, 60);
		Wave(400, 0.15, 0.5, 1, 0.20, 0.30, 0.10);
		Liquid(true, 0, 120, 150, 255, 140, 2, 0.8, false);
	}

	// 8 -- signature: the wave origin tracks the player, so glow ripples
	// outward from wherever you are standing. The one to show people in VR.
	static void PulseWave(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Window(190, 230, 0.60, 0.90, 0.50, 1.00);
		Lane("gitd_wf", true, 0, 170, 220, 255,  70, 0, 1.00);
		Lane("gitd_wc", true, 0, 170, 220, 255,  70, 0, 0.80);
		Lane("gitd_fg", true, 0, 190, 235, 255, 130, 0, 1.10);
		Lane("gitd_cg", true, 0, 150, 200, 255, 100, 0, 0.80);
		Wave(120, 1.0, 1.8, 1, 0.50, 0.90, 0.40);
		Origin(1);
	}

	// 9 -- signature: the liquid lane carries everything; the architecture is
	// near-monochrome. Only what can hurt you glows.
	static void Hazard(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Lane("gitd_wf", true, 0, 70, 70, 72,  50, 0, 0.35);
		Lane("gitd_wc", true, 0, 70, 70, 72,  50, 0, 0.30);
		Lane("gitd_fg", true, 0, 64, 64, 66,  70, 0, 0.30);
		Lane("gitd_cg", true, 0, 64, 64, 66,  60, 0, 0.25);
		Liquid(true, 0, 90, 255, 60, 220, 3, 2.00, true);
		Throb(0.20, 0.40, 0.60);
	}

	// 10 -- signature: flow at very tight spacing and high sharpness, so it
	// reads as traces rather than as a gradient.
	static void Circuitry(bool surfaceOnly)
	{
		Flow(1.00, 12.0, 0.9, 3.0);
		Tex(0.10, 0.040, 0.0, 1.4);
		if (surfaceOnly) return;
		Window(165, 195, 0.70, 1.00, 0.50, 0.90);
		Lane("gitd_wf", true, 2, 0, 0, 0,  60, 3, 1.10);
		Lane("gitd_wc", true, 2, 0, 0, 0,  60, 3, 1.10);
		Lane("gitd_fg", true, 2, 0, 0, 0,  90, 3, 1.20);
		Lane("gitd_cg", true, 2, 0, 0, 0,  80, 3, 1.00);
	}

	// 11 -- signature: wave detune with a seed, so the bands lose phase with
	// each other instead of marching in step. Light through moving water.
	static void DeepWater(bool surfaceOnly)
	{
		Cells(0.20, 34.0, 0.12, 0.80);
		if (surfaceOnly) return;
		Window(195, 240, 0.50, 0.85, 0.35, 0.80);
		Lane("gitd_wf", true, 1, 0, 0, 0,  80, 1, 0.80);
		Lane("gitd_wc", true, 1, 0, 0, 0,  80, 1, 0.70);
		Lane("gitd_fg", true, 1, 0, 0, 0, 200, 1, 1.00);
		Lane("gitd_cg", true, 1, 0, 0, 0, 140, 1, 0.80);
		Wave(300, 0.40, 0.7, 2, 0.60, 0.50, 0.50, 0.70, 12.0);
	}

	// 12 -- signature: light-keyed FORWARD (the opposite of Ember) plus a fast
	// throb. Bright rooms run hottest.
	static void Furnace(bool surfaceOnly)
	{
		Tex(0.25, 0.030, 0.30, 1.5);
		if (surfaceOnly) return;
		Window(0, 30, 0.85, 1.00, 0.40, 1.00);
		LightDir(false);
		Lane("gitd_wf", true, 3, 0, 0, 0,  75, 1, 1.30);
		Lane("gitd_wc", true, 3, 0, 0, 0,  65, 1, 1.00);
		Lane("gitd_fg", true, 3, 0, 0, 0, 130, 1, 1.20);
		Lane("gitd_cg", true, 3, 0, 0, 0, 100, 1, 0.90);
		Throb(0.50, 0.70, 0.35);
		Liquid(true, 0, 255, 70, 15, 210, 1, 1.9, true);
	}

	// 13 -- signature: the far-colour ramp is the whole effect. Bright crimson
	// at every seam bleeding out to near-black oxblood, mottled organic by
	// cells and noise, with a long flat reach so floors look soaked rather
	// than outlined. Nothing else in the set leans on the two-colour ramp.
	static void Hellscape(bool surfaceOnly)
	{
		Cells(0.45, 22.0, 0.15, 0.55);
		Tex(0.50, 0.055, 0.08, 1.8);
		if (surfaceOnly) return;
		Window(348, 8, 0.75, 1.00, 0.30, 0.80);
		Lane("gitd_wf", true, 1, 0, 0, 0,  90, 1, 1.20, 2, 26,  4,  6);
		Lane("gitd_wc", true, 1, 0, 0, 0,  70, 1, 0.90, 2, 20,  3,  5);
		Lane("gitd_fg", true, 1, 0, 0, 0, 200, 1, 1.30, 2, 30,  5,  7);
		Lane("gitd_cg", true, 1, 0, 0, 0, 120, 1, 0.90, 2, 18,  3,  5);
		Liquid(true, 0, 200, 20, 25, 240, 1, 1.60, true);
	}

	// 14 -- signature: the throb IS the effect. No wave, no flow, no cells --
	// nothing else moving, so the pulse has the room to itself. Exponential
	// falloff on all four lanes hits hard and dies fast at the edges.
	static void RedAlert(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Lane("gitd_wf", true, 0, 255, 20, 25,  80, 3, 1.50);
		Lane("gitd_wc", true, 0, 255, 20, 25,  80, 3, 1.50);
		Lane("gitd_fg", true, 0, 255, 25, 30, 100, 3, 1.50);
		Lane("gitd_cg", true, 0, 255, 20, 25,  90, 3, 1.40);
		Throb(0.85, 0.90, 0.30);
		Liquid(true, 0, 255, 40, 40, 160, 3, 1.7, true);
	}

	// 15 -- signature: cells dense, small and slow. Flat lanes only, low
	// value. Grows on the ground rather than lighting the room.
	static void Spore(bool surfaceOnly)
	{
		Cells(0.90, 12.0, 0.05, 0.25);
		if (surfaceOnly) return;
		Window(55, 85, 0.50, 0.80, 0.20, 0.50);
		Lane("gitd_wf", false, 2, 0, 0, 0,   0, 0, 0.00);
		Lane("gitd_wc", false, 2, 0, 0, 0,   0, 0, 0.00);
		Lane("gitd_fg", true,  2, 0, 0, 0, 130, 2, 0.70);
		Lane("gitd_cg", true,  2, 0, 0, 0,  90, 2, 0.45);
		Liquid(true, 0, 140, 190, 60, 150, 2, 0.9, false);
	}

	// 16 -- signature: hard-banded wave with the wall's top and bottom half a
	// cycle apart, so the band sweeps rather than pulses flat.
	static void Signal(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Lane("gitd_wf", true, 0, 255, 180, 40,  75, 3, 1.30);
		Lane("gitd_wc", true, 0, 255, 180, 40,  75, 3, 1.30);
		Lane("gitd_fg", true, 0, 255, 190, 60, 110, 3, 1.20);
		Lane("gitd_cg", true, 0, 255, 170, 30,  90, 3, 1.00);
		Wave(180, 0.85, 4.0, 1, 0.70, 1.00, 0.00);
		Phase(0.0, 0.5, 0.25, 0.75);
	}

	// 17 -- signature: the full hue circle, but pulled right down in
	// saturation and up in value. 1.1's "colourful maps" idea as pastel
	// instead of as a rainbow assault -- and unlike 1.1, actually per sector.
	static void Prism(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Window(0, 360, 0.18, 0.35, 0.85, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  90, 0, 0.90);
		Lane("gitd_wc", true, 1, 0, 0, 0,  90, 0, 0.90);
		Lane("gitd_fg", true, 1, 0, 0, 0, 150, 0, 1.00);
		Lane("gitd_cg", true, 1, 0, 0, 0, 120, 0, 0.85);
	}

	// ---- 18-22: five built on mechanisms the first eighteen never touch ----

	// 18 -- signature: the wave measures HEIGHT, not distance from a point.
	// The crest is a horizontal plane sweeping up through the map, so a
	// stairwell reads as one rising front rather than as four surfaces taking
	// turns. Phase is deliberately flat -- per-channel offsets would break the
	// single front into the sequence Reactor already does.
	static void Ascent(bool surfaceOnly)
	{
		Tex(0.30, 0.075, 0.04, 1.6);
		if (surfaceOnly) return;
		Window(200, 260, 0.45, 0.75, 0.55, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  85, 2, 1.00);
		Lane("gitd_wc", true, 1, 0, 0, 0,  85, 2, 0.90);
		Lane("gitd_fg", true, 1, 0, 0, 0, 150, 2, 1.10);
		Lane("gitd_cg", true, 1, 0, 0, 0, 120, 2, 0.85);
		Wave(96, 0.55, 1.6, 5, 0.55, 0.75, 0.30);
		Phase(0.0, 0.0, 0.0, 0.0);
		Liquid(true, 0, 90, 170, 255, 170, 2, 1.10, true);
	}

	// 19 -- signature: ONE colour per sector across all four lanes, and no far
	// ramp anywhere. Each room is a single flat lantern; the variation is
	// between rooms and never between the surfaces of one.
	static void Beacon(bool surfaceOnly)
	{
		Tex(0.22, 0.055, 0.03, 1.3);
		if (surfaceOnly) return;
		Window(20, 55, 0.55, 0.80, 0.60, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0, 110, 0, 0.95, 0);
		Lane("gitd_wc", true, 1, 0, 0, 0,  90, 0, 0.80, 0);
		Lane("gitd_fg", true, 1, 0, 0, 0, 170, 0, 1.05, 0);
		Lane("gitd_cg", true, 1, 0, 0, 0, 140, 0, 0.85, 0);
		GITD_Util.SetB("gitd_lock_planes", true);
		// Long-hand rather than Liquid(), which forces a far ramp -- and the
		// whole point here is that nothing ramps.
		Lane("gitd_liq", true, 0, 255, 170, 80, 180, 0, 1.20, 0);
		GITD_Util.SetB("gitd_liq_on", true);
		GITD_Util.SetB("gitd_liq_walls", true);
	}

	// 20 -- signature: two different colour SOURCES at once. The floor is keyed
	// to its own material, so a metal grate glows the same colour map-wide; the
	// walls are keyed to light level, so the room's own darkness sets their hue.
	// Every other preset picks one policy and uses it on all four lanes.
	static void Trawler(bool surfaceOnly)
	{
		Flow(0.45, 14.0, 0.35, 1.6);
		Tex(0.18, 0.065, 0.03, 1.4);
		if (surfaceOnly) return;
		Window(140, 260, 0.40, 0.85, 0.35, 0.95);
		LightDir(true);
		Lane("gitd_wf", true, 3, 0, 0, 0,  70, 1, 0.85);
		Lane("gitd_wc", true, 3, 0, 0, 0,  60, 1, 0.70);
		Lane("gitd_fg", true, 2, 0, 0, 0, 165, 2, 1.15);
		Lane("gitd_cg", true, 2, 0, 0, 0, 110, 2, 0.80);
		Liquid(true, 0, 60, 200, 160, 190, 2, 1.30, true);
	}

	// 21 -- signature: reach cut to almost nothing with intensity pushed past
	// two, so every seam is a hot wire rather than a band and the room is drawn
	// as line art. The only preset whose glow stops being illumination.
	static void Filament(bool surfaceOnly)
	{
		if (surfaceOnly) return;
		Window(0, 360, 0.90, 1.00, 0.90, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0, 18, 3, 2.80);
		Lane("gitd_wc", true, 1, 0, 0, 0, 14, 3, 2.60);
		Lane("gitd_fg", true, 1, 0, 0, 0, 26, 3, 3.00);
		Lane("gitd_cg", true, 1, 0, 0, 0, 20, 3, 2.60);
		Throb(0.15, 0.30, 0.18);
		Liquid(true, 0, 255, 255, 255, 40, 3, 3.00, true);
	}

	// 22 -- signature: a wave with ZERO reach depth. It moves brightness and
	// the colour boundary only, so no edge ever travels -- the room breathes
	// without anything moving. Spherical distance, so it crosses floor, wall
	// and ceiling as one surface instead of arriving per plane.
	static void Tide(bool surfaceOnly)
	{
		Cells(0.30, 26.0, 0.06, 0.62);
		if (surfaceOnly) return;
		Window(165, 205, 0.35, 0.65, 0.50, 0.95);
		Lane("gitd_wf", true, 2, 0, 0, 0, 110, 2, 0.90);
		Lane("gitd_wc", true, 2, 0, 0, 0, 100, 2, 0.75);
		Lane("gitd_fg", true, 2, 0, 0, 0, 240, 2, 1.05);
		Lane("gitd_cg", true, 2, 0, 0, 0, 180, 2, 0.80);
		Wave(520, 0.18, 1.2, 4, 0.0, 0.85, 0.65, 0.55, 1.0);
		Phase(0.0, 0.15, 0.30, 0.45);
		Liquid(true, 0, 70, 210, 200, 220, 2, 1.20, true);
	}

	// ---- 23-27: five more, each on a lever the first twenty-three left alone -

	// 23 -- signature: wave shape 3, the only preset that uses it. The crest is
	// a vertical plane travelling along the map's OTHER ground axis, so the
	// front crosses a level sideways rather than spreading from a point (1) or
	// rising through it (5). In a long east-west map it arrives down the length
	// of the place; the same map under Pulse would light from the middle out.
	// Flow is set across it so the surface grain runs with the front.
	static void Crosswind(bool surfaceOnly)
	{
		Flow(0.35, 30.0, 0.55, 1.2);
		Tex(0.20, 0.050, 0.06, 1.3);
		if (surfaceOnly) return;
		Window(150, 215, 0.45, 0.80, 0.50, 0.95);
		Lane("gitd_wf", true, 2, 0, 0, 0,  80, 1, 1.00);
		Lane("gitd_wc", true, 2, 0, 0, 0,  70, 1, 0.85);
		Lane("gitd_fg", true, 2, 0, 0, 0, 150, 1, 1.10);
		Lane("gitd_cg", true, 2, 0, 0, 0, 110, 1, 0.80);
		Wave(260, 0.70, 1.1, 3, 0.45, 0.65, 0.25);
		Phase(0.0, 0.25, 0.0, 0.25);
		Liquid(true, 0, 80, 200, 220, 190, 2, 1.20, true);
	}

	// 24 -- signature: a wave that carries NO brightness at all. Reach and
	// bright are both zero and colour is full, so nothing gets lighter or darker
	// and nothing moves -- the hue slides through the whole circle instead, and
	// a wall you are staring at changes colour under you. Tide moves brightness
	// and colour together; this is the colour half on its own. Detuned and
	// seeded so rooms drift out of step with each other.
	static void HueDrift(bool surfaceOnly)
	{
		Tex(0.25, 0.060, 0.02, 1.2);
		if (surfaceOnly) return;
		Window(0, 360, 0.45, 0.85, 0.55, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  90, 1, 0.95);
		Lane("gitd_wc", true, 1, 0, 0, 0,  80, 1, 0.80);
		Lane("gitd_fg", true, 1, 0, 0, 0, 160, 1, 1.05);
		Lane("gitd_cg", true, 1, 0, 0, 0, 120, 1, 0.80);
		Wave(340, 0.30, 0.8, 1, 0.0, 0.0, 1.00, 0.35, 5.0);
		Liquid(true, 0, 120, 220, 160, 190, 2, 1.20, true);
	}

	// 25 -- signature: cells at triple the largest scale in the set and nearly
	// stopped. Spore's grain is small, dense and low; this is the same mechanism
	// at map scale, so instead of speckle you get slow continents of glow that
	// drift across a floor and take a corridor's length to cross. Flat lanes
	// carry it, with a long reach so it soaks rather than outlines.
	static void Moss(bool surfaceOnly)
	{
		Cells(0.80, 72.0, 0.03, 0.40);
		Tex(0.30, 0.035, 0.01, 1.1);
		if (surfaceOnly) return;
		Window(80, 140, 0.40, 0.70, 0.30, 0.70);
		Lane("gitd_wf", true, 2, 0, 0, 0,  55, 2, 0.45);
		Lane("gitd_wc", false, 2, 0, 0, 0,  0, 0, 0.00);
		Lane("gitd_fg", true, 2, 0, 0, 0, 240, 2, 1.00);
		Lane("gitd_cg", true, 2, 0, 0, 0, 120, 2, 0.55);
		Liquid(true, 0, 110, 200, 120, 190, 2, 1.00, true);
	}

	// 26 -- signature: the throb rate above 1, which nothing else does. Every
	// other throbbing preset beats slower than the level's own rate; this beats
	// well over twice it at a shallow depth, so it reads as a bad fluorescent
	// tube rather than as an alarm. Red Alert is deep, slow and red; this is
	// shallow, fast and cold white, with the grain cranked so the flicker lands
	// on detail rather than on flat colour.
	static void BadBallast(bool surfaceOnly)
	{
		Tex(0.55, 0.090, 0.0, 2.2);
		if (surfaceOnly) return;
		Window(190, 230, 0.10, 0.30, 0.85, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  65, 3, 1.20);
		Lane("gitd_wc", true, 1, 0, 0, 0,  75, 3, 1.30);
		Lane("gitd_fg", true, 1, 0, 0, 0,  90, 3, 1.00);
		Lane("gitd_cg", true, 1, 0, 0, 0, 100, 3, 1.20);
		Throb(0.45, 0.35, 2.60);
		Liquid(true, 0, 200, 220, 255, 150, 3, 1.30, true);
	}

	// 27 -- signature: the architecture does not glow AT ALL. All four lanes
	// off, the liquid lane alone, and its spill onto the walls switched off, so
	// the light stops at the edge of the nukage instead of climbing out of it.
	// Hazard leaves the walls faintly lit and lets the liquid wash up them;
	// here a pool is a hole of light in a black room, which is what makes the
	// pit read as deep.
	static void Sump(bool surfaceOnly)
	{
		Cells(0.35, 30.0, 0.05, 0.55);
		if (surfaceOnly) return;
		Lane("gitd_wf", false, 0, 0, 0, 0, 0, 0, 0.00);
		Lane("gitd_wc", false, 0, 0, 0, 0, 0, 0, 0.00);
		Lane("gitd_fg", false, 0, 0, 0, 0, 0, 0, 0.00);
		Lane("gitd_cg", false, 0, 0, 0, 0, 0, 0, 0.00);
		Liquid(true, 0, 120, 255, 90, 255, 2, 2.20, false);
		Throb(0.20, 0.35, 0.45);
	}

	// ---- 28-33: the loud end (owner, 2026-09-18: "more neon, more crazy") ---
	//
	// Same rule as the rest -- a different mechanism each -- but tuned past
	// restraint on purpose. These are the ones to look at with Bloom's Neon or
	// Emissive preset on; several of them are built to blow out.
	//
	// NAMES: nothing here is called Static. `Static()` collides with ZScript's
	// static keyword the way `Void()` collides with the void type, and both die
	// at LOAD, not at compile.

	// 28 -- signature: the far ramp crossing the colour wheel. Hellscape ramps
	// crimson to a darker crimson; this ramps hot magenta at the seam to cyan at
	// the far edge, so every surface carries both ends of the spectrum and the
	// middle of a wall is the colour in between. Flow at wide spacing lays a
	// slow grid over it. Sunset on a chrome arcade cabinet.
	static void Vaporwave(bool surfaceOnly)
	{
		Flow(0.55, 40.0, 0.30, 2.2);
		Tex(0.20, 0.050, 0.02, 1.5);
		if (surfaceOnly) return;
		Window(300, 330, 0.85, 1.00, 0.70, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  95, 1, 1.60, 2,  40, 220, 255);
		Lane("gitd_wc", true, 1, 0, 0, 0,  85, 1, 1.40, 2,  40, 220, 255);
		Lane("gitd_fg", true, 1, 0, 0, 0, 170, 1, 1.70, 2,  30, 200, 255);
		Lane("gitd_cg", true, 1, 0, 0, 0, 130, 1, 1.40, 2,  60, 120, 255);
		Liquid(true, 0, 255, 60, 200, 210, 1, 1.80, true);
	}

	// 29 -- signature: the throb at its maximum rate AND full depth, with a
	// colour rolled per sector. Bad Ballast flickers shallow and cold in one
	// colour; this is every room strobing at its own colour, hard enough to read
	// through closed eyes. The loudest preset in the mod, and the one to turn
	// off before a long session.
	static void Strobe(bool surfaceOnly)
	{
		Tex(0.15, 0.065, 0.0, 1.8);
		if (surfaceOnly) return;
		Window(0, 360, 0.90, 1.00, 0.85, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  90, 3, 1.80);
		Lane("gitd_wc", true, 1, 0, 0, 0,  90, 3, 1.80);
		Lane("gitd_fg", true, 1, 0, 0, 0, 140, 3, 2.00);
		Lane("gitd_cg", true, 1, 0, 0, 0, 110, 3, 1.70);
		Throb(1.00, 1.00, 4.00);
		Liquid(true, 0, 255, 255, 255, 200, 3, 2.40, true);
	}

	// 30 -- signature: a wave that carries the WHOLE hue circle as it travels.
	// Hue Drift slides colour with nothing moving; Prism is a static pastel
	// spread; this is a rainbow front crossing floor, wall and ceiling as one
	// sphere, bright and saturated, with the brightness riding along. Fast
	// enough that a room is never one colour for long.
	static void Chromawave(bool surfaceOnly)
	{
		Cells(0.25, 40.0, 0.20, 0.50);
		if (surfaceOnly) return;
		Window(0, 360, 0.85, 1.00, 0.80, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0, 100, 1, 1.50);
		Lane("gitd_wc", true, 1, 0, 0, 0,  95, 1, 1.40);
		Lane("gitd_fg", true, 1, 0, 0, 0, 180, 1, 1.70);
		Lane("gitd_cg", true, 1, 0, 0, 0, 140, 1, 1.40);
		Wave(240, 1.60, 1.4, 4, 0.75, 0.85, 1.00, 0.25, 7.0);
		Phase(0.0, 0.3, 0.6, 0.9);
		Liquid(true, 0, 255, 120, 255, 220, 1, 2.00, true);
	}

	// 31 -- signature: everything at once, at the top of every scale. Intensity
	// near the maximum on all four lanes over a long reach, the grain contrast
	// at the top of its range, and white-hot far colours -- built to blow past
	// 1.0 everywhere so the bloom pass has something to chew. Neon draws hard
	// edges; this is the opposite, a room with no dark left in it.
	static void Overdrive(bool surfaceOnly)
	{
		Tex(0.60, 0.040, 0.10, 4.00);
		if (surfaceOnly) return;
		Window(160, 320, 0.80, 1.00, 0.90, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0, 200, 0, 2.80, 2, 255, 255, 255);
		Lane("gitd_wc", true, 1, 0, 0, 0, 200, 0, 2.60, 2, 255, 255, 255);
		Lane("gitd_fg", true, 1, 0, 0, 0, 360, 0, 3.00, 2, 255, 255, 255);
		Lane("gitd_cg", true, 1, 0, 0, 0, 280, 0, 2.60, 2, 255, 255, 255);
		Liquid(true, 0, 255, 255, 255, 300, 0, 3.00, true);
	}

	// 32 -- signature: flow fast and tight enough to read as MOVEMENT along the
	// seams, ramped from white-hot at the seam to dead oxblood at the edge, and
	// keyed forward so the rooms the mapper lit brightest run hottest. Circuitry
	// is the same mechanism cold, sharp and still; this is the same traces
	// running molten and dripping.
	static void Veins(bool surfaceOnly)
	{
		Flow(0.90, 16.0, 2.40, 4.0);
		Cells(0.30, 18.0, 0.30, 0.35);
		Tex(0.45, 0.050, 0.25, 2.2);
		if (surfaceOnly) return;
		Window(0, 25, 0.85, 1.00, 0.55, 1.00);
		LightDir(false);
		Lane("gitd_wf", true, 3, 0, 0, 0,  70, 1, 1.90, 2, 60,  6,  4);
		Lane("gitd_wc", true, 3, 0, 0, 0,  60, 1, 1.60, 2, 46,  5,  4);
		Lane("gitd_fg", true, 3, 0, 0, 0, 150, 1, 2.20, 2, 70,  8,  5);
		Lane("gitd_cg", true, 3, 0, 0, 0, 110, 1, 1.70, 2, 40,  4,  3);
		Throb(0.30, 0.55, 1.40);
		Liquid(true, 0, 255, 140, 30, 230, 1, 2.30, true);
	}

	// 33 -- signature: a hard-banded wave detuned to its maximum with a seed, so
	// the bands never line up and the phase falls apart plane by plane. Signal
	// is the clean version of this mechanism -- one band sweeping in order; this
	// is the same thing broken, in acid green against magenta, jittering like a
	// dead channel. The sharpest wave in the set.
	static void LostSignal(bool surfaceOnly)
	{
		Tex(0.85, 0.095, 0.40, 3.4);
		if (surfaceOnly) return;
		Window(95, 320, 0.80, 1.00, 0.65, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  60, 3, 1.70);
		Lane("gitd_wc", true, 1, 0, 0, 0,  60, 3, 1.70);
		Lane("gitd_fg", true, 1, 0, 0, 0,  90, 3, 1.60);
		Lane("gitd_cg", true, 1, 0, 0, 0,  75, 3, 1.50);
		Wave(140, 2.80, 8.0, 2, 0.85, 1.00, 0.80, 1.00, 33.0);
		Phase(0.0, 0.5, 0.75, 0.25);
		Liquid(true, 0, 120, 255, 60, 170, 3, 2.00, true);
	}

	// ---- 34-42: MORE SHADES ON THE WALLS -------------------------------------
	//
	// Owner, 2026-09-18, on Deep, Frostbite, Red Alert and Hellscape: more
	// variety on the walls, a few shades either way, a step closer to neon, and
	// more wild neon ones.
	//
	// HOW THE VARIETY IS MADE, since it is not a new mechanism: the four lanes
	// hash their colour with their own salt, so under the per-sector policy each
	// lane lands somewhere ELSE in the hue window. A narrow window is one colour
	// on every surface; a wide one gives a wall, its ceiling seam and the faces
	// three related shades. The originals are deliberately narrow -- that is
	// what makes them unify a level -- so these widen the window and lift
	// saturation and value toward neon instead of changing what they are about.
	//
	// Every original is untouched: Deep, Frostbite, Red Alert, Hellscape and
	// Cathedral are still exactly what they were.

	// 34 -- DEEP, WIDER AND HOTTER. Its window opens from 45 degrees of blue to
	// 70 through indigo, and saturation goes up rather than down, so a corridor
	// reads as several blues lit from inside instead of one.
	static void Abyssal(bool surfaceOnly)
	{
		Cells(0.22, 36.0, 0.10, 0.75);
		if (surfaceOnly) return;
		Window(185, 255, 0.70, 1.00, 0.45, 0.95);
		Lane("gitd_wf", true, 1, 0, 0, 0,  95, 1, 1.15);
		Lane("gitd_wc", true, 1, 0, 0, 0,  90, 1, 1.00);
		Lane("gitd_fg", true, 1, 0, 0, 0, 220, 1, 1.25);
		Lane("gitd_cg", true, 1, 0, 0, 0, 160, 1, 0.95);
		Wave(300, 0.40, 0.7, 2, 0.55, 0.45, 0.55, 0.70, 12.0);
		Liquid(true, 0, 40, 180, 255, 210, 1, 1.50, true);
	}

	// 35 -- FROSTBITE AT FULL BRIGHTNESS. The same long sqrt reach that made it
	// spread and die slowly, with the window widened through cyan and the value
	// pushed to the top: ice under a strip light rather than ice at dusk.
	static void Glacier(bool surfaceOnly)
	{
		Cells(0.40, 30.0, 0.06, 0.65);
		Tex(0.25, 0.060, 0.02, 1.4);
		if (surfaceOnly) return;
		Window(168, 215, 0.45, 0.85, 0.80, 1.00);
		Lane("gitd_wf", true, 2, 0, 0, 0, 110, 2, 0.90);
		Lane("gitd_wc", true, 2, 0, 0, 0, 110, 2, 0.90);
		Lane("gitd_fg", true, 2, 0, 0, 0, 260, 2, 1.20);
		Lane("gitd_cg", true, 2, 0, 0, 0, 190, 2, 1.00);
		Liquid(true, 0, 170, 235, 255, 230, 2, 1.30, true);
	}

	// 36 -- RED ALERT, NOT ALL ONE RED. Red Alert is one fixed crimson on every
	// surface, which is what makes it an alarm; this rolls each lane through
	// crimson to amber, so the room is still alarmed but reads as several
	// warning lights rather than one wash. The throb is kept and slowed.
	static void Klaxon(bool surfaceOnly)
	{
		Tex(0.20, 0.070, 0.0, 1.6);
		if (surfaceOnly) return;
		Window(345, 30, 0.85, 1.00, 0.60, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  80, 3, 1.50);
		Lane("gitd_wc", true, 1, 0, 0, 0,  80, 3, 1.50);
		Lane("gitd_fg", true, 1, 0, 0, 0, 110, 3, 1.45);
		Lane("gitd_cg", true, 1, 0, 0, 0,  95, 3, 1.35);
		Throb(0.70, 0.75, 0.45);
		Liquid(true, 0, 255, 80, 40, 180, 3, 1.70, true);
	}

	// 37 -- HELLSCAPE, LIT RATHER THAN SOAKED. The same two-colour ramp down to
	// oxblood, but the near end walks crimson to ember-orange per lane and the
	// value comes up, so the seams burn instead of the room being one red bath.
	static void Inferno(bool surfaceOnly)
	{
		Cells(0.45, 20.0, 0.18, 0.50);
		Tex(0.45, 0.050, 0.12, 2.0);
		if (surfaceOnly) return;
		Window(350, 38, 0.80, 1.00, 0.55, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  85, 1, 1.40, 2, 36,  6,  6);
		Lane("gitd_wc", true, 1, 0, 0, 0,  70, 1, 1.15, 2, 28,  5,  5);
		Lane("gitd_fg", true, 1, 0, 0, 0, 190, 1, 1.55, 2, 42,  8,  6);
		Lane("gitd_cg", true, 1, 0, 0, 0, 120, 1, 1.10, 2, 24,  4,  5);
		Liquid(true, 0, 255, 90, 25, 240, 1, 1.80, true);
	}

	// ---- the wild end -------------------------------------------------------

	// 38 -- NEON PURPLE, HARD. Blacklight's part of the spectrum at full
	// saturation with an exponential falloff and a short reach, so every seam is
	// a purple tube and the middle of the wall stays dark.
	static void Ultraviolet(bool surfaceOnly)
	{
		Tex(0.55, 0.080, 0.03, 2.6);
		if (surfaceOnly) return;
		Window(262, 320, 0.90, 1.00, 0.75, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  45, 3, 1.90);
		Lane("gitd_wc", true, 1, 0, 0, 0,  45, 3, 1.90);
		Lane("gitd_fg", true, 1, 0, 0, 0,  70, 3, 1.80);
		Lane("gitd_cg", true, 1, 0, 0, 0,  60, 3, 1.70);
		Liquid(true, 0, 220, 60, 255, 200, 3, 2.00, true);
	}

	// 39 -- NEON GREEN AND YELLOW, WITH TRACES RUNNING. Circuitry's flow at a
	// wider spacing under an acid window, so the traces read as lit tubing
	// rather than as circuitry. The most toxic-looking of the set.
	static void Acid(bool surfaceOnly)
	{
		Flow(0.85, 20.0, 1.30, 2.6);
		Tex(0.30, 0.055, 0.06, 1.8);
		if (surfaceOnly) return;
		Window(68, 112, 0.90, 1.00, 0.80, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  70, 2, 1.60);
		Lane("gitd_wc", true, 1, 0, 0, 0,  65, 2, 1.50);
		Lane("gitd_fg", true, 1, 0, 0, 0, 130, 2, 1.70);
		Lane("gitd_cg", true, 1, 0, 0, 0, 100, 2, 1.40);
		Liquid(true, 0, 140, 255, 40, 230, 2, 1.90, true);
	}

	// 40 -- TWO NEONS AT ONCE. Hot pink at the seam ramping to electric cyan at
	// the far edge, explicit on every lane, so one wall carries both ends of a
	// neon sign. Vaporwave ramps across the wheel too, but slowly and softly;
	// this is the same idea at full saturation with a short, hard reach.
	static void Bubblegum(bool surfaceOnly)
	{
		Tex(0.18, 0.045, 0.02, 1.5);
		if (surfaceOnly) return;
		Window(300, 345, 0.95, 1.00, 0.85, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  60, 3, 1.70, 2, 30, 230, 255);
		Lane("gitd_wc", true, 1, 0, 0, 0,  60, 3, 1.70, 2, 30, 230, 255);
		Lane("gitd_fg", true, 1, 0, 0, 0, 100, 3, 1.80, 2, 20, 210, 255);
		Lane("gitd_cg", true, 1, 0, 0, 0,  85, 3, 1.60, 2, 60, 180, 255);
		Liquid(true, 0, 255, 60, 200, 220, 3, 2.00, true);
	}

	// 41 -- ELECTRIC. A near-white blue at the top of the value range on a very
	// short reach, with a fast shallow throb: the seams read as live wiring
	// rather than as lighting. Filament draws a room as line art in white; this
	// is the same thinness with a colour and a pulse.
	static void Voltage(bool surfaceOnly)
	{
		Tex(0.35, 0.095, 0.05, 2.4);
		if (surfaceOnly) return;
		Window(188, 214, 0.55, 0.85, 0.95, 1.00);
		Lane("gitd_wf", true, 1, 0, 0, 0,  28, 3, 2.30);
		Lane("gitd_wc", true, 1, 0, 0, 0,  24, 3, 2.20);
		Lane("gitd_fg", true, 1, 0, 0, 0,  40, 3, 2.40);
		Lane("gitd_cg", true, 1, 0, 0, 0,  34, 3, 2.10);
		Throb(0.35, 0.40, 2.20);
		Liquid(true, 0, 200, 240, 255, 190, 3, 2.20, true);
	}

	// 42 -- CATHEDRAL WITH A FLOOR. Cathedral lights a room only from above: its
	// wall-from-floor and floor lanes are off, so the bottom of the room has no
	// colour at all, and its deep-blue far end sits 200 units down a wall where
	// most rooms never reach it. This keeps the light from above and gives the
	// floor a cold pool to answer it, so the blue is somewhere you can see.
	static void Nave(bool surfaceOnly)
	{
		Tex(0.20, 0.050, 0.01, 1.3);
		if (surfaceOnly) return;
		Lane("gitd_wf", true, 0,  40,  70, 140,  70, 2, 0.60, 2, 10, 14, 44);
		Lane("gitd_fg", true, 0,  30,  60, 130, 150, 2, 0.75, 2,  8, 12, 40);
		Lane("gitd_wc", true, 0, 255, 205, 120, 200, 2, 1.10, 2, 12, 18, 60);
		Lane("gitd_cg", true, 0, 255, 190, 110, 180, 2, 0.90, 2, 12, 18, 60);
		Wave(400, 0.15, 0.5, 1, 0.20, 0.30, 0.10);
		Liquid(true, 0, 120, 150, 255, 140, 2, 0.8, false);
	}
}
