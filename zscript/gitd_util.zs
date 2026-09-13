// GlowInTheDark 2.0 -- shared helpers.
//
// Everything here is pure. That is deliberate and it is what makes the
// randomiser stable: a sector's colour is recomputed from scratch on every
// apply and lands on the same value, so dragging a slider re-tints the map
// without reshuffling it. 1.1 could not do this -- it called random() once
// per SetSectorGlow and had no way back to a colour it had already used.

class GITD_Util
{
	// ---- hashing -----------------------------------------------------------

	// Murmur3 finalizer. Cheap, and it avalanches properly -- which matters
	// here, because the input is a sequential sector index. A weak hash on
	// 0,1,2,3... gives a gradient across the map instead of a scatter.
	clearscope static uint Hash(uint x)
	{
		x ^= x >> 16;
		x *= 0x7feb352d;
		x ^= x >> 15;
		x *= 0x846ca68b;
		x ^= x >> 16;
		return x;
	}

	clearscope static uint Mix(uint a, uint b, uint c)
	{
		return Hash(Hash(a ^ 0x9e3779b9) ^ Hash(b ^ 0x85ebca6b) ^ Hash(c));
	}

	// FNV-1a, for texture-name keyed colour: the same flat gets the same
	// colour everywhere on the map with no hand-written table to maintain.
	clearscope static uint HashString(String s)
	{
		uint h = 2166136261;
		int n = s.Length();
		for (int i = 0; i < n; i++)
		{
			h ^= uint(s.ByteAt(i));
			h *= 16777619;
		}
		return h;
	}

	// A hash as 0..1.
	clearscope static double Unit(uint h)
	{
		return double(h & 0xFFFFFF) / double(0xFFFFFF);
	}

	// ---- interpolation -----------------------------------------------------

	clearscope static double Lerp(double a, double b, double t)
	{
		return a + (b - a) * t;
	}

	// Hue ranges wrap. min 330 / max 30 means "through red", not "everything
	// except red" -- which is the range you actually want for the warm presets.
	clearscope static double LerpHue(double lo, double hi, double t)
	{
		if (hi < lo) hi += 360.0;
		return Lerp(lo, hi, t);
	}

	// ---- colour ------------------------------------------------------------

	// h wraps, s and v clamp.
	//
	// Alpha is ALWAYS 255, and that is not cosmetic: flat glow is gated on
	// FlatGlowColor.a > 0 (HWFlat::DrawFlat, hw_flats.cpp). A zero-alpha
	// colour silently switches the entire lane off with no error anywhere.
	clearscope static Color HSV(double h, double s, double v)
	{
		h = h - 360.0 * floor(h / 360.0);
		s = clamp(s, 0.0, 1.0);
		v = clamp(v, 0.0, 1.0);

		double hp = h / 60.0;
		int seg = int(hp) % 6;
		double f = hp - floor(hp);

		double p = v * (1.0 - s);
		double q = v * (1.0 - s * f);
		double t = v * (1.0 - s * (1.0 - f));

		double r, g, b;
		if      (seg == 0) { r = v; g = t; b = p; }
		else if (seg == 1) { r = q; g = v; b = p; }
		else if (seg == 2) { r = p; g = v; b = t; }
		else if (seg == 3) { r = p; g = q; b = v; }
		else if (seg == 4) { r = t; g = p; b = v; }
		else               { r = v; g = p; b = q; }

		return Color(255,
			int(r * 255.0 + 0.5),
			int(g * 255.0 + 0.5),
			int(b * 255.0 + 0.5));
	}

	// Inverse, so the auto far-colour can rotate hue rather than only dim.
	clearscope static void ToHSV(Color c, out double h, out double s, out double v)
	{
		double r = c.r / 255.0;
		double g = c.g / 255.0;
		double b = c.b / 255.0;

		double mx = max(r, max(g, b));
		double mn = min(r, min(g, b));
		double d = mx - mn;

		v = mx;
		s = mx > 0.0 ? d / mx : 0.0;

		if (d <= 0.0) { h = 0.0; return; }

		if (mx == r)      h = 60.0 * ((g - b) / d);
		else if (mx == g) h = 60.0 * ((b - r) / d + 2.0);
		else              h = 60.0 * ((r - g) / d + 4.0);

		h = h - 360.0 * floor(h / 360.0);
	}

	// The colour a glow fades TOWARD.
	//
	// Deriving this instead of defaulting it to black is what makes the
	// wall/flat corner ramp continuously with zero configuration -- give the
	// wall's bottom glow and the floor's own glow the same far colour and the
	// seam between them stops being an edge (Sector.SetGlowColorFar,
	// mapdata.zs). Real light both dims and cools as it falls off, so this
	// darkens, enriches slightly, and rotates a little toward blue.
	clearscope static Color AutoFar(Color base)
	{
		double h, s, v;
		ToHSV(base, h, s, v);
		return HSV(h - 12.0, clamp(s * 1.15, 0.0, 1.0), v * 0.22);
	}

	// Packed RGB, for holding a resolved colour per sector between the resolve
	// and apply passes. Alpha is always 255 here so it does not need storing.
	clearscope static int Pack(Color c)
	{
		return (c.r << 16) | (c.g << 8) | c.b;
	}

	clearscope static Color Unpack(int v)
	{
		return Color(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
	}

	// Weighted mix. t=0 is all a, t=1 is all b.
	clearscope static Color LerpCol(Color a, Color b, double t)
	{
		t = clamp(t, 0.0, 1.0);
		return Color(255,
			int(a.r + (b.r - a.r) * t + 0.5),
			int(a.g + (b.g - a.g) * t + 0.5),
			int(a.b + (b.b - a.b) * t + 0.5));
	}

	// Midpoint of two colours. Used by the seamless option: the far colour a
	// corner ramps toward should sit between the two surfaces meeting there,
	// not favour either one.
	clearscope static Color Blend(Color a, Color b)
	{
		return Color(255,
			(a.r + b.r) / 2,
			(a.g + b.g) / 2,
			(a.b + b.b) / 2);
	}

	// Colour CVars come back with no alpha bits set. Rebuilding with alpha
	// forced is mandatory -- see the note on HSV() above.
	// clearscope because GetC() below is, and a clearscope caller cannot reach
	// a play-scope helper.
	clearscope static Color FromCVar(CVar c)
	{
		if (!c) return Color(255, 128, 128, 128);
		int v = c.GetInt();
		return Color(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
	}

	// ---- cvar shorthand ----------------------------------------------------

	// clearscope throughout: the per-pixel layer is pushed from UiTick so that
	// menu sliders move the picture while the game is paused, and a ui-scope
	// caller cannot reach a play-scope helper.
	clearscope static double GetF(String name, double def = 0.0)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : def;
	}

	clearscope static int GetI(String name, int def = 0)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetInt() : def;
	}

	clearscope static bool GetB(String name, bool def = false)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetBool() : def;
	}

	clearscope static Color GetC(String name)
	{
		return FromCVar(CVar.FindCVar(name));
	}

	clearscope static void SetF(String name, double v)
	{
		let c = CVar.FindCVar(name);
		if (c) c.SetFloat(v);
	}

	clearscope static void SetI(String name, int v)
	{
		let c = CVar.FindCVar(name);
		if (c) c.SetInt(v);
	}

	clearscope static void SetB(String name, bool v)
	{
		let c = CVar.FindCVar(name);
		if (c) c.SetBool(v);
	}

	// Colour CVars store packed RGB; alpha is added on read, not on write.
	static void SetC(String name, int r, int g, int b)
	{
		let c = CVar.FindCVar(name);
		if (c) c.SetInt(((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF));
	}
}
