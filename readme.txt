GlowInTheDark 2.0
=================

A ZScript rewrite of GlowInTheDark 1.1 (PresidentKoopa, 2021) for UZDXREMA.
Same name, almost nothing else in common -- the original was ACS and could only
reach a fifth of the engine's glow stack.


WHY IT WAS REWRITTEN
--------------------

Tracing 1.1 through the engine turned up three things:

* It only ever lit WALLS. ACS SetSectorGlow writes planes[].GlowColor and
  nothing else (ACSF_SetSectorGlow in p_acs.cpp). Floor and ceiling faces were
  never touched, so the engine's entire flat-glow system was invisible to it.

* Its randomisation never happened. The first argument is a sector TAG, not an
  index, and tag 0 matches every UNTAGGED sector at once
  (FSectorTagIterator::Next in p_tags.cpp). random() is evaluated once per
  call, so the whole map got a single shared colour. Everything after tag 0
  hit only doors and lifts.

* Its throttle test was inverted, so those doors and lifts arrived at about one
  per tic -- roughly 47 minutes to finish a sweep.

Colours were also read once before the loop, which is why 1.1's menu says
changes need a map restart.


WHAT THIS DOES INSTEAD
----------------------

Four lanes, each independently configured:

  wf   wall above the floor seam       (reach is VERTICAL, up the wall)
  wc   wall below the ceiling seam     (reach is VERTICAL, down the wall)
  fg   the floor's own face            (reach is HORIZONTAL, inward from edges)
  cg   the ceiling's own face          (reach is HORIZONTAL, inward from edges)

Both systems call their reach "height" in the engine, and they mean different
axes. The menu labels which is which.

Four colour sources, selectable per lane:

  Fixed              one colour everywhere
  Random per sector  stable-hashed, so sliders re-tint without reshuffling
  Texture/material   same flat, same colour, map-wide, no texture table
  Light level        keyed to the sector's own brightness, direction switchable

All of them land in the same HSV window, so the Randomiser page's hue,
saturation and value ranges bound every source except Fixed.

The light and texture sources read the MAP, not a setting, so the map is
watched about once a second as well: a light raised by a trigger, or a floor
that changes flat, re-tints on its own. Light keys on the brightest level a
sector has been seen at, so a flickering sector holds one colour instead of
changing every time something re-applies. The cost: a light switched OFF keeps
the colour it had while lit.

An Intensity of 0 switches a lane off. (The engine reads 0 as "unset" and would
draw it at full brightness, so the mod treats it as off itself.)

SEAMLESS CORNERS
----------------

Options > GlowInTheDark > Seamless corners. On by default.

The gradient at a corner was never missing. The wall's glow fades UPWARD from
the floor line; the floor's edge glow fades INWARD from that same line. Two
ramps meeting nose to nose, both at FULL strength exactly where they touch.
The hard cut is not an absence of blending -- it is the two sides disagreeing
about what colour to be AT the line they share.

So it is the NEAR colours that have to agree, because they are the ones that
meet. With this on, both lanes take the junction colour at the line. A lane
whose far colour is Auto gets its own colour as the far end, which is what lets
a corner still read floor-purple into wall-blue rather than collapsing into one
flat wash of the average. A lane with an Explicit far colour keeps it (that is
Hellscape's whole look), and a lane with its far colour Off stays one colour.

Each lane keeps its own reach, falloff and intensity. "Match reach and falloff
too", off by default, makes the floor and ceiling faces take the wall lane's
shape at the corner as well -- a ramp that changes width or curve across a
corner can read as a seam -- but with it on, the Floor Face and Ceiling Face
Reach, Falloff and Intensity sliders do nothing wherever a wall lane meets them.

Two things it deliberately does not do:

* If only one of the two lanes at a corner is enabled there is no corner --
  just a single glow -- so that lane keeps its own colour rather than agreeing
  with a surface that is not being drawn.

* It is IGNORED while a Wave is running, enforced in code rather than left to
  you. A wave moves reach per pixel, so undulating one side reopens the seam
  it just closed and the seam then travels. Eight of the presets run waves.
  Either the room is bounded by continuous colour with no edge, or the edge
  moves.

Not to be confused with "All four lanes share one colour" on the Randomiser
page, which forces every lane to the same colour outright (under the Texture
source, every lane keys on the floor's flat). That also removes the seam, but
by flattening the look, and it does nothing under Fixed.

LIQUIDS
-------

A floor is a liquid when the map's terrain definitions say so
(TerrainDef.IsLiquid) -- that covers Heretic, Hexen, Strife and any map or mod
with its own TERRAIN lump. The engine's terrain.txt has no Doom floors at all,
so the stock Doom liquid flats are also matched by name: NUKAGE, FWATER,
SWATER, LAVA, BLOOD, SLIME01-12 and RROCK05-08. Liquids override the floor lane
and get their own config. This is what replaces 1.1's gldefs.bm, and it lights
the liquid's own surface, which GLDEFS-based glow never did.

PRESETS AND TEXTURE
-------------------

Twenty-three presets, each built around a different mechanism rather than a
different palette -- if two of them look alike, that is a bug.

The Texture option picks the surface (grain, flow lines, cells) separately from
the preset. "From the preset" puts back the current preset's own surface and
touches nothing else; picking a PRESET rewrites every setting.

Sector iteration is by index over Level.Sectors, chunked at 2000 per tic over
two passes (resolve every colour, then blend and write). A 5000-sector map
completes in six tics.


NOTHING NEEDS A MAP RESTART
---------------------------

Lane changes re-apply within about five tics. Wave and Surface Detail push
every tic.

Everything the menus change is pushed from UiTick as well as WorldTick, so it
keeps moving while the game is PAUSED and while the menu is open -- the
per-pixel layer (Wave, Surface Detail, the alarm) and the four lanes alike.
Drag a lane or cells slider with the menu up and the map re-tints under it.
That is what the fork's clearscope declarations on the glow setters are for.

RS_SWEEPS
---------

A sweep's glow effects repaint the rooms it crosses in the sweep's colour, and
that colour is meant to stay. This mod passes those rooms by -- on a settings
change, on the light and flat watch, and when it is switched off -- so the two
no longer fight. Only the parts the sweep painted are skipped: a sweep that
left the walls alone leaves them to this mod.

The sweep leaves a claim marker per room, found here by class name at run
time, so neither mod needs the other loaded. Switch the sweep's glow effect off
and its claims go; within about a second this mod repaints those rooms in its
own colours.

SAVES
-----

A savegame keeps every glow field of every floor and ceiling: colour, height,
far colour, falloff, intensity and all of the flat glow. A loaded game comes
back looking the way it was saved. The mod still re-applies the whole map on
load, which repaints the same colours; a save made with an older engine, which
kept only the wall glow colour and height, has its floors and ceilings dark for
the few tics that takes. Loading a save also keeps the preset and tuning the
save was made with -- it is not treated as a preset change -- and a load or hub
return never shuffles.

RANDOMIZE ON DEATH
------------------

Options > GlowInTheDark > Randomize on death.

  New colours   same preset, new seed -- the look you tuned holds, the map
                re-tints. A light-keyed preset turns its hue window instead,
                and a preset with only fixed colours has nothing to re-tint,
                so it rolls a new preset.
  New preset    a different look entirely each time you die

Rolls skip preset 0 (Vanilla+), because landing on the deliberately restrained
one reads as the mod having switched itself off, and never land on the preset
already showing. Same rule as map shuffle.


TESTING IT
----------

Load it alone first, with the old Environmental_Lighting03_GlowInTheDark.pk3
UNLOADED -- both write GlowColor and they will fight.

1. Prove the flat lanes. Options > GlowInTheDark > Floor Face. Turn off the two
   wall lanes, set Floor Face to a saturated fixed colour with reach ~200.
   The FLOOR SURFACE should light up, not just the wall beside it. This is the
   thing 1.1 could not do at all; if it does not work, nothing else matters.

2. Prove liveness. Drag any lane slider with the menu open. It should re-tint
   within a fifth of a second with no hitch.

3. Prove stability. Drag a Randomiser slider. Sector colours should shift as a
   group, never reshuffle.

4. Prove liquids. Doom II MAP02 or any map with nukage or lava, Liquids page
   enabled.

5. Walk all twenty-three presets on one map.

6. Big map, 5000+ sectors, watch for a spike when a setting changes.

7. Save, change preset, load. The saved look should come back, floors included.


THINGS I COULD NOT VERIFY WITHOUT RUNNING IT
--------------------------------------------

Being explicit about these rather than letting you find them:

* Wave "shape" is exposed as 1-5 (the menu's list). The engine accepts 0-9;
  0 draws the same as 1, and 6-9 are not offered here.

* "Disturbance reach" on the Surface Detail page is inert on its own. The
  engine's react parameter only scales the fog-disturbance array, which this
  mod never populates (SetGlowReact in vmthunks.cpp). It is exposed for other
  mods that do. The throb in Red Alert and elsewhere comes from pulse/level,
  which are self-contained.

* Flat glow uses at most 64 of a sector's edges (the count is clamped in
  HWFlat::DrawFlat, hw_flats.cpp). Very large or very complex sectors may glow
  from only part of their perimeter. Nothing to do about it mod-side.

* All preset values are chosen from the parameter semantics, not from looking
  at them. Expect to want to tune them.


FILES
-----

  cvarinfo              92 CVars, archived so settings persist
  menudef               main page plus eight submenus
  mapinfo               registers the event handler (without this: nothing)
  zscript.txt           version guard and includes
  zscript/gitd_util.zs      hashing, HSV, far-colour derivation, CVar helpers
  zscript/gitd_policy.zs    the four colour sources, liquid detection
  zscript/gitd_presets.zs   the twenty-three looks
  zscript/gitd_textures.zs  the surface textures, chosen apart from the preset
  zscript/gitd_handler.zs   applies lanes, drives the per-pixel layer

ENGINE
------

This needs UZDXREMA. It is not a stock GZDoom mod: flat glow, far colours,
falloff and intensity, the glow wave, surface texture, flow, cells and the
alarm pulse are all fork additions, and so are the clearscope glow setters that
let the menus re-tint the map while paused.
