#!/usr/bin/env python3
"""Write the mobile and Gamersky parity notes from the verified baseline."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = json.loads((ROOT / "tools" / "research" / "baseline.json").read_text(encoding="utf-8"))
OUT = ROOT / "docs" / "execution"
OUT.mkdir(parents=True, exist_ok=True)


def mobile() -> str:
    w = BASE["world"]
    s = BASE["wilds"]
    lines = [
        "# MH伙伴移动端功能矩阵",
        "",
        f"采集日 {BASE['observedAt']}。事实来自已核实的公开页，不把待复核项写成确定功能。",
        "",
        "| 功能 | 来源和版本 | 用户操作 | iOS 证据 | Android 证据 | Web | 任务 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        f"| 世界百科搜索与收藏 | App Store {w['iosVersion']} 简介 | 搜索并收藏 | 有 | 应用宝简介写了武器防具技能怪物任务素材弱点 | `/g/world/entries` | A01 / T06 |",
        f"| 世界地图与稀有采集点 | App Store 简介 | 从素材打开采集点 | 有 | 应用宝简介没有写地图，以 App Store 和官网标题为准 | `/g/world/maps` | A02 / T06 |",
        f"| 世界配装条件 | 简介；2.16.2 提到自动配装与觉醒技能 | 固定装备、我的装饰品、再筛选 | 有 | 应用宝写了配装模拟 | `/g/world/builds` | A03 / T04 |",
        f"| 世界活动与赏金 | 简介 | 按任务名和报酬搜索 | 有 | 应用宝写了活动任务和赏金 | `/g/world/events` | A05 / T07 |",
        f"| 世界云存储 | 简介只写不同方案不同空间 | 登录后同步 | 有 | 应用宝简介没有写会员 | `/me` | A07 / T05 |",
        f"| 荒野百科 | 简介 | 搜索收藏 | 有，当前 {s['iosVersion']} | 应用宝 {s['androidVersion']}，简介一致 | `/g/wilds/entries` | A01 / T06 |",
        "| 荒野地图 | 简介没有写地图 | 不作为已确认功能 | 未见 | 未见 | 不提供荒野地图验收 | 待复核 |",
        "| 荒野自动配装与预留孔 | 1.4.0、1.5.0 更新说明 | 预留武器孔后求解，分列空孔 | 有 | 应用宝停在 1.13.0，没有这段 changelog | `/g/wilds/builds` | A04 / T04 |",
        "| 荒野导入 | 简介 | 导入 mhbuddy.build | 有 | 简介一致 | 配装页导入 | A04 / T04 |",
        "| 荒野活动 | 1.7.0 更新说明 | 查看活动 | 有 | 页上没有 1.13.0 之后的说明 | `/g/wilds/events` | A05 / T07 |",
        "",
        "## 待复核",
        "",
    ]
    for item in BASE["pending"]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append("Google Play 三个包名在 2026-11-23 的 zh_CN 直链为 404，本表的安卓证据来自应用宝，不是 Google Play。")
    lines.append("")
    return "\n".join(lines)


def gamersky() -> str:
    return "\n".join([
        "# 游民星空工具对照",
        "",
        f"对照日 {BASE['observedAt']}。世界／冰原没有检到游民自有图鉴或配装器。",
        "",
        "| 作品 / 入口 | 归属 | 用户操作 | 可见结果 | 本项目页面 | 验收 | 证据 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        "| 荒野图鉴 https://www.gamersky.com/tools/mhwiki/ | 游民 | 查武器、防具、技能、怪物、任务 | 页面 200，分类来自首页脚本 | `/g/wilds/entries` | A01 | 网页已观察（资料线程，2026-11-23） |",
        "| 荒野配装器 https://www.gamersky.com/tools/mhbd/ | 游民 | 按武器和稀有度看大厅，自动配装 | 说明页写了大厅和自动配装 | `/g/wilds/builds` 与 `/builds/:id` | A04 | 编辑说明已确认。大厅「300 多种」是 2025-03-11 文章数字，待复核 |",
        "| 招式动作值 | 游民图鉴入口 | 查动作值 | MH伙伴公开记录未见同名入口 | 不做成已确认功能 | — | 待复核 |",
        "| 世界工具路径 /tools/mhw /mhwi /mhwbd | 游民 | 打开世界配装器 | 2026-11-23 返回 404 | 无对应页 | — | 网页已观察为 404 |",
        "| 2019 攻略推荐的 Armor Set Search | 站外第三方 | 目标技能、指定或排除装备 | 不是游民托管工具 | 世界配装夹具走 A03 | A03 | 编辑说明已确认，工具本身待核验 |",
        "",
        "村任务／集会所进度不采用。海龙版本不能写成 2026-11-23 的最新资料。",
        "",
    ])


def main() -> None:
    (OUT / "mh-mobile-parity.md").write_text(mobile(), encoding="utf-8")
    (OUT / "gamersky-parity.md").write_text(gamersky(), encoding="utf-8")
    report = {"observedAt": BASE["observedAt"], "pending": len(BASE["pending"]), "mode": "offline-baseline"}
    (OUT / "research-run.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("research-mh wrote parity notes")


if __name__ == "__main__":
    main()
