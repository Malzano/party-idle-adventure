# BinkBonk Idle — Lore Bible: The Meadow, the Four, and the Clubs

> Companion to [ARCHITECTURE.md](ARCHITECTURE.md). Everything here is written to fit the
> names already shipped in the game (BinkBonk Meadow, the Mushroom King, the Crown of the
> First Star, faction tags EMB/ASH/HLW/LNT, guilds like "Waffle Squad"…), so wiring story
> text into screens later needs no retcons. Mechanical numbers quoted for factions exist as
> a data stub in `GameContent.FACTIONS` (StatBlock-parsable strings) — designed now, wired
> when the faction choice ships (see TODO).
>
> **Tone contract:** cozy, cute, and gently silly (Soul Strike / MapleStory energy).
> Danger is real but never grim — baddies get *bonked*, nobody gets hurt-hurt, and
> everything ends with snacks.

---

## 1. The world in one page

Long ago a wishing star came down softly in the middle of a great meadow, and where it
landed the world went **fizzy**: mushrooms grew doors, snails learned to sneak, slimes
turned friendly-ish (they still want hugs; their hugs sting a bit). The star's light rolls
out from the crater in waves — stage after stage of glimmering paths, going deeper and
deeper toward the buried starlight (this is what the player pushes through: act after act,
the meadow deals out its trails one wave at a time).

The fizzy creatures aren't evil. They're **overexcited**. **Gloopy Slimes** bounce along
old berry lanes, **Sneaky Snails** slow-race through the dew, and beneath the biggest
toadstool sits the **Mushroom King**, who mostly wants everyone to admire his cap. They
crowd the paths, so adventurers *bonk* them — a bonk is a firm, friendly thump that pops a
creature back into sparkles and coins. No hard feelings. They reform at home by teatime.

At the edge of it all sits **BinkBonk Meadow** — the camp: half picnic, half headquarters.
A **Bulletin Board** for quests and rankings. A **Tinker Shop** that hammers gear back
into shape (with glue and glitter). A **Snack Shack** where a warm meal buffs the whole
party. A **Wishing Well** where stardrops go in and wonderful new gear splashes out (the
gacha: the star grants wishes, for a price, *almost* exactly what you asked for). Treasure
turns up too: **Battle Caches** — picnic hampers nobody ever unpacked — and, once in a
long while, a **mythic** wonder of the first starfall: the *Crown of the First Star*, the
*Heart of the Meadow King*, *Starsplitter*, even *The Legendary Spatula*. When one turns
up, every campfire in the meadow hears about it by supper (the global mythic ribbon).

Why adventure? Coins, glory, snacks. Everyone at the hearth wants to see the buried
starlight at least once. **Seasons** are the meadow's calendar: each season the star
"sneezes" — the paths reshuffle, the boards reset, and the race to the deep starts again,
giggling.

And through the **Stampede Gate** shimmers the **Star Stampede**: a pocket of the meadow
where the fizz never settles — baddies pour in from every direction and one brave soul
with a well-packed backpack skips, bonks, and levels until they're all tuckered out.

The four people at the Snug Hearth on the login screen are the four ways of answering the
meadow: hug it head-on (Warrior), out-sparkle it (Mage), out-snack it (Hunter), or
out-sneak it (Rogue).

---

## 2. Character storylines

Each storyline runs the same five-act spine the sim already walks (50 stages per act),
with a personal thread per class. Beats are written as one-line hooks so they can become
stage-intro cards, Bulletin Board letters, or codex entries without rework.

### 2.1 The Warrior — *the Big-Hearted* (STR · VIT)

Raised on porridge and pillow forts; walks in front so nobody else has to.

- **Act I — The First Bonk.** Adopts the whole party on day one. Nobody agreed to this.
- **Act II — The Unbudgeable.** Discovers that standing very still is a martial art.
- **Act III — Shield Meets Snail.** A Sneaky Snail refuses to be bonked. A rivalry (and
  eventually a friendship) begins.
- **Act IV — The Long Carry.** Carries the entire party's snacks up Starfall Slopes.
  Complains zero times. Glows about it for a week.
- **Act V — The Gentle Wall.** At the star's edge, learns the biggest bonk of all is
  choosing not to bonk. Bonks anyway, but *kindly*.

### 2.2 The Mage — *the Plucky* (INT)

A certified Sparkmage whose wand runs on fizzy starlight and enthusiasm.

- **Act I — Sparkles 101.** First bolt pops like a firework and smells of toasted
  marshmallow. Immediately does it again.
- **Act II — The Lemonade Standard.** Establishes that mana lemonade is a *serious
  academic requirement*.
- **Act III — Glitter Everywhere.** The party finds sparkles in their boots for weeks.
  The Mage apologizes for nothing.
- **Act IV — The Star's Accent.** Starts understanding what the buried starlight is
  humming. It's… a lullaby?
- **Act V — Plucky's Answer.** Hums it back. The meadow's fizz softens for a whole day.

### 2.3 The Hunter — *the Keen-Eyed* (DEX)

Grew up in the berry brambles playing hide-and-seek with fireflies. Never misses
snack time. Never misses, generally.

- **Act I — Acorn Economics.** Arrows tipped with acorns: renewable, biodegradable,
  extremely bonky.
- **Act II — The Patient Game.** Wins a staring contest with a Puffling. It took a nap
  mid-contest. Still counts.
- **Act III — The Far Larder.** Maps every snack bush from the camp to Mushroom Hollow.
  The map is classified.
- **Act IV — One Perfect Shot.** Splits a falling stardrop so both halves land in the
  Wishing Well. Two wishes came true that day.
- **Act V — Eyes on the Star.** First to see the buried starlight. Says only: "It's
  berry-colored." Refuses to elaborate.

### 2.4 The Rogue — *the Sneaky* (LCK · DEX)

Tiptoes everywhere, even at breakfast. Luck is a cookie jar with a loose lid.

- **Act I — Finders Keepers.** Locked doors mysteriously wander open. The Rogue was
  "nowhere near them."
- **Act II — The Giggling Heist.** Steals the Mushroom King's second-favorite cap.
  Returns it with a bow on it. Gets adopted as "honorary mushroom."
- **Act III — Loaded Dice, Warm Heart.** Caught stacking the party's snack raffle —
  in everyone else's favor.
- **Act IV — The Unpickable Pocket.** Meets a lock luck can't open: a promise. Keeps it.
- **Act V — The Last Trick.** At the star, wishes for nothing. "Already got the good
  loot," they say, glancing at the party. Then steals the Warrior's sandwich.

---

## 3. Factions (the Meadow Clubs)

Mid-game allegiance, one per account per season (design intent §3.5). Stat effects are
StatBlock-parsable strings in `GameContent.FACTIONS`; specials name the system they hook.

### 3.1 The Marshmallow Watch — "Keep the hearth toasty. The hearth keeps you." (tag EMB)

The camp's blanket-wearing guardians: they tend the Snug Hearth, stack the pillow-forts,
and believe every adventure should end where it started — warm.
- **Pros:** +15% Maximum Life · +12% Armour
- **Cons:** -8% Attack Speed · -10% Coin Find
- **Special:** +2h offline snooze cap (the hearth keeps your spot warm).
- **Fits:** Warrior. **Rival:** The Sneaky Snackers.

### 3.2 The Waffle Squad — "Breakfast is a battle plan." (tag ASH)

Sparkle-chefs and dawn-raiders who believe firepower begins with syrup. Loud, warm,
slightly singed.
- **Pros:** +14% Toasty Damage · +8% All Damage · +6% Crit Chance
- **Cons:** -12% Armour
- **Special:** Tinker Shop crafts cost +25% Tin Bits (they keep borrowing the pans).
- **Fits:** Mage. **Rival:** The Marshmallow Watch.

### 3.3 The Sneaky Snackers — "Finders keepers, sharers weepers." (tag HLW)

The meadow's tiptoe society: scouts, snoops, and connoisseurs of unattended picnics.
They share eventually. Usually.
- **Pros:** +18% Coin Find · +12% Item Rarity
- **Cons:** -10% Maximum Life
- **Special:** Battle Caches roll one rarity band higher — but the baddies guard them
  a little harder (+6% enemy HP).
- **Fits:** Rogue. **Rival:** The Firefly Troop.

### 3.4 The Firefly Troop — "Forward is the comfiest direction." (tag LNT)

Lantern-carrying trailblazers who mark every safe path with glow-dust and leave
encouraging notes in the dark bits.
- **Pros:** +12% Movement Speed · +10% XP Gain
- **Cons:** -8% Maximum Mana
- **Special:** +2% party All Damage per online partymate; -10 daily Battle Cache cap
  (always skipping ahead of the loot).
- **Fits:** Hunter. **Rival:** The Sneaky Snackers.

### 3.5 Choosing (design intent)

One club per account, chosen in camp around level 25, switchable once per season (the
star's sneeze shakes all allegiances loose). Clubs are *flavors of comfort*, not moral
sides — every pro has a con so no club is strictly best, and each club's special hooks a
different system (offline, crafting, chests, party) so the choice reads in play, not just
on a character sheet.

---

## 4. How the threads braid (season arc sketch)

Season I, "**Starfall**": the star sneezes early, the paths reshuffle, and the Mushroom
King's cap goes missing (again). The Rogue knows something. The Warrior carries the
snacks. The Mage learns the lullaby's second verse. The Hunter has already seen how it
ends and is saying nothing. Divisions climb from Sleepy Snail to Star Sovereign; whoever
tops the Stampede board gets their name doodled on the Bulletin Board in glitter.

Season finale hook: the buried starlight isn't a treasure. It's an **egg**.
