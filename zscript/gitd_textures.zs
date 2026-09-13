// RS_GlowInTheDark -- SURFACE TEXTURE, AS ITS OWN LAYER.
//
// The grain, the scanlines and the cracks used to be part of whichever preset
// happened to include them. That made the best-looking part of the effect the
// hardest to get at: the tight traces only existed inside Circuitry, the
// crazed cracks only inside Spore, and wanting either on top of some other
// palette meant editing a preset by hand.
//
// So the texture is lifted out. A preset still carries its own as before and
// that is still the default, but the texture can now be chosen independently
// and lands on whatever palette is underneath.
//
// THREE TERMS, and they are separate things that get confused:
//
//   GRAIN    gitd_tex_*   value noise over the surface. Dirt, not structure.
//   FLOW     gitd_flow*   bands running along the glow. Tight and sharp reads
//                         as scanlines or circuit traces; loose and soft reads
//                         as a slow pulse travelling down a lane.
//   CELLS    gitd_cell*   a cell pattern. Wide edges read as frost or mottle;
//                         narrow edges on small cells read as cracks.
//
// A style here is free to set all three, and the good ones do -- layering was
// the other thing barely used: only Hellscape (grain under cells), Circuitry
// and Trawler (grain under flow) combine two.

class GITD_Textures
{
	// Order is the menu order.
	const T_PRESET    = 0;   // leave whatever the preset chose
	const T_NONE      = 1;
	const T_GRAIN     = 2;
	const T_DIRT      = 3;
	const T_SCANLINES = 4;
	const T_TRACES    = 5;
	const T_PULSEBAND = 6;
	const T_CRACKS    = 7;
	const T_CRAZED    = 8;
	const T_FROST     = 9;
	const T_MOTTLE    = 10;
	const T_SCALES    = 11;
	const T_ETCHED    = 12;
	const T_CORRODED  = 13;
	const T_WEAVE     = 14;

	static void F(String n, double v) { let c = CVar.FindCVar(n); if (c) c.SetFloat(v); }

	static void Grain(double amount, double scale, double drift, double contrast)
	{
		F("gitd_tex_noise", amount); F("gitd_tex_scale", scale);
		F("gitd_tex_drift", drift);  F("gitd_tex_contrast", contrast);
	}

	static void Flow(double amount, double spacing, double speed, double sharp)
	{
		F("gitd_flow", amount); F("gitd_flow_spacing", spacing);
		F("gitd_flow_speed", speed); F("gitd_flow_sharp", sharp);
	}

	static void Cells(double amount, double scale, double speed, double width)
	{
		F("gitd_cell", amount); F("gitd_cell_scale", scale);
		F("gitd_cell_speed", speed); F("gitd_cell_width", width);
	}

	// Every style states all three, including the zeros. A style that set only
	// its own term would inherit the others from whatever ran before it, which
	// is how you get a preset wearing half of the last one.
	static void Clear()
	{
		Grain(0.0, 0.06, 0.0, 1.0);
		Flow(0.0, 12.0, 1.0, 1.0);
		Cells(0.0, 24.0, 0.2, 0.5);
	}

	static void Apply(int idx)
	{
		// The preset's own. SyncPreset puts it back with
		// GITD_Presets.Apply(preset, true) before calling here, so there is
		// nothing left for this to write.
		if (idx == T_PRESET) return;

		Clear();
		switch (idx)
		{
		default:
		case T_NONE:      break;

		// ---- grain -------------------------------------------------------
		case T_GRAIN:     Grain(0.25, 0.070, 0.02, 1.6); break;
		case T_DIRT:      Grain(0.80, 0.085, 0.05, 3.0); break;   // Blacklight's

		// ---- flow: the line looks ----------------------------------------
		// Tight spacing plus high sharpness is what makes a band read as a
		// LINE rather than as a gradient. This is the term that was in one
		// preset only.
		case T_SCANLINES: Flow(0.90, 7.0, 0.5, 4.0); break;   // fine, dense, slow
		case T_TRACES:    Flow(1.00, 12.0, 0.9, 3.0); break;   // Circuitry's
		case T_PULSEBAND: Flow(0.70, 40.0, 1.1, 1.3); break;   // wide soft sweep

		// ---- cells: the crack looks --------------------------------------
		// Small cells with narrow edges read as a crazed surface; large cells
		// with wide edges read as frost or as leather.
		case T_CRACKS:    Cells(0.85, 22.0, 0.04, 0.28); break;
		case T_CRAZED:    Cells(0.95, 14.0, 0.03, 0.18); break;   // finer, harder
		case T_FROST:     Cells(0.40, 30.0, 0.08, 0.70); break;   // Frostbite's, a shade stronger
		case T_MOTTLE:    Cells(0.50, 24.0, 0.15, 0.55); break;
		case T_SCALES:    Cells(0.70, 18.0, 0.10, 0.40); break;

		// ---- layered: two terms at once ----------------------------------
		// Grain under structure. Hellscape, Circuitry and Trawler are the
		// presets that do this, and it is most of why Hellscape reads as a
		// material rather than as a pattern.
		case T_ETCHED:
			Grain(0.18, 0.100, 0.01, 2.0);
			Flow(0.75, 9.0, 0.4, 3.5);
			break;
		case T_CORRODED:
			Grain(0.45, 0.050, 0.06, 1.8);
			Cells(0.55, 26.0, 0.05, 0.30);
			break;
		case T_WEAVE:
			Flow(0.55, 11.0, 0.6, 2.6);
			Cells(0.45, 28.0, 0.06, 0.35);
			break;
		}
	}
}
