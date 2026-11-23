# UI 风格落地

色板来自 `/cursor/stores/self/docs/ui-style.md`。页面结构以已定稿的 `/cursor/stores/self/docs/design-system.md` 为准。这两份原文都没有改。

默认 `data-theme=light`（平涂羊皮纸 `#D9CBAF`，卡片 `#E1D7C4`，阅读面 `#F4EFE4`）。可选 `data-theme=dark`（`#1E3D4A` 收到 `#13273C`，卡片 `#15283A`）。同一屏只用一套 token。世界圆点在浅色是 `#376AC9`、深色是 `#50D4ED`；荒野圆点在浅色是 `#991E45`、深色是 `#F1D95C`。不靠换主题区分作品。

窄屏小于 720px，黑底栏四项：首页、百科、配装、我的。宽屏用 64px 顶栏，当前项 2px 下划线。地图窄屏隐藏底栏。

正文 15px，字体是随包的 Noto Sans SC / TC / JP / Noto Sans（SIL OFL 1.1）。界面线标是 Lucide（`lucide_icons_flutter` 4.0.3）。组件结构用 `material_ui`，不用默认紫色。

示意对照：`home-phone`、`wiki-index-phone`、`wiki-article-phone`、`wiki-desktop`、`map-phone`、`map-desktop`、`account-phone`、`wiki-article-dark-phone`。

## 设计规范第 11 节待复核

1. 浅色底栏选中色先用 `#C4C4DC`。
2. 深色二级页签未选中字色，以及活动页三个页签的字色。
3. 深色大图卡圆角用 10px。
4. 浅色分区条圆角用 2px。
5. 浅色配装搜索浮动按钮圆角 12px，是否更圆待复核。
6. 星标在 Web 上是收藏当前条目。
7. `MR` 圆标 36px、`#244D9C`。活动详情这一版还没画这个圆。
8. `New` 缎带 45 度，只在深色推荐卡。这一版推荐卡还没有实拍大图。
9. 深色技能表间隔色 `#0E3148` / `#07496B`。
10. 浅色技能分组按类别涂粉和薄荷。
11. 属性负数、会心、防御先用正文色。
12. 浅色新闻双列间距 12px。资讯列表这一版还是活动列表，不是双列新闻。
13. 深色主按钮填充 `#0277A3`，停止搜索 `#C62828`。不用取样的 `#0397CE` / `#F54336` 直接做白字底。
