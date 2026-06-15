# Design reference library (seed)

Decompiled primitives for well-known product aesthetics. When a user gives a vibe/brand reference ("the feeling of Spotify", "make it like Linear"), look it up here FIRST for instant, deterministic primitives, then write them into the project's `design-system/MASTER.md`. See `.claude/rules/design-references.md` for the procedure.

> **These are seeds, not gospel.** Brands redesign. For a reference NOT in this list — or when you need current detail — follow the decompile procedure in the rule (WebFetch the live site / brand guidelines and extract the six primitive groups). Free font analogs are given because most brand faces are proprietary; swap if the project licenses the real one. Verify hex against the live product before locking.

Each entry decomposes into the six groups that fill `MASTER.md`: **mode · color · type · layout · motion · mood**, plus **anti-patterns** (what this vibe is NOT) and **best when**.

---

## Spotify — dark, immersive, content-first
- **Mode:** dark-first (non-negotiable)
- **Color:** bg `#121212`, surface `#181818`/`#282828`, accent `#1DB954` (green), text `#FFFFFF`, muted `#B3B3B3`
- **Type:** geometric sans, heavy title weights 700–900; Circular → free analog **Montserrat / Poppins**; tight tracking on big bold headings
- **Layout:** card grids, horizontal-scroll "shelves", persistent bottom player bar, hero album art, 4–8px card radius, circular avatars
- **Motion:** understated, smooth; subtle hover-lift on cards; soft page transitions
- **Mood:** immersive, energetic-but-focused, imagery does the talking
- **Anti-patterns:** NOT light-first, NOT corporate-blue, NOT flat-white-SaaS, no heavy borders
- **Best when:** media/streaming, dense browse, dark content-forward apps

## Linear — crisp, fast, dark-minimal
- **Mode:** dark-first
- **Color:** near-black bg `#08090A`/`#101113`, indigo accent `#5E6AD2`, subtle multi-stop gradients, low-chroma grays
- **Type:** Inter (custom) → **Inter**; tight, small, precise; restrained sizes
- **Layout:** dense, keyboard-first, thin 1px hairline borders, small radii (6–8px), high information density, command-palette ethos
- **Motion:** snappy, near-instant, micro-easing; nothing bouncy
- **Mood:** engineered, premium, quiet confidence, speed
- **Anti-patterns:** NOT playful, NO large radii, NO heavy illustration, NO slow animation
- **Best when:** dev tools, B2B SaaS, productivity, anything that should feel fast

## Stripe — polished, trustworthy, gradient-light
- **Mode:** light-first (dark optional)
- **Color:** white bg, indigo `#635BFF`, signature angled multi-color gradients, deep slate text `#0A2540`
- **Type:** Söhne/Camphor → **Inter / Söhne analog**; clean, confident, generous sizes
- **Layout:** generous whitespace, strong grid, code blocks as first-class, layered cards with soft shadows, medium radii (8–12px)
- **Motion:** refined, purposeful; subtle parallax/gradient shifts
- **Mood:** sophisticated, developer-trust, enterprise-grade calm
- **Anti-patterns:** NOT cluttered, NOT neon, NO harsh borders
- **Best when:** fintech, developer products, premium marketing sites

## Notion — calm, document-first, near-monochrome
- **Mode:** light-first (dark supported)
- **Color:** warm off-white `#F7F6F3`, near-black text `#37352F`, minimal accent, subtle grays
- **Type:** system sans for body + Lyon/serif for display → **system-ui + a serif display** (e.g. Lora)
- **Layout:** lots of whitespace, narrow content column, blocky, restrained, small radii, playful spot illustrations
- **Motion:** minimal, gentle
- **Mood:** calm, focused, friendly-neutral, content over chrome
- **Anti-patterns:** NOT loud, NO strong brand color flooding, NO dense dashboards
- **Best when:** docs, knowledge tools, editors, content apps

## Vercel — stark, high-contrast, geometric
- **Mode:** dark-native (light supported), pure black/white
- **Color:** `#000000` / `#FFFFFF`, grayscale ramp, accent used sparingly
- **Type:** **Geist** (Vercel's own, free) — geometric, sharp
- **Layout:** extreme contrast, sharp edges / small radii, geometric, generous negative space, monospace for code
- **Motion:** minimal, precise
- **Mood:** stark, modern, developer-minimal, confident
- **Anti-patterns:** NOT colorful, NOT soft, NO gradients-everywhere
- **Best when:** dev platforms, minimal portfolios, high-contrast brands

## Apple (HIG) — premium, spacious, restrained
- **Mode:** light or dark (both first-class)
- **Color:** restrained; lots of white/near-black, one accent, translucency/material blur
- **Type:** **SF Pro** (Apple platforms) → **Inter / system-ui** on web; large bold headlines, clear hierarchy
- **Layout:** very generous whitespace, large hero type + imagery, depth via subtle shadow/translucency, large radii on cards
- **Motion:** refined, physics-based, never gratuitous
- **Mood:** premium, clear, confident, product-as-hero
- **Anti-patterns:** NOT busy, NO clashing colors, NO heavy borders
- **Best when:** premium consumer products, hardware, polished marketing

## Discord — friendly, rounded, dark-social
- **Mode:** dark-first
- **Color:** surface `#313338`/`#2B2D31`, "blurple" `#5865F2`, text `#F2F3F5`, muted `#B5BAC1`
- **Type:** gg sans → **Inter**; rounded, approachable
- **Layout:** dense but friendly, rounded corners (8–16px), pill buttons, list-heavy, mascot/illustration accents
- **Motion:** bouncy-but-controlled, playful micro-interactions
- **Mood:** social, fun, community, casual-energetic
- **Anti-patterns:** NOT corporate, NOT stark, NO sharp edges
- **Best when:** community/social, chat, gaming-adjacent

## Airbnb — warm, photographic, friendly-premium
- **Mode:** light-first
- **Color:** white bg, "Rausch" coral `#FF385C`, warm neutrals, charcoal text
- **Type:** Cereal → **Montserrat**; friendly geometric
- **Layout:** photography-forward, big imagery, rounded cards (12px), airy grids, prominent search
- **Motion:** smooth, warm, gentle
- **Mood:** welcoming, trustworthy, aspirational, human
- **Anti-patterns:** NOT cold, NOT dense-corporate, NO tiny imagery
- **Best when:** marketplaces, travel/hospitality, listing-driven apps

## Netflix — cinematic, dark, imagery-driven
- **Mode:** dark-native
- **Color:** `#141414` bg, `#E50914` red, white text, deep blacks
- **Type:** Netflix Sans → **Montserrat**; bold display (Bebas Neue for posters)
- **Layout:** edge-to-edge hero, horizontal card rows, imagery-as-content, minimal chrome
- **Motion:** smooth hover-expand on cards, cinematic fades
- **Mood:** cinematic, immersive, premium entertainment
- **Anti-patterns:** NOT light, NOT text-heavy, NO visible grid lines
- **Best when:** video/media, catalog browsing, entertainment

## Material 3 (Google) — tonal, expressive, rounded
- **Mode:** light or dark with dynamic/tonal color
- **Color:** dynamic tonal palettes from a seed color; clear roles (primary/secondary/tertiary/surface)
- **Type:** Roboto / Google Sans → **Roboto / Inter**
- **Layout:** large radii (16–28px), elevation/tonal surfaces, FABs, clear component system
- **Motion:** expressive, spring-based, emphasized easing
- **Mood:** friendly, systematic, accessible, Android-native
- **Anti-patterns:** NOT sharp-edged, NOT monochrome-stark
- **Best when:** Android apps, Flutter, component-system-driven products

## Brutalist / editorial — raw, high-contrast, typographic
- **Mode:** usually light (stark)
- **Color:** black/white, one harsh accent, no soft grays
- **Type:** grotesk or monospace (Helvetica/Times/mono) → **Space Grotesk / IBM Plex Mono**; oversized type
- **Layout:** hard edges (NO radius), visible grids/borders, asymmetric, dense, raw HTML feel
- **Motion:** minimal or deliberately abrupt
- **Mood:** bold, anti-corporate, artistic, confrontational
- **Anti-patterns:** NO soft shadows, NO rounded corners, NO gradients, NO "friendly" polish
- **Best when:** portfolios, editorial, fashion, statement brands

## Duolingo — playful, chunky, gamified
- **Mode:** light-first, bright
- **Color:** white bg, "feather" green `#58CC02`, bold secondary brights, high saturation
- **Type:** din rounded / Feather → **Nunito** (rounded, friendly, heavy)
- **Layout:** big chunky rounded buttons (16px+), 3D-ish depth on CTAs, mascot everywhere, generous spacing
- **Motion:** bouncy, celebratory, juicy feedback
- **Mood:** playful, encouraging, gamified, joyful
- **Anti-patterns:** NOT serious-corporate, NO thin type, NO muted palette
- **Best when:** education, consumer apps, gamification, kids/family
