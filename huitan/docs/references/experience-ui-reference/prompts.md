# imagegen 参考图提示词

2026-10-13。以下为内置 imagegen 实际输入；不涉及 Meowa 调用记录。输出为参考图，非已接入游戏的组件。

## 最终统一修正

战斗图以 `gameplay-v1.png` 为目标、`transparent_background=false`：

```text
Edit Image 1 with a single correction: the XP display says "6 / 15", so shorten only the jade-cyan XP fill to exactly 40% of its track, moving the small endpoint glint accordingly. Preserve the "Lv. 2" badge on the LEFT, all XP frame dimensions, the XP number text, health/mana bars, all world pixels/composition, small crystals, trail, level-up notification, existing bottom HUD and overall 16:10 canvas. Change nothing else.
```

升级图以 `level-choice-v1.png` 为目标、`gameplay-v1.png` 为 HUD 参考、`transparent_background=false`：

```text
Edit Image 1, correcting ONLY its compact XP HUD under the blue mana bar. Image 2 shows the authoritative desired XP HUD arrangement: a small "Lv. 2" badge on the LEFT, then the thin aged-gold framed jade-cyan XP track, then the small pale fraction "6 / 15" on the RIGHT. Copy that complete arrangement and its size, margin and style from Image 2 into the same top-left position in Image 1. Set the XP fill to exactly 40% of its track to match 6/15, and use a subdued endpoint glint. Remove Image 1's old right-hand level badge so there is only one level badge. Preserve EVERYTHING ELSE from Image 1 exactly: health and mana bars, terrain, hero, warm lighting, depth of field, both empty growth cards and their selected/normal outlines, Chinese header, grade 2 subtitle, two small queue dots, compact confirm button, keyboard hint, bottom HUD, 16:10 canvas. Do not add crystals or the "等级提升" notification from Image 2 to Image 1; use Image 2 ONLY for the XP HUD.
```

## 战斗 HUD

参考图顺序：`docs/media/pixel-color-preview/battle-after.png`、`docs/references/upgrade-ui-reference/reference-v3.png`。`transparent_background=false`。

```text
Create a polished in-game UI visual reference for our existing Godot HD-2D game. This is a reference mockup, not an asset sheet. Image 1 is the actual current battle map screenshot and is the edit target: preserve its 16:10 composition, camera, terrain, flowers, yellow-jacket pixel hero, warm golden-hour lighting, depth of field, existing top-left red health and blue mana bars, bottom-left skill slots, and bottom-center inventory bar. Keep the actual game world recognizably unchanged. Image 2 is the existing approved growth-choice visual language, used for the fine warm brass edges only.

Add a compact experience HUD immediately BELOW the two existing top-left bars, with comfortable spacing. The XP track is distinctly thinner than the health and mana bars, around 260px wide and 10px high at a 1280px window, with a restrained aged warm-gold rim and translucent charcoal-olive empty well; a jade-to-cyan fill at about 60%, one tiny glint at its endpoint. Attach a small simple chamfered level badge at its left, text exactly "Lv. 2". Keep "6 / 15" as a small pale readable value beside or underneath the XP bar, separate from the art. Avoid extra panel backgrounds or thick framing. It should harmonize with existing HUD without overpowering it.

Place a handful of tiny clearly faceted PIXEL crystal pickups on the nearby grass: small cyan-blue single shard, medium amethyst pointed shard, and slightly larger amber twin shard. They must appear small relative to the hero, with crisp chunky pixel clusters, limited colors and a restrained halo. Show one crystal approaching the hero with just two tiny cyan trail dots. No beams, orbit rings, oversized particle clouds, pickup popups, or large floating numbers. A separate very small ephemeral top-center notification says only "等级提升" with a fine short brass divider and lots of transparent space, no rectangle behind it. This notification is shown here as a design state demonstration.

Deliver a visually beautiful, practical game screenshot mockup, retain plenty of visible world. Do not add cards, abilities, equipment details, wave counters, result screens, invented gameplay features, logos, explanatory labels or an opaque full-screen UI background.
```

## 升级选择

参考图顺序：`docs/media/pixel-color-preview/battle-after.png`、`docs/references/upgrade-ui-reference/reference-v3.png`、`docs/media/run-growth-preview/level-up.png`。`transparent_background=false`。

```text
Create the upgrade-selection screen reference for our actual HD-2D Godot game, in the same 16:10 aspect ratio as the real game. Image 1 is the actual current gameplay screenshot to use as the background; preserve its camera, landscape, hero, golden-hour lighting and depth of field. Image 2 is our already approved finished growth-choice design and is the visual reference to preserve closely. Image 3 is its current actual in-game assembly for placement and component scale.

The composition has two elegant empty tall growth cards, centered with ample world visible at the sides and between them, about 220px wide by 375px tall per card at a 1280px window, positioned around the center. Preserve the approved clean chamfered brass corners, restrained botanical engravings at corners, muted sage-green translucent interiors, separate circular empty icon socket near the top. Left card selected with a thin warm-gold luminous outline, right card normal with a quieter bronze outline; no ragged borders, no oversized bloom. Keep both cards completely blank: no skill icons, names, descriptions, stats, tags or upgrade benefits, since those are not designed.

Above them, clear softly lit warm-cream Chinese header exactly "选择成长方向", with the short symmetrical brass diamond ornaments from the approved design. A small unobtrusive line under the header reads exactly "等级 2", and a tiny separate step indicator with two dots (first bright, second dim) hints at queued level choices, without any explanatory paragraph. Below the cards use the approved compact plain chamfered bronze confirm button, text exactly "确认", with no elaborate flourishes. A subtle short keyboard hint below says "← → 选择   Enter 确认".

Keep the real red health and blue mana bars top-left and bottom HUD from Image 1. Add the same compact jade-cyan XP strip immediately below the mana bar, thinner than the existing two bars, tiny attached badge "Lv. 2". It should be quiet during selection. The actual game world remains clearly visible through card interiors and outside the cards, with no black screen-sized veil and no opaque modal slab. A calm, finished, tactile fantasy game interface that fits the beautiful existing artwork. No skill details, no new world composition, no wave UI, no result UI.
```

## 组件与状态表

参考图顺序：`docs/media/pixel-color-preview/battle-after.png`、`docs/references/upgrade-ui-reference/reference-v3.png`。`transparent_background=false`。

```text
Design one comprehensive high-quality UI reference board for the EXPERIENCE AND LEVEL-UP subsystem of an existing HD-2D game. Image 1 is the actual game screenshot: use it to judge scale, warm golden-hour landscape palette, pixel sprite readability and existing red/blue/gold HUD. Image 2 is the approved growth-card artwork: faithfully match its clean chamfered aged brass, botanical corner engravings and translucent sage-green body. This board supports subsequent Meowa extraction into separate assets, so arrange each asset clearly with generous gaps on a quiet warm-neutral gray backdrop, not on the game landscape. Do NOT invent abilities, skill details, item properties, buff categories or finalized game rules.

Use a refined professional landscape art board with four well-spaced sections, labeled only with these small Chinese headings: "经验宝石", "等级与经验", "升级反馈", "成长选择". Every asset must be visually complete with unclipped corners and halo, no overlap. Assets are art references, no dimension lines or decorative diagrams.

Section 1: three distinctly readable small PIXEL crystal candidates shown enlarged at an integer pixel scale: cyan-blue single shard, amethyst pointed shard, warm amber twin shard. Crisp square pixel clusters, limited 5-to-7 color ramps, dark cool facet shadows, tiny highlights, not smooth 3D renders. Include separate small soft ground shadow, two small cyan trail motes, and one understated cyan absorption sparkle as isolated pieces. Label the three candidates only with tiny "01", "02", "03", no XP values.

Section 2: a thin horizontal aged-brass XP frame with translucent charcoal-olive empty well, a separate jade-cyan fill strip, and a separate plain chamfered small level badge with no baked-in number. Below show assembled state samples: about 20% fill, 65% fill with subtle endpoint glint, 100% fill with a very short soft gleam, and capped state marked only "MAX". The XP frames remain much slimmer and calmer than red/blue health bars, never huge thick metal slabs. Dynamic level numbers and XP fractions are NOT baked into production asset previews. State samples may show small pale text "Lv. 2" or "6 / 15" nearby for typography.

Section 3: a compact floating warm-cream text notification exactly "等级提升" with tiny separate brass divider accents, a small quiet two-dot pending-choice indicator, and one narrow flash strip for an XP bar. No large panel, no ornamental medallion, no banners filling the screen.

Section 4: faithful blank growth card normal and selected versions from Image 2, clean corners, sage translucent interiors; separate round empty icon socket; separate short header-left and header-right diamond ornament and divider; compact plain brass confirm button in normal, hover and pressed appearances, all without baked-in text. No abilities, skill names or descriptions anywhere, no painted sample icons in sockets. Keep the card style cohesive with the approved reference, not a redesign. Show physical metal and restrained glow, clean anti-aliased UI art with clear edges; pixel gems alone use their crisp pixel art style. Make it attractive enough to serve as the complete visual vocabulary for this subsystem.
```
