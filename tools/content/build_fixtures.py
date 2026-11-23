#!/usr/bin/env python3
"""Write deterministic fixture catalogs. Numbers are synthetic."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "content" / "fixtures"


def texts(zh, zht, en, ja, summary_zh="合成夹具，不是游戏实数。"):
    return {
        "zh-Hans": {"name": zh, "aliases": [], "summary": summary_zh},
        "zh-Hant": {"name": zht, "aliases": [], "summary": "合成夾具，不是遊戲實數。"},
        "en": {"name": en, "aliases": [], "summary": "Synthetic fixture. Not live game data."},
        "ja": {"name": ja, "aliases": [], "summary": "合成フィクスチャ。ゲームの実数ではない。"},
    }


def entry(kind, entry_id, zh, zht, en, ja, **extra):
    item = {
        "kind": kind,
        "entryId": entry_id,
        "rarity": extra.pop("rarity", 1),
        "profiles": extra.pop("profiles", ["base"]),
        "platforms": ["pc", "ps", "xbox"],
        "texts": texts(zh, zht, en, ja, extra.pop("summary", "合成夹具，不是游戏实数。")),
        "fields": extra.pop("fields", {}),
        "fixture": True,
    }
    aliases = extra.pop("aliases", None)
    if aliases:
        for loc, names in aliases.items():
            item["texts"][loc]["aliases"] = names
    item.update(extra)
    return item


def world():
    entries = [
        entry(
            "monster",
            "fixture-jagras",
            "夹具大凶豺龙",
            "夾具大凶豺龍",
            "Fixture Jagras",
            "フィクスチャジャグラス",
            aliases={"zh-Hans": ["豺龙"], "zh-Hant": ["豺龍"], "en": ["jagras"], "ja": ["ジャグラス"]},
            fields={
                "weaknesses": [
                    {"part": "头", "element": "火", "stars": 2, "evidence": "fixture"}
                ],
                "note": "应用宝简介把弱点列为资料类别。这里的星级是夹具。",
            },
        ),
        entry(
            "monster",
            "fixture-ice-elder",
            "夹具冰原古龙",
            "夾具冰原古龍",
            "Fixture Ice Elder",
            "フィクスチャ氷原古龍",
            profiles=["iceborne"],
            summary="仅冰原内容档。本体筛选应隐藏。",
        ),
        entry(
            "material",
            "fixture-iron-ore",
            "夹具铁矿",
            "夾具鐵礦",
            "Fixture Iron Ore",
            "フィクスチャ鉄鉱",
            aliases={"zh-Hans": ["铁矿"], "en": ["iron"]},
        ),
        entry(
            "material",
            "fixture-rare-ore",
            "夹具稀有矿",
            "夾具稀有礦",
            "Fixture Rare Ore",
            "フィクスチャ稀少鉱石",
            rarity=6,
            fields={"gather": "rare"},
        ),
        entry(
            "material",
            "fixture-ice-ore",
            "夹具冰原矿",
            "夾具冰原礦",
            "Fixture Ice Ore",
            "フィクスチャ氷原鉱石",
            profiles=["iceborne"],
        ),
        entry(
            "weapon",
            "fixture-iron-sword",
            "夹具铁刀",
            "夾具鐵刀",
            "Fixture Iron Sword",
            "フィクスチャ鉄刀",
            part="weapon",
            slots=[],
            skills=[],
            fields={"attack": 100, "evidence": "fixture"},
        ),
        entry(
            "weapon",
            "fixture-plain-weapon",
            "夹具素刀",
            "夾具素刀",
            "Fixture Plain Blade",
            "フィクスチャ無装飾刀",
            part="weapon",
            slots=[],
            skills=[],
        ),
        entry(
            "armor",
            "fixture-fixed-mail",
            "夹具固定胸甲",
            "夾具固定胸甲",
            "Fixture Fixed Mail",
            "フィクスチャ固定メイル",
            part="chest",
            slots=[],
            skills=[{"skillId": "fixture-skill-s", "level": 1}],
        ),
        entry(
            "armor",
            "fixture-arms-slot",
            "夹具开孔腕甲",
            "夾具開孔腕甲",
            "Fixture Slotted Vambrace",
            "フィクスチャスロット腕",
            part="arms",
            slots=[{"index": 0, "accept": "lv1"}],
            skills=[],
        ),
        entry(
            "armor",
            "fixture-waist-slot",
            "夹具开孔腰甲",
            "夾具開孔腰甲",
            "Fixture Slotted Coil",
            "フィクスチャスロット腰",
            part="waist",
            slots=[{"index": 0, "accept": "lv1"}],
            skills=[],
        ),
        entry(
            "armor",
            "fixture-plain-head",
            "夹具素头",
            "夾具素頭",
            "Fixture Plain Helm",
            "フィクスチャ無装飾頭",
            part="head",
            slots=[],
            skills=[],
        ),
        entry(
            "armor",
            "fixture-plain-legs",
            "夹具素腿",
            "夾具素脚",
            "Fixture Plain Greaves",
            "フィクスチャ無装飾脚",
            part="legs",
            slots=[],
            skills=[],
        ),
        entry(
            "skill",
            "fixture-skill-s",
            "夹具攻击",
            "夾具攻擊",
            "Fixture Attack",
            "フィクスチャ攻撃",
            aliases={"zh-Hans": ["攻击"], "en": ["attack"]},
        ),
        entry(
            "decoration",
            "fixture-attack-jewel",
            "夹具攻击珠",
            "夾具攻擊珠",
            "Fixture Attack Jewel",
            "フィクスチャ攻撃珠",
            slotType="lv1",
            skills=[{"skillId": "fixture-skill-s", "level": 1}],
        ),
        entry(
            "charm",
            "fixture-charm",
            "夹具护石",
            "夾具護石",
            "Fixture Charm",
            "フィクスチャ護石",
            part="charm",
            slots=[],
            skills=[],
        ),
        entry(
            "item",
            "fixture-potion",
            "夹具回复药",
            "夾具回復藥",
            "Fixture Potion",
            "フィクスチャ回復薬",
        ),
        entry(
            "quest",
            "fixture-quest",
            "夹具调查任务",
            "夾具調查任務",
            "Fixture Quest",
            "フィクスチャ調査",
        ),
    ]
    relations = [
        {"type": "drops", "fromKind": "monster", "fromId": "fixture-jagras", "toKind": "material", "toId": "fixture-iron-ore"},
        {"type": "craftedFrom", "fromKind": "weapon", "fromId": "fixture-iron-sword", "toKind": "material", "toId": "fixture-iron-ore"},
        {"type": "grantsSkill", "fromKind": "decoration", "fromId": "fixture-attack-jewel", "toKind": "skill", "toId": "fixture-skill-s"},
        {"type": "grantsSkill", "fromKind": "armor", "fromId": "fixture-fixed-mail", "toKind": "skill", "toId": "fixture-skill-s"},
    ]
    maps = [
        {
            "mapId": "fixture-ancient-forest",
            "profiles": ["base"],
            "texts": texts("夹具古代树", "夾具古代樹", "Fixture Ancient Forest", "フィクスチャ古代樹"),
            "layers": [
                {"layerId": "floor-1", "texts": texts("一层", "一層", "Floor 1", "1層")},
                {"layerId": "floor-2", "texts": texts("二层", "二層", "Floor 2", "2層")},
            ],
            "pois": [
                {
                    "poiId": "poi-common",
                    "layerId": "floor-1",
                    "xNorm": 0.32,
                    "yNorm": 0.48,
                    "area": "区域1",
                    "kind": "gather",
                    "resourceRef": {"kind": "material", "entryId": "fixture-iron-ore"},
                    "conditions": "夹具：常见采集",
                    "sourceRef": "fixture",
                },
                {
                    "poiId": "poi-rare",
                    "layerId": "floor-2",
                    "xNorm": 0.32,
                    "yNorm": 0.48,
                    "area": "区域1",
                    "kind": "rare-gather",
                    "resourceRef": {"kind": "material", "entryId": "fixture-rare-ore"},
                    "conditions": "夹具：可能出现",
                    "sourceRef": "fixture",
                },
            ],
        }
    ]
    return {
        "fixture": True,
        "schemaVersion": 1,
        "gameId": "world",
        "contentProfiles": ["base", "iceborne"],
        "platformId": "pc",
        "patchId": "fixture-p1",
        "dataRevision": "fixture-1",
        "revisionNumber": 1,
        "rulesetVersion": "fixture-r1",
        "defaultLocale": "zh-Hans",
        "entries": entries,
        "relations": relations,
        "maps": maps,
    }


def wilds():
    entries = [
        entry("weapon", "fixture-weapon-w", "夹具试作武器W", "夾具試作武器W", "Fixture Weapon W", "フィクスチャ武器W", part="weapon", slots=[{"index": 0, "accept": "type-j"}], skills=[]),
        entry("weapon", "fixture-weapon-child", "夹具派生武器", "夾具派生武器", "Fixture Derived Weapon", "フィクスチャ派生武器", part="weapon", slots=[], skills=[], fields={"attack": 80, "evidence": "fixture"}),
        entry("armor", "fixture-head-h", "夹具头部H", "夾具頭部H", "Fixture Helm H", "フィクスチャ頭H", part="head", slots=[{"index": 0, "accept": "type-k"}], skills=[]),
        entry("armor", "fixture-plain-chest", "夹具素胸", "夾具素胸", "Fixture Plain Chest", "フィクスチャ無装飾胴", part="chest", slots=[], skills=[]),
        entry("armor", "fixture-plain-arms", "夹具素腕", "夾具素腕", "Fixture Plain Arms", "フィクスチャ無装飾腕", part="arms", slots=[], skills=[]),
        entry("armor", "fixture-plain-waist", "夹具素腰", "夾具素腰", "Fixture Plain Waist", "フィクスチャ無装飾腰", part="waist", slots=[], skills=[]),
        entry("armor", "fixture-plain-legs", "夹具素腿", "夾具素脚", "Fixture Plain Legs", "フィクスチャ無装飾脚", part="legs", slots=[], skills=[]),
        entry("skill", "fixture-skill-x", "夹具技能X", "夾具技能X", "Fixture Skill X", "フィクスチャスキルX"),
        entry("skill", "fixture-skill-y", "夹具技能Y", "夾具技能Y", "Fixture Skill Y", "フィクスチャスキルY"),
        entry("decoration", "fixture-jewel-j", "夹具珠J", "夾具珠J", "Fixture Jewel J", "フィクスチャ珠J", slotType="type-j", skills=[{"skillId": "fixture-skill-x", "level": 1}]),
        entry("decoration", "fixture-jewel-k", "夹具珠K", "夾具珠K", "Fixture Jewel K", "フィクスチャ珠K", slotType="type-k", skills=[{"skillId": "fixture-skill-y", "level": 1}]),
        entry("material", "fixture-wilds-ore", "夹具铁矿", "夾具鐵礦", "Fixture Iron Ore", "フィクスチャ鉄鉱", aliases={"zh-Hans": ["铁矿"], "en": ["iron"]}),
        entry(
            "monster",
            "fixture-wilds-beast",
            "夹具荒野兽",
            "夾具荒野獸",
            "Fixture Wilds Beast",
            "フィクスチャ荒野獣",
            fields={
                "parts": [
                    {
                        "name": "夹具头部",
                        "wound": "夹具伤口",
                        "weakness": "火",
                        "evidence": "fixture",
                        "publicNote": "荒野 1.7.0 更新说明提到怪物部位、伤口与弱点。本条数值是夹具。",
                    }
                ]
            },
        ),
        entry("item", "fixture-wilds-potion", "夹具回复药", "夾具回復藥", "Fixture Potion", "フィクスチャ回復薬"),
    ]
    relations = [
        {"type": "derives", "fromKind": "weapon", "fromId": "fixture-weapon-w", "toKind": "weapon", "toId": "fixture-weapon-child"},
        {"type": "craftedFrom", "fromKind": "weapon", "fromId": "fixture-weapon-child", "toKind": "material", "toId": "fixture-wilds-ore"},
        {"type": "grantsSkill", "fromKind": "decoration", "fromId": "fixture-jewel-j", "toKind": "skill", "toId": "fixture-skill-x"},
        {"type": "grantsSkill", "fromKind": "decoration", "fromId": "fixture-jewel-k", "toKind": "skill", "toId": "fixture-skill-y"},
    ]
    return {
        "fixture": True,
        "schemaVersion": 1,
        "gameId": "wilds",
        "contentProfiles": ["base"],
        "platformId": "pc",
        "patchId": "fixture-p1",
        "dataRevision": "fixture-1",
        "revisionNumber": 1,
        "rulesetVersion": "fixture-r1",
        "defaultLocale": "zh-Hans",
        "entries": entries,
        "relations": relations,
        "maps": [],
    }


def events():
    return [
        {
            "id": "fixture-event-ancient",
            "gameId": "world",
            "platformId": "pc",
            "region": "cn",
            "titles": {
                "zh-Hans": "夹具赏金：古代树调查",
                "zh-Hant": "夾具賞金：古代樹調查",
                "en": "Fixture bounty: Ancient Forest",
                "ja": "フィクスチャ報奨：古代樹",
            },
            "rewards": [
                {"itemId": "fixture-fruit", "names": {"zh-Hans": "夹具古代树果实", "zh-Hant": "夾具古代樹果實", "en": "Fixture forest fruit", "ja": "フィクスチャ古代樹の実"}}
            ],
            "startsAt": "2026-11-23T00:00:00Z",
            "endsAt": "2026-11-30T16:00:00Z",
            "timezone": "Asia/Shanghai",
            "status": "active",
            "verifiedAt": "2026-11-23T00:00:00Z",
            "sourceUrl": "",
            "conditions": "夹具日程，不是卡普空官方时间。",
            "sequence": 1,
            "fixture": True,
        },
        {
            "id": "fixture-event-wilds",
            "gameId": "wilds",
            "platformId": "pc",
            "region": "cn",
            "titles": {
                "zh-Hans": "夹具活动：荒野试炼",
                "zh-Hant": "夾具活動：荒野試煉",
                "en": "Fixture event: Wilds trial",
                "ja": "フィクスチャ：荒野の試練",
            },
            "rewards": [
                {"itemId": "fixture-ticket", "names": {"zh-Hans": "夹具票券", "zh-Hant": "夾具票券", "en": "Fixture ticket", "ja": "フィクスチャチケット"}}
            ],
            "startsAt": "2026-11-23T02:00:00Z",
            "endsAt": "2026-12-01T02:00:00Z",
            "timezone": "Asia/Shanghai",
            "status": "active",
            "verifiedAt": "2026-11-23T00:00:00Z",
            "sourceUrl": "",
            "conditions": "荒野 1.7.0 更新说明写了活动任务。此条时间是夹具。",
            "sequence": 1,
            "fixture": True,
        },
    ]


def articles():
    return [
        {
            "id": "fixture-article-about",
            "gameId": "world",
            "locale": "zh-Hans",
            "title": "本站资料是夹具",
            "body": "MH伙伴助手的百科数字是合成夹具，用来验收搜索、地图和配装。公开产品页的功能差异见开发文档，不在这里复述商店全文。",
            "sourceUrl": "https://apps.apple.com/cn/app/id1365915425",
            "originalLanguage": "zh-Hans",
            "reviewStatus": "fixture",
            "verifiedAt": "2026-11-23T00:00:00Z",
        }
    ]


def public_builds():
    equipped = {
        "format": "mhbuddy.build",
        "schemaVersion": 1,
        "gameId": "wilds",
        "contentProfile": "base",
        "platformId": "pc",
        "patchId": "fixture-p1",
        "dataRevision": "fixture-1",
        "rulesetVersion": "fixture-r1",
        "title": "夹具公开配装",
        "weapon": {"entryId": "fixture-weapon-w", "instanceId": "w1", "customizations": []},
        "armor": [
            {"slot": "head", "entryId": "fixture-head-h", "instanceId": "h1"},
            {"slot": "chest", "entryId": "fixture-plain-chest", "instanceId": "c1"},
            {"slot": "arms", "entryId": "fixture-plain-arms", "instanceId": "a1"},
            {"slot": "waist", "entryId": "fixture-plain-waist", "instanceId": "wst1"},
            {"slot": "legs", "entryId": "fixture-plain-legs", "instanceId": "l1"},
        ],
        "decorations": [
            {"entryId": "fixture-jewel-j", "equipInstanceId": "w1", "slotIndex": 0},
            {"entryId": "fixture-jewel-k", "equipInstanceId": "h1", "slotIndex": 0},
        ],
        "tags": ["夹具", "公开"],
        "weaponType": "fixture",
        "rarity": 1,
    }
    return [
        {
            "id": "pub-fixture-wilds-1",
            "ownerId": "seed",
            "gameId": "wilds",
            "title": "夹具公开配装",
            "weaponType": "fixture",
            "rarity": 1,
            "snapshot": equipped,
        }
    ]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "catalog-world.json").write_text(json.dumps(world(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "catalog-wilds.json").write_text(json.dumps(wilds(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "events.json").write_text(json.dumps(events(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "articles.json").write_text(json.dumps(articles(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "public-builds.json").write_text(json.dumps(public_builds(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("fixtures ok")


if __name__ == "__main__":
    main()
