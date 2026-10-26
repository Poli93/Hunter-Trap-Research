### Hunter Traps activation range research and its inconsistency on creatures with large combat reach
https://discord.gg/fZEEfHqUHn

**Introduction**

While researching Explosive Trap activation ranges for [my backport](https://poli93.github.io/wotlk/) of wowsims I encountered a few discrepancies that I'd like to share with the community, as I believe other private server players will find this interesting.

Based on game data, I expect both Lord Marrowgar and Sindragosa to have the biggest ranges for traps amongst the bosses in ICC. After presenting this data to players, we discovered there is also something else going on that **sometimes** prevents this behaviour. 

```
    unit 36612 Lord Marrowgar                    combat reach 20.2500  bounding radius 4.5000  scale 1.000
    unit 36855 Lady Deathwhisper                 combat reach  6.0000  bounding radius 3.0000  scale 1.000
    unit 37813 Deathbringer Saurfang             combat reach  1.7250  bounding radius 0.4278  scale 1.000
    unit 36626 Festergut                         combat reach  8.0000  bounding radius 0.3100  scale 1.000
    unit 36627 Rotface                           combat reach  8.0000  bounding radius 0.3100  scale 1.000
    unit 36678 Professor Putricide               combat reach  7.8000  bounding radius 1.2090  scale 1.000
    unit 37970 Prince Valanar                    combat reach  1.7500  bounding radius 0.5425  scale 1.000
    unit 37972 Prince Keleseth                   combat reach  1.7500  bounding radius 0.5425  scale 1.000
    unit 37973 Prince Taldaram                   combat reach  1.7500  bounding radius 0.5425  scale 1.000
    unit 37955 Blood-Queen Lana'thel             combat reach  7.2000  bounding radius 1.2400  scale 1.000
    unit 36789 Valithria Dreamwalker             combat reach 20.0000  bounding radius 2.0000  scale 1.000
    unit 36853 Sindragosa                        combat reach 18.7500  bounding radius 0.7750  scale 1.000
    unit 36597 The Lich King                     combat reach  5.5000  bounding radius 2.7500  scale 1.000
```

After further research, it appears units are filed into squared map grids. Objects (trap in this case) only check units whose centre is in a grid square near the trap, only then does it run a second check. The AoE range check: `TargetCombatReach + AttackRadius + IfSourceIsRunning`, per [Blizzard's formula](https://www.bluetracker.gg/wow/topic/us-en/13087818929-warlords-of-draenor-theorycraft-discussion/#503)
The IfSourceIsRunning check can never return true for hunter traps, as the check is done by the trap object itself. When the trap fires, a dummy NPC ([World Invisible Trigger](https://www.wowhead.com/wotlk/npc=12999/world-invisible-trigger)) is spawned on it to cast the effect.

```
DB 59 01 C7 32 30 F1 ×2      caster: World Invisible Trigger (entry 12999),
A9 BF 00 00                  spell 49065, Explosive Trap Effect
01 3D 00 00 04 8F 00 30 F1   target hit: 0xF130008F0400003D, Lord Marrowgar
BC A2 B5 C3 EB 02 09 45 …    source:      (−363.27, 2192.18, 41.76)
86 D5 C2 C3 C1 CE 09 45 …    destination: (−389.67, 2204.92, 41.99)
```

**Why this only happens with traps?**

Other AoE spells, cones, auras and totems [were patched](https://github.com/TrinityCore/TrinityCore/pull/27827) to search 40 extra yards past the grid squares, to solve exactly this problem with big CombatReach creatures.

**Why Marrowgar?**

Marrowgar has big CombatReach, but the trap has to find him, because a trap has no target. 
To solve this, the server files every unit under a map square, and only opens the squares near the trap. The activation check around the circle (_For traps this turned out to be a square, see part 2_) runs after that, and only on the units in those squares. 

The [example code below](https://github.com/TrinityCore/TrinityCore/blob/3.3.5/src/server/game/Grids/Cells/CellImpl.h) is of TrinityCore, the open-source base Warmane is derived from.
Marrowgar's spawn point is 1.37 yards from the x = −400.00 border.
Grid Borders fall on multiples of 66.67: …, −466.67, −400.00, −333.33, … and …, 2133.33, 2200.00, 2266.67, … 
```cpp
// Grids/GridDefines.h
#define MAX_NUMBER_OF_CELLS     8
#define SIZE_OF_GRIDS            533.3333f
#define SIZE_OF_GRID_CELL       (SIZE_OF_GRIDS/MAX_NUMBER_OF_CELLS)   // 66.6667 yd

// square number of a position
double x_offset = (double(x) - center_offset)/size;
int x_val = int(x_offset + CENTER_VAL + 0.5);
```

**How to work around this behaviour?**

In the process of testing this behaviour, I’ve made an addon to make the grids visible.
It adds a radar window that shows the map around you. 
The grid square borders are drawn as orange lines, with each square’s number and your distance to the nearest border.

<img width="167" height="221" alt="image" src="https://github.com/user-attachments/assets/eaeefb32-72cd-4f1c-8928-00da9f42bc4f" />


### Hunter Traps activation range research, part 2: traps are squares, and they rotate with your compass facing

**Introduction**

Following up on [the map grid research](https://github.com/Poli93/MapGrid) and discussions with hunters on the wowsims backport discord, I ran into trap ranges that no circle could explain. Sometimes a trap would reach much further than it should, and sometimes much shorter.

After packet sniffing 92 traps against training dummies and against players in duels, and going through the code of most major private server cores, the answer turned out to be: **hunter traps trigger in a square, not a circle, and the square rotates depending on the compass direction you face.** 

**Why a square?**

Traps don't use a normal distance check. A trap is a game object, and private server cores make every distance check from a game object use the object's model box, `GameObject::IsInRange`. That makes sense for doors and towers, and traps inherited it.

<img width="928" height="134" alt="image" src="https://github.com/user-attachments/assets/2e24635d-b990-497b-9236-53f95519d880" />

The trap model is 1 yard long (0.5 front + 0.5 back) and 0.9 yards wide (0.48420584202 one side + 0.42008346319 other side), and the check grows it by a radius on every side. Each axis is checked separately, so the result is a box with sharp corners. Its corners reach about 41% further than its flat sides.


```cpp
// GameObject.cpp, GameObject::IsInRange
return dx < info->GeoBoxMax.X + radius && dx > info->GeoBoxMin.X - radius
    && dy < info->GeoBoxMax.Y + radius && dy > info->GeoBoxMin.Y - radius
    && dz < info->GeoBoxMax.Z + radius && dz > info->GeoBoxMin.Z - radius;
```

(per GameObjectCache.wdb and slot names from [GameObjectData.h](https://github.com/TrinityCore/TrinityCore/blob/07a435ee9785b454e4286a59b4eba5997bb12691/src/server/game/Entities/GameObject/GameObjectData.h#L125))
```
Entry 189322: 'Explosive Trap VI'  type=6  displayId=3072  size=1.0
  Data0  lockId         = 12
  Data1  level          = 0
  Data2  diameter       = 5
  Data3  spellId        = 49065
  Data4  type           = 1
  Data5  cooldown       = 0
  Data6  autoCloseTime  = 0
  Data7  startDelay     = 1
  Data8  serverOnly     = 0
  Data9  stealthed      = 1
  Data10 large          = 0
  Data11 invisible      = 0
  Data12 openTextID     = 0
  Data13 closeTextID    = 0
  Data14 ignoreTotems   = 1
```
The radius is half the trap's 5 yard diameter, plus sizes:
```
    creatures:  (5/2) + 0.389 + TargetCombatReach
    players:    (5/2)     (no CombatReach added)
```
0.389 is the default size of a player's body, reused for every object that isn't a unit, traps included ([ObjectDefines.h](https://github.com/TrinityCore/TrinityCore/blob/07a435ee9785b454e4286a59b4eba5997bb12691/src/server/game/Entities/Object/ObjectDefines.h#L39)).

**Why does it spin?**

Before checking the box, the code turns the target's position into the trap's own frame. Two lines in that turn are **[possibly](https://github.com/azerothcore/azerothcore-wotlk/pull/27441#issuecomment-5517556964)** swapped:
```cpp
float sinB = dx / dist; 
float cosB = dy / dist;  
```
So instead of turning with you, the square turns the opposite way, twice as fast compared with where you look. Every 22.5° of turning, a flat side and a corner swap places in front of you.

**Why only traps?**

Only checks made *from* a game object use the box. 


**How to work around this behaviour?**

One example is when your target is in front of you, face one of the in-between directions (NNE, ENE, ESE…, in radians 0.393, 1.178, 1.963, 2.749, 3.534, 4.320, 5.105, 5.890) to put the long corner of the square in front of you.
To investigate this behaviour and to measure it ingame I'm including [TrapAngle](https://github.com/Poli93/Hunter-Trap-Research/tree/main/TrapAngle) and [TrapSim](https://poli93.github.io/Hunter-Trap-Research/TrapSim/)
