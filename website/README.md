# Deck Hand website

The marketing site for Deck Hand. Plain static files with no build step:
`index.html`, `styles.css`, `site.js`, and `assets/`.

## Preview locally

```bash
cd website
python3 -m http.server 8000
# open http://localhost:8000
```

## Deploy to Cloudflare Pages

1. In the Cloudflare dashboard, go to **Workers & Pages → Create → Pages →
   Connect to Git** and pick this repository.
2. Build settings:
   - **Framework preset:** None
   - **Build command:** leave empty
   - **Build output directory:** `website`
   - **Production branch:** `main`
3. Deploy. The site is live at `<project>.pages.dev`.
4. Once you have a domain, open the project's **Custom domains** tab and add
   it. If the domain's DNS is already on Cloudflare, the records are created
   for you.

`_headers` sets security headers and long-lived caching for `assets/`.
`404.html` is served automatically for unknown paths.

### After you pick a domain

Social previews need an absolute image URL. Replace `/assets/og.png` in the
`og:image` meta tag in `index.html` with `https://<your-domain>/assets/og.png`,
and add `<link rel="canonical" href="https://<your-domain>/">`.

## Logo

`brand/` holds three icon concepts as SVG and PNG. Each has a squircle
version for the web and a square `-master.png` for the app icon script:

| File | Concept |
| --- | --- |
| `concept-a-sticker` | **Tap** (site default). A coral pointing hand with a sticker outline, tapping a blue deck on indigo. |
| `concept-b-puck` | **Pixel**. A glossy bezel with the pointing hand drawn in glowing dots, a nod to the classic Mac hand cursor. |
| `concept-c-deck` | **Deck**. Three stacked cards with a white line-art hand. |

To use a concept as the app icon:

```bash
swift DeckHand/Scripts/make-app-icons.swift website/brand/concept-a-sticker-master.png
```

To switch the site's icon, regenerate `assets/icon-*.png`, `favicon-*.png`
and `apple-touch-icon.png` from the chosen concept's PNG.
