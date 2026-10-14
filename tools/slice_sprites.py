"""Cuts walk cycles out of Spriters Resource sheets into the game's sheet format.

Each output sheet has 3 rows (down, right, up) of equal-size cells, feet at the
bottom-centre of each cell. Left is drawn by mirroring the right row.
Put the printed frame count in the CHARACTERS table in game/scripts/game.gd.

Usage: python3 tools/slice_sprites.py "<path to Mario&LuigiMMO folder>"
Add a character by adding an entry to CHARACTERS with the pixel box of each
row on its source sheet (left, top, right, bottom).
"""
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "characters")

# rows: boxes for the down / side / up walk rows (a box may repeat when a sheet
# only has one direction). side_faces_left: the side row looks left on the
# source sheet and gets mirrored. Optional: "bg" overrides the background colour,
# "strip" lists extra colours to clear (drawn-on shadows), "flood" clears only
# background that touches the frame edge (for white sheets with white sprites),
# "recolor" writes extra palette-swapped copies ({new id: {old rgb: new rgb}}).
CHARACTERS = {
    "mario": {"sheet": "Playable Characters GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Playable Characters - Mario (Overworld).png",
              "rows": [(0, 8, 176, 48), (0, 86, 176, 126), (0, 169, 176, 209)], "side_faces_left": False},
    "luigi": {"sheet": "Playable Characters GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Playable Characters - Luigi (Overworld).png",
              "rows": None, "side_faces_left": False},  # rows found automatically (same layout as Mario)
    "peach": {"sheet": "Playable Characters GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Princess Peach.png",
              "rows": [(0, 2, 215, 43), (0, 46, 215, 88), (0, 90, 215, 131)], "order": [0, 2, 1], "side_faces_left": False},
    "bowser": {"sheet": "Playable Characters EVIL/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Bowser (USA).png",
               "rows": [(0, 28, 260, 76), (0, 86, 260, 132), (0, 142, 260, 190)], "side_faces_left": True},
    "goomba": {"sheet": "Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Enemies - Goomba.png",
               "rows": [(0, 202, 185, 232), (0, 232, 185, 260), (0, 260, 185, 290)], "side_faces_left": False},
    "toad": {"sheet": "Partners GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Toad.png",
             "rows": None, "side_faces_left": False},
    "beanie": {"sheet": "Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Enemies - Beanie & Gold Beanie.png",
               "rows": [(0, 188, 172, 216), (0, 222, 172, 250), (0, 255, 172, 284)], "side_faces_left": False},
    "waluigi": {"sheet": "Playable Characters GOOD/Custom _ Edited - Mario Customs - Waluigi - Waluigi (Overworld, Mario & Luigi_ Superstar Saga-Style).png",
                "rows": [(0, 10, 126, 56), (0, 61, 126, 107), (126, 10, 248, 56)], "side_faces_left": True},
    "rosalina": {"sheet": "Playable Characters GOOD/Custom _ Edited - Mario Customs - Rosalina & Luma - Rosalina (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(28, 19, 232, 61), (32, 105, 232, 149), (34, 149, 232, 192)], "side_faces_left": True,
                 "bg": (255, 255, 255), "flood": True},
    "toadette": {"sheet": "Playable Characters GOOD/Custom _ Edited - Mario Customs - Toadette & Peachette - Toadette (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(0, 0, 104, 27), (0, 76, 150, 101), (0, 52, 183, 76)], "side_faces_left": True, "flood": True},
    "bowser_jr": {"sheet": "Playable Characters EVIL/Custom _ Edited - Mario Customs - Bowser Jr. - Bowser Jr. (Mario & Luigi_ Superstar Saga-Style).png",
                  "rows": [(278, 112, 313, 155), (372, 112, 405, 155), (313, 112, 343, 155)], "side_faces_left": True},
    "shadow_mario": {"sheet": "Playable Characters EVIL/Custom _ Edited - Mario Customs - Other Bosses - Shadow Mario (Mario & Luigi_ Superstar Saga-Style).png",
                     "rows": [(88, 240, 116, 281), (63, 240, 86, 281), (36, 240, 62, 281)], "side_faces_left": False},
    "pianta": {"sheet": "NPCs/Custom _ Edited - Mario Customs - Piantas - Piantas (Superstar Saga-Style).png",
               "rows": [(0, 196, 128, 240), (128, 196, 232, 240), (0, 196, 128, 240)], "side_faces_left": False},
    "galoomba": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Goomba & Related Enemies - Galoomba (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(0, 150, 200, 172), (0, 235, 200, 257), (0, 176, 200, 198)], "side_faces_left": False},
    "koopa": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Koopa Troopa & Related Enemies - Koopa Troopa (Mario & Luigi_ Superstar Saga-Style).png",
              "rows": [(0, 585, 140, 616), (0, 651, 140, 682), (0, 618, 140, 649)], "side_faces_left": False},
    "dry_bones": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Dry Bones & Related Enemies - Dry Bones (Mario & Luigi_ Superstar Saga-Style).png",
                  "rows": [(0, 481, 130, 512), (0, 547, 130, 581), (0, 515, 130, 546)], "side_faces_left": False},
    "shy_guy": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Shy Guy, Snifit & Related Enemies - Shy Guy (Mario & Luigi_ Superstar Saga-Style).png",
                "rows": [(0, 30, 175, 75)] * 3, "side_faces_left": True, "strip": [(84, 109, 142)]},
    "buzzy_beetle": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Buzzy Beetle, Spiny & Related Enemies - Buzzy Beetle (Mario & Luigi_ Superstar Saga-Style).png",
                     "rows": [(0, 27, 220, 55)] * 3, "side_faces_left": True},
    # Phase 6 roster. Battle-style sheets with one pose (Vivian,
    # Bombette) repeat the same box for all three rows.
    "egadd": {"sheet": "Playable Characters GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Professor E. Gadd.png",
              "rows": [(0, 4, 230, 48), (0, 100, 230, 146), (0, 52, 230, 97)], "side_faces_left": False},
    "vivian": {"sheet": "Playable Characters GOOD/Custom _ Edited - Paper Mario Customs - Thousand-Year Door Partners - Vivian (Mario & Luigi_ Superstar Saga-Style).png",
               "rows": [(0, 0, 58, 42)] * 3, "side_faces_left": False, "flood": True},
    "rookie_bowser": {"sheet": "Playable Characters EVIL/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Rookie Bowser (USA).png",
                      "rows": [(0, 20, 300, 70), (0, 138, 365, 186), (0, 82, 300, 132)], "side_faces_left": False},
    "grodus": {"sheet": "Playable Characters EVIL/Custom _ Edited - Paper Mario Customs - Grodus & the X-Nauts - Grodus (Mario & Luigi_ Superstar Saga-Style).png",
               "rows": [(300, 160, 620, 216), (300, 284, 620, 340), (300, 220, 606, 276)], "side_faces_left": False,
               "bg": (255, 255, 255), "flood": True},
    # recolor: extra sheets with the red shell/mask swapped for the other three
    # brothers' colours (swatches from the sheet's "Pallets" box).
    "koopa_bros": {"sheet": "Playable Characters EVIL/Custom _ Edited - Paper Mario Customs - Paper Mario 64 Bosses - Koopa Bros (Mario & Luigi_ Superstar Saga-Style).png",
                   "rows": [(374, 256, 492, 296), (374, 332, 492, 368), (374, 296, 492, 331)], "side_faces_left": False,
                   "flood": True, "recolor": {
                       "koopa_bros_green": {(255, 8, 8): (128, 216, 48), (200, 0, 0): (0, 176, 0), (160, 0, 0): (0, 120, 32)},
                       "koopa_bros_yellow": {(255, 8, 8): (247, 195, 0), (200, 0, 0): (224, 152, 0), (160, 0, 0): (173, 115, 0)},
                       "koopa_bros_black": {(255, 8, 8): (132, 132, 132), (200, 0, 0): (98, 98, 98), (160, 0, 0): (69, 69, 69)},
                   }},
    "bombette": {"sheet": "Partners GOOD/Custom _ Edited - Paper Mario Customs - Paper Mario 64 Partners - Bombette (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(0, 0, 136, 35)] * 3, "side_faces_left": False, "flood": True, "strip": [(41, 48, 66)]},
    "bow": {"sheet": "Partners GOOD/Custom _ Edited - Paper Mario Customs - Paper Mario 64 Partners - Bow (Mario & Luigi_ Superstar Saga-Style).png",
            "rows": [(68, 383, 198, 412), (208, 383, 328, 412), (338, 383, 468, 412)], "side_faces_left": False},
    "bobbery": {"sheet": "Partners GOOD/Custom _ Edited - Paper Mario Customs - Thousand-Year Door Partners - Bobbery (Mario & Luigi_ Superstar Saga-Style).png",
                "rows": [(223, 88, 298, 122), (28, 88, 123, 122), (298, 88, 363, 122)], "side_faces_left": False, "flood": True},
    "goombella": {"sheet": "Partners GOOD/Custom _ Edited - Paper Mario Customs - Thousand-Year Door Partners - Goombella (Mario & Luigi_ Superstar Saga-Style).png",
                  "rows": [(0, 2, 75, 32), (8, 32, 132, 62), (75, 2, 148, 32)], "side_faces_left": False, "flood": True},
    "koops": {"sheet": "Partners GOOD/Custom _ Edited - Paper Mario Customs - Thousand-Year Door Partners - Koops (Mario & Luigi_ Superstar Saga-Style).png",
              "rows": [(25, 85, 180, 121), (20, 47, 240, 84), (25, 120, 180, 155)], "side_faces_left": True, "flood": True},
    "yoshi_kid": {"sheet": "Partners GOOD/Custom _ Edited - Paper Mario Customs - Thousand-Year Door Partners - Yoshi Kid (Mario & Luigi_ Superstar Saga-Style).png",
                  "rows": [(462, 2, 508, 32), (0, 2, 160, 32), (509, 2, 555, 32)], "side_faces_left": True, "flood": True},
    "peasley": {"sheet": "Partners GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Prince Peasley.png",
                "rows": [(0, 3, 220, 44), (0, 141, 210, 182), (0, 46, 220, 88)], "side_faces_left": False},
    "yoshi": {"sheet": "Partners GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Yoshi.png",
              "rows": [(0, 3, 170, 42), (0, 83, 232, 121), (0, 43, 170, 82)], "side_faces_left": True, "flood": True},
}

# Townsfolk you can talk to (the NPCS table in game.gd). They stand still, so a
# row may be a box around a single pose. The Beanbean Kingdom Residents sheet
# has one column per direction (left, front, back, right), so its boxes pick
# one pose each.
_NPC = "NPCs/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - "
_RESIDENTS = _NPC + "Beanbean Kingdom Residents.png"
NPCS = {
    "bean_elder": {"sheet": _RESIDENTS, "rows": [(23, 2, 40, 28), (60, 2, 77, 28), (41, 2, 58, 28)], "side_faces_left": False},
    "bean_villager": {"sheet": _RESIDENTS, "rows": [(101, 2, 119, 36), (141, 2, 159, 36), (121, 2, 139, 36)], "side_faces_left": False},
    "bean_kid": {"sheet": _RESIDENTS, "rows": [(264, 2, 281, 36), (302, 2, 319, 36), (283, 2, 300, 36)], "side_faces_left": False},
    "bean_girl": {"sheet": _RESIDENTS, "rows": [(21, 180, 38, 212), (60, 180, 77, 212), (40, 180, 57, 212)], "side_faces_left": False},
    "bean_guard": {"sheet": _NPC + "Beanbean Guards.png",
                   "rows": [(0, 3, 226, 39), (0, 42, 180, 78), (0, 79, 226, 115)], "side_faces_left": True},
    "shopkeeper": {"sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Castle Town Shop (Interior).png",
                   "rows": [(188, 116, 295, 153), (188, 44, 295, 82), (188, 153, 295, 190)], "side_faces_left": False, "flood": True},
    "toad_blue": {"sheet": _NPC + "Toads.png", "rows": [(0, 2, 176, 35), (0, 35, 176, 67), (0, 69, 176, 101)], "side_faces_left": True},
    "toadsworth": {"sheet": _NPC + "Toadsworth.png", "rows": [(0, 60, 145, 89), (0, 29, 145, 58), (0, 91, 145, 120)], "side_faces_left": True},
    "dr_toad": {"sheet": _NPC + "Dr. Toad.png", "rows": [(0, 4, 176, 35), (0, 75, 176, 106), (0, 40, 176, 71)],
                "side_faces_left": True, "flood": True},
    "lady_lima": {"sheet": _NPC + "Lady Lima.png", "rows": [(225, 48, 350, 85), (225, 86, 360, 123), (225, 12, 350, 49)],
                  "side_faces_left": False, "flood": True},
    "queen_bean": {"sheet": _NPC + "Queen Bean.png", "rows": [(3, 670, 54, 715), (423, 670, 464, 715), (213, 670, 264, 715)],
                   "side_faces_left": True},
    "koopa_troop": {"sheet": _NPC + "Koopa Troopas.png", "rows": [(0, 5, 212, 40), (0, 40, 212, 75), (0, 76, 212, 111)], "side_faces_left": False},
    "koopa_troop_red": {"sheet": _NPC + "Koopa Troopas.png", "rows": [(0, 117, 212, 152), (0, 152, 212, 187), (0, 188, 212, 223)],
                        "side_faces_left": False},
    "border_bro": {"sheet": _NPC + "Border Bros.png", "rows": [(12, 32, 128, 74), (12, 82, 146, 122), (130, 32, 250, 74)],
                   "side_faces_left": False, "flood": True},
    "hoohoo_villager": {"sheet": _NPC + "Hoohooligans.png", "rows": [(0, 104, 150, 142), (0, 141, 150, 179), (0, 29, 150, 67)],
                        "side_faces_left": False, "strip": [(80, 80, 80)]},
    "hoohoo_villager_b": {"sheet": _NPC + "Hoohooligans.png", "rows": [(150, 104, 295, 142), (150, 141, 295, 179), (150, 29, 295, 67)],
                          "side_faces_left": False, "strip": [(80, 80, 80)]},
}


# Bosses (the BOSSES table in game.gd). Battle-style sheets: the idle row is
# used for all three rows, like Vivian. They face left on the sheets (towards
# the heroes in battle). Dimentio stays out of the game on purpose.
_BOSS = "Boss Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Bosses - "
_MC = "Boss Enemies/Custom _ Edited - Mario Customs - "
_PM = "Boss Enemies/Custom _ Edited - Paper Mario Customs - "
_GOOMBOSS = _PM + "Paper Mario 64 Bosses - King Goomba _ Goomboss (Mario & Luigi_ Superstar Saga-Style).png"


def _virus(y):
    """One colour of the Viruses sheet: down, side, back rows, and the big face to attack with."""
    return {"sheet": _MC + "Other Enemies - Viruses (Superstar Saga-Style).png",
            "rows": [(3, y, 66, y + 21), (3, y + 46, 101, y + 68), (3, y + 23, 66, y + 44)],
            "side_faces_left": True, "attack": (70, y, 103, y + 44), "attack_faces_left": False, "flood": True}


BOSSES = {
    "popple": {"sheet": _BOSS + "Popple.png", "rows": [(0, 35, 145, 72)] * 3, "side_faces_left": True},
    "tolstar": {"sheet": _BOSS + "Tolstar.png", "rows": [(0, 33, 545, 88)] * 3, "side_faces_left": True,
                "bg": (255, 255, 255), "flood": True},
    "dragohoho": {"sheet": _BOSS + "Dragohoho.png", "rows": [(0, 41, 530, 105)] * 3, "side_faces_left": True},
    "wart": {"sheet": "Boss Enemies/Custom _ Edited - Mario Customs - Wart - Wart (Mario & Luigi_ Superstar Saga-Style).png",
             "rows": [(205, 91, 715, 159)] * 3, "side_faces_left": True, "bg": (255, 255, 255), "flood": True},
    # Phase 8: every other Superstar Saga boss sheet. "attack" is the box of
    # the attack animation (the 4th row, see build); "skip" drops frames.
    "piranha_bean": {"sheet": _BOSS + "Piranha Bean.png", "rows": [(0, 41, 336, 88)] * 3, "side_faces_left": True,
                     "attack": (0, 162, 520, 211)},
    "hermie": {"sheet": _BOSS + "Hermie III.png", "rows": [(0, 22, 730, 118)] * 3, "side_faces_left": True,
               "attack": (0, 520, 830, 615)},
    "mom_piranha": {"sheet": _BOSS + "Mom Piranha.png", "rows": [(0, 38, 807, 118)] * 3, "side_faces_left": True,
                    "attack": (0, 144, 750, 223)},
    "chuckolator": {"sheet": _BOSS + "Chuckolator.png", "rows": [(0, 38, 592, 122)] * 3, "side_faces_left": True,
                    "attack": (0, 348, 615, 433)},
    "hoohooros": {"sheet": _BOSS + "Hoohooros.png", "rows": [(0, 35, 455, 75)] * 3, "side_faces_left": True,
                  "attack": (0, 93, 590, 133)},
    "trunkle": {"sheet": _BOSS + "Trunkle.png", "rows": [(0, 35, 565, 110)] * 3, "side_faces_left": True,
                "attack": (0, 250, 512, 328)},
    "birdo": {"sheet": _BOSS + "Birdo.png", "rows": [(0, 34, 285, 73)] * 3, "side_faces_left": True,
              "attack": (0, 199, 282, 238)},
    "jojora": {"sheet": _BOSS + "Jojora.png", "rows": [(0, 36, 190, 77)] * 3, "side_faces_left": True,
               "attack": (0, 92, 406, 137)},
    "jojora_friend": {"sheet": _BOSS + "Jojora's Friend.png", "rows": [(0, 23, 595, 90)] * 3, "side_faces_left": True,
                      "attack": (0, 536, 882, 595)},
    "queen_bean_boss": {"sheet": _BOSS + "Queen Bean.png", "rows": [(0, 10, 1150, 91)] * 3, "side_faces_left": True,
                        "attack": (0, 482, 1226, 586)},
    "larry": {"sheet": _BOSS + "Larry.png", "rows": [(0, 38, 228, 87)] * 3, "side_faces_left": True,
              "attack": (0, 159, 372, 209)},
    "lemmy": {"sheet": _BOSS + "Lemmy.png", "rows": [(0, 36, 235, 79)] * 3, "side_faces_left": True,
              "attack": (0, 141, 240, 184)},
    "ludwig": {"sheet": _BOSS + "Ludwig.png", "rows": [(0, 40, 362, 88)] * 3, "side_faces_left": True,
               "attack": (0, 259, 365, 307)},
    "morton": {"sheet": _BOSS + "Morton.png", "rows": [(0, 36, 366, 82)] * 3, "side_faces_left": True,
               "attack": (0, 142, 370, 188)},
    "roy": {"sheet": _BOSS + "Roy.png", "rows": [(0, 35, 340, 72)] * 3, "side_faces_left": True,
            "attack": (0, 135, 374, 170)},
    "wendy": {"sheet": _BOSS + "Wendy.png", "rows": [(0, 41, 324, 89)] * 3, "side_faces_left": True,
              "attack": (0, 160, 406, 208)},
    "iggy": {"sheet": _BOSS + "Iggy.png", "rows": [(0, 34, 325, 89)] * 3, "side_faces_left": True,
             "attack": (0, 321, 262, 377)},
    "cackletta": {"sheet": _BOSS + "Cackletta.png", "rows": [(0, 26, 603, 94)] * 3, "side_faces_left": True,
                  "attack": (0, 322, 702, 391)},
    "fawful": {"sheet": _BOSS + "Fawful.png", "rows": [(0, 38, 300, 115)] * 3, "side_faces_left": True,
               "attack": (0, 146, 345, 224)},
    "fawful_2": {"sheet": _BOSS + "Fawful (2nd Form).png", "rows": [(0, 344, 268, 391)] * 3, "side_faces_left": True,
                 "attack": (0, 403, 374, 453)},
    "bowletta": {"sheet": _BOSS + "Bowletta.png", "rows": [(0, 34, 490, 113)] * 3, "side_faces_left": True,
                 "attack": (0, 798, 703, 874)},
    "cackletta_soul": {"sheet": _BOSS + "Cackletta's Soul.png", "rows": [(0, 33, 758, 109)] * 3, "side_faces_left": True,
                       "attack": (0, 122, 758, 209)},
    "magikoopa": {"sheet": "Boss Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Enemies - Magikoopa.png",
                  "rows": [(0, 50, 258, 93)] * 3, "side_faces_left": True, "attack": (0, 112, 618, 158)},
    "yo_bro": {"sheet": "Boss Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Enemies - Yo Bro.png",
               "rows": [(0, 32, 740, 80)] * 3, "side_faces_left": True, "attack": (0, 412, 762, 452),
               "attack_skip": [8, 9, 10, 11]},
    "psycho_kamek": {"sheet": "Boss Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Psycho Kamek.png",
                     "rows": [(0, 15, 146, 47)] * 3, "side_faces_left": True, "attack": (165, 63, 325, 97)},
    # Custom Superstar Saga-style bosses (Mario, Paper Mario and TTYD customs).
    "jr_troopa": {"sheet": _PM + "Paper Mario 64 Bosses - Jr. Troopa (Mario & Luigi_ Superstar Saga-Style).png",
                  "rows": [(1, 25, 199, 57)] * 3, "side_faces_left": True, "strip": [(76, 108, 117), (40, 48, 64)]},
    "goomboss": {"sheet": _GOOMBOSS, "rows": [(5, 264, 352, 346)] * 3, "side_faces_left": True,
                 "attack": (358, 264, 570, 346), "flood": True},
    "goomboss_2": {"sheet": _GOOMBOSS, "rows": [(5, 1151, 352, 1232)] * 3, "side_faces_left": True,
                   "attack": (380, 1151, 595, 1232), "flood": True},  # red with rage (phase 2)
    "red_goomba": {"sheet": _GOOMBOSS, "rows": [(712, 106, 832, 131), (712, 181, 832, 205), (712, 132, 832, 156)],
                   "side_faces_left": False, "flood": True},
    "blue_goomba": {"sheet": _GOOMBOSS, "rows": [(712, 205, 832, 229), (712, 279, 832, 303), (712, 230, 832, 254)],
                    "side_faces_left": False, "flood": True},
    "gooper_blooper": {"sheet": _MC + "Blooper & Related Enemies - Gooper Blooper (Mario & Luigi_ Superstar Saga-Style).png",
                       "rows": [(0, 28, 156, 112)] * 3, "side_faces_left": True, "attack": (0, 28, 465, 112), "scale": 0.7},
    "big_bobomb": {"sheet": _MC + "Bob-omb & Related Enemies - Big Bob-omb (Mario & Luigi_ Superstar Saga-Style).png",
                   "rows": [(0, 4, 482, 111)] * 3, "side_faces_left": True, "attack": (0, 234, 575, 340), "flood": True,
                   "scale": 0.6},
    "swiggler": {"sheet": "Boss Enemies/Custom _ Edited - Mario & Luigi Customs - Bosses - Swiggler (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(0, 32, 935, 93)] * 3, "side_faces_left": True, "attack": (0, 369, 590, 448), "flood": True},
    "lakithunder": {"sheet": _MC + "Lakitu & Related Enemies - Lakithunder (Mario & Luigi_ Superstar Saga-Style).png",
                    "rows": [(0, 33, 180, 111)] * 3, "side_faces_left": True, "attack": (0, 235, 320, 334), "flood": True},
    "petey": {"sheet": _MC + "Petey Piranha - Petey Piranha (M&L_ Superstar Saga-Style).png",
              "rows": [(0, 39, 600, 133)] * 3, "side_faces_left": True, "attack": (92, 272, 166, 370)},
    "tatanga": {"sheet": _MC + "Tatanga - Tatanga (Mario & Luigi_ Superstar Saga-Style).png",
                "rows": [(10, 56, 310, 122)] * 3, "side_faces_left": False, "attack": (80, 124, 200, 177)},
    "tutankoopa": {"sheet": _PM + "Paper Mario 64 Bosses - Tutankoopa (Mario & Luigi_ Superstar Saga-Style).png",
                   "rows": [(224, 140, 320, 180)] * 3, "side_faces_left": True, "attack": (224, 195, 382, 235),
                   "attack_skip": [2], "flood": True},
    "general_guy": {"sheet": _PM + "Paper Mario 64 Bosses - General Guy (Mario & Luigi_ Superstar Saga-Style).png",
                    "rows": [(55, 145, 262, 222)] * 3, "side_faces_left": False, "attack": (125, 72, 262, 142), "flood": True},
    "kammy": {"sheet": _PM + "Kammy Koopa - Kammy Koopa (Mario & Luigi_ Superstar Saga-Style).png",
              "rows": [(0, 540, 230, 589)] * 3, "side_faces_left": True, "attack": (0, 688, 470, 750)},
    "virus_fever": _virus(147),
    "virus_chill": _virus(3),
    "virus_weird": _virus(75),
    "lava_piranha": {"sheet": _PM + "Paper Mario 64 Bosses - Lava Piranha (Mario & Luigi_ Superstar Saga-Style).png",
                     "rows": [(440, 135, 785, 198)] * 3, "side_faces_left": True, "attack": (440, 410, 662, 488),
                     "attack_skip": [4], "flood": True},
    "beldam": {"sheet": _PM + "Thousand-Year Door Bosses - Beldam (Mario & Luigi_ Superstar Saga-Style).png",
               "rows": [(4, 84, 126, 116)] * 3, "side_faces_left": True, "attack": (4, 48, 64, 82), "flood": True},
    "marilyn": {"sheet": _PM + "Thousand-Year Door Bosses - Marilyn (Mario & Luigi_ Superstar Saga-Style).gif",
                "rows": [(4, 5, 85, 53)] * 3, "side_faces_left": True, "attack": (4, 100, 126, 173)},
    "cortez": {"sheet": _PM + "Thousand-Year Door Bosses - Cortez (Mario & Luigi_ Superstar Saga-Style).png",
               "rows": [(0, 538, 312, 613)] * 3, "side_faces_left": True, "attack": (0, 656, 880, 731), "flood": True},
    "macho_grubba": {"sheet": _PM + "Thousand-Year Door Bosses - Grubba _ Macho Grubba (Mario & Luigi_ Superstar Saga-Style).png",
                     "rows": [(0, 34, 410, 147)] * 3, "side_faces_left": True, "attack": (0, 407, 740, 518), "scale": 0.75},
    "smorg": {"sheet": _PM + "Thousand-Year Door Bosses - Smorg (Mario & Luigi_ Superstar Saga-Style).png",
              "rows": [(125, 8, 845, 198)] * 3, "side_faces_left": True, "attack": (15, 218, 745, 446), "scale": 0.3},
}


def bands(mask):
    out, start = [], None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(mask)))
    return out


def frames_in(im, bg, box, strip=(), flood=False):
    x0, y0, x1, y1 = box
    px = im.load()
    clear = {bg, *strip}
    fg = lambda x, y: px[x, y][3] > 0 and px[x, y][:3] not in clear
    rows = [b for b in bands([any(fg(x, y) for x in range(x0, x1)) for y in range(y0, y1)]) if b[1] - b[0] > 6]
    ya, yb = y0 + rows[0][0], y0 + rows[-1][1]
    cols = [c for c in bands([any(fg(x, y) for y in range(ya, yb)) for x in range(x0, x1)]) if c[1] - c[0] > 4]
    frames = []
    for a, b in cols:
        fr = im.crop((x0 + a, ya, x0 + b, yb))
        p = fr.load()
        if flood:  # only clear background touching the edges, keeps white caps/eyes
            w, h = fr.size
            todo = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
            while todo:
                x, y = todo.pop()
                if 0 <= x < w and 0 <= y < h and p[x, y][3] > 0 and p[x, y][:3] in clear:
                    p[x, y] = (0, 0, 0, 0)
                    todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        else:
            for y in range(fr.size[1]):
                for x in range(fr.size[0]):
                    if p[x, y][:3] in clear:
                        p[x, y] = (0, 0, 0, 0)
        frames.append(fr.crop(fr.getbbox()) if fr.getbbox() else fr)
    return frames


def auto_rows(im, bg, xmax=176):
    px = im.load()
    mask = [any(px[x, y][:3] != bg for x in range(xmax)) for y in range(min(im.size[1], 400))]
    rows = [b for b in bands(mask) if b[1] - b[0] > 10][:5]
    return [(0, rows[i][0], xmax, rows[i][1]) for i in (0, 2, 4)]


def build(name, cfg, root):
    im = Image.open(os.path.join(root, cfg["sheet"])).convert("RGBA")
    bg = tuple(cfg.get("bg") or max(im.getcolors(1 << 24))[1][:3])  # most common colour = background
    boxes = cfg["rows"] or auto_rows(im, bg)
    strip = [tuple(c) for c in cfg.get("strip", ())]
    rows = [frames_in(im, bg, b, strip, cfg.get("flood", False)) for b in boxes]
    if "order" in cfg:
        rows = [rows[i] for i in cfg["order"]]
    if "skip" in cfg:  # frames to leave out of the idle row (a blink, a hurt pose)
        rows = [[f for i, f in enumerate(r) if i not in cfg["skip"]] for r in rows]
    if cfg["side_faces_left"]:
        if len(set(boxes)) == 1:
            rows = [[f.transpose(Image.FLIP_LEFT_RIGHT) for f in r] for r in rows]
        else:
            rows[1] = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in rows[1]]
    if "attack" in cfg:
        # Bosses: a 4th row with the attack animation, drawn like the side row.
        attack = frames_in(im, bg, cfg["attack"], strip, cfg.get("flood", False))
        if "attack_skip" in cfg:
            attack = [f for i, f in enumerate(attack) if i not in cfg["attack_skip"]]
        if cfg.get("attack_faces_left", cfg["side_faces_left"]):
            attack = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in attack]
        rows.append(attack)
    if "scale" in cfg:  # oversized sheets: shrink every frame (nearest neighbour keeps the pixels crisp)
        k = cfg["scale"]
        rows = [[f.resize((max(1, round(f.size[0] * k)), max(1, round(f.size[1] * k))), Image.NEAREST) for f in r]
                for r in rows]
    n = max(len(r) for r in rows)
    cw = max(f.size[0] for r in rows for f in r) + 2
    ch = max(f.size[1] for r in rows for f in r) + 2
    # Even cells keep every cell edge on a whole pixel at the battle's 1.5x
    # scale, so the feet of the row above can't bleed into the top of a frame.
    cw += cw % 2
    ch += ch % 2
    sheet = Image.new("RGBA", (cw * n, ch * len(rows)), (0, 0, 0, 0))
    for ri, r in enumerate(rows):
        for ci in range(n):
            f = r[ci % len(r)]
            sheet.paste(f, (ci * cw + (cw - f.size[0]) // 2, ri * ch + ch - f.size[1]), f)
    os.makedirs(OUT, exist_ok=True)
    sheet.save(os.path.join(OUT, name + ".png"))
    print(name, [len(r) for r in rows], (cw, ch))
    for other, swap in cfg.get("recolor", {}).items():
        copy = sheet.copy()
        px = copy.load()
        for y in range(copy.size[1]):
            for x in range(copy.size[0]):
                c = px[x, y]
                if c[3] > 0 and c[:3] in swap:
                    px[x, y] = (*swap[c[:3]], c[3])
        copy.save(os.path.join(OUT, other + ".png"))
        print(other, "(recolour of %s)" % name)


if __name__ == "__main__":
    root = sys.argv[1]
    for name, cfg in {**CHARACTERS, **NPCS, **BOSSES}.items():
        if len(sys.argv) > 2 and name not in sys.argv[2:]:
            continue
        build(name, cfg, root)
