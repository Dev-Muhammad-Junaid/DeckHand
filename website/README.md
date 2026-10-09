# Deck Hand website

The marketing site for Deck Hand, with a waitlist. Static files plus one
Cloudflare Pages Function.

```
website/
  public/              the site Cloudflare serves (index.html, styles.css, ui.css, site.js, assets/)
  functions/api/       waitlist.js — POST /api/waitlist, stores emails in Cloudflare KV
  src/index.html       page source the mockup builder starts from
  tools/mockups/       rebuilds the app-UI product shots (build.py)
  tools/               fetch-apple-assets.sh, fit_bezels.py
  brand/               icon concepts and masters
```

## Preview locally

```bash
cd website/public
python3 -m http.server 8000      # http://localhost:8000
```

The waitlist form needs the Function, so it only submits on Cloudflare, or
locally with `cd website && npx wrangler pages dev public --kv WAITLIST`.

## Deploy to Cloudflare Pages

1. **Workers & Pages → Create → Pages → Connect to Git**, pick this repository.
2. Build settings:
   - Framework preset: **None**
   - Build command: *(empty)*
   - **Root directory: `website`**
   - **Build output directory: `public`**
   - Production branch: `main`
3. Create the waitlist store: **Workers & Pages → KV → Create namespace**,
   name it `deckhand-waitlist`.
4. In the Pages project, **Settings → Bindings → Add → KV namespace**:
   variable name **`WAITLIST`**, namespace `deckhand-waitlist`. Add it for
   Production (and Preview if you want previews to collect test signups).
5. Redeploy. The site is live at `<project>.pages.dev`.
6. When you have a domain, add it under **Custom domains**, then in
   `src/index.html` replace `/assets/og.png` in the `og:image` tag with
   `https://<your-domain>/assets/og.png`, add
   `<link rel="canonical" href="https://<your-domain>/">`, and rebuild.

### Waitlist signups

Each signup is a KV entry keyed `email:<address>` with the join time,
country (from Cloudflare) and which form was used (`hero` or `closing`).
Duplicates are detected, and a hidden field turns away form-filling bots.
Browse them in the dashboard under the KV namespace, or export:

```bash
npx wrangler kv key list --namespace-id <id> > waitlist-keys.json
```

## Before launch

- [ ] Replace both `[contact email — add before launch]` placeholders in
      `public/privacy.html` with the address that handles privacy requests.
- [ ] Bind the `WAITLIST` KV namespace (above) and test a signup on
      `<project>.pages.dev`.
- [ ] Add the custom domain, then set the absolute `og:image` URL and the
      canonical link in `src/index.html` and rebuild.

The privacy policy is served at `/privacy` (Cloudflare Pages maps it to
`privacy.html`) and is linked from both waitlist forms and the footer. If you
turn on analytics or a mailing tool, update its "Cookies and storage" and
"The waitlist" sections to match.

## Official Apple bezels and app icons

The device frames and app tiles are drawn in CSS until Apple's own assets
are added. On a Mac, from the repository root:

```bash
./website/tools/fetch-apple-assets.sh
python3 website/tools/fit_bezels.py \
  --ipad   "website/brand/apple-bezels/Bezel-iPad-Pro-(M5)/<a landscape PNG>" \
  --iphone "website/brand/apple-bezels/Bezel-iPhone-17/<a portrait PNG>"
```

The first command downloads the bezels from
[Apple Design Resources](https://developer.apple.com/design/resources/#product-bezels)
and the App Store artwork for Xcode, Keynote, Pages, Numbers, Final Cut Pro,
Logic Pro, Pixelmator Pro and Slack into `public/assets/apps/`. The second
finds each bezel's screen cutout and writes `public/bezels.css`, which puts
the mockups inside the real frames. Commit the results; nothing else needs
to change.

Apple's bezels are licensed for showing your app in marketing; check
Apple's terms before using its app icons beyond showing them as content on
a Mac.

## Changing the product shots

The product shots are HTML rebuilt from the SwiftUI views, so they stay
sharp and match the app. Edit the page in `src/index.html` and the screens
in `tools/mockups/` (`build.py` for layouts, `ui.src.css` for the app's
styles, `mac.py` for the Mac desktop and alert), then:

```bash
python3 website/tools/mockups/build.py
```

`styles.css` and `site.js` in `public/` are edited directly.

## Logo

`brand/concept-b2-ipad.svg` is the current icon: a tilted iPad with the
pointing-hand cursor drawn in lit dots. `brand/concept-b2-ipad-master.png`
is the square master used for the app icons
(`swift DeckHand/Scripts/make-app-icons.swift website/brand/concept-b2-ipad-master.png`).
The other concepts are kept for reference.
