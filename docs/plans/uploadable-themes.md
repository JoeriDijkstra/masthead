# Uploadable & customized themes — framework plan

Today, themes are Elixir modules in `lib/ledger/themes/` registered in a
hardcoded map. To unlock end-user uploads and per-site customization we need
to move themes from "code shipped with the release" to "data living in the
database + object storage, rendered through a sandboxed template engine."

This plan lays out the framework. It does **not** yet redesign every screen
or finalize every token in the manifest — those land in follow-up plans once
the substrate exists.

## Decisions taken upfront

| Question | Answer |
|---|---|
| Customization depth | **Full theme package**: CSS + templates + assets, uploaded as a single archive. |
| Scope | **Shared library with per-site override**: themes belong to an owner (or are system), reusable across sites; each site stores its own token + CSS-override layer. |
| Built-ins | **Migrate to records**: Default / Studio / Blank become seeded theme rows; the existing modules are deleted. |

These three choices together imply: a new templating substrate (sandboxed,
not EEx), a new schema, an upload pipeline, an admin surface, and a one-shot
migration of every existing site's `theme` string.

## Non-goals (for this framework)

- Live theme preview / WYSIWYG editing — token editor is a plain form for v1.
- Theme marketplace, ratings, paid distribution.
- SASS/Tailwind preprocessing inside the platform — themes ship plain CSS.
- Server-side image processing for theme assets.
- Hot-swapping a theme on a running site without a page reload.

## Architecture overview

```
┌────────────────────┐  upload      ┌──────────────────────┐
│  Admin LiveView    │ ───────────▶ │  Ledger.Themes.Pkg   │
│  /themes (library) │              │  validate + unpack   │
└────────────────────┘              └─────────┬────────────┘
                                              │ stream files
                                              ▼
                                    ┌──────────────────────┐
                                    │  Ledger.Storage      │
                                    │  themes/<slug>/<ver>/│
                                    └──────────────────────┘
                                              ▲
       site picks theme + tokens              │
              │                               │
              ▼                               │
┌────────────────────┐  render      ┌─────────┴────────────┐
│ PublicController   │ ───────────▶ │  Ledger.Themes       │
│ (per request)      │              │  .Renderer (Liquid)  │
└────────────────────┘              └──────────────────────┘
```

### Templating engine

EEx is unsafe — it compiles to Elixir, gives uploads arbitrary code execution.
We need a sandboxed engine. Use **Solid** (Liquid for Elixir, hex
`solid`) for v1:

- Pure-Elixir Liquid parser/renderer, sandboxed by design (no module
  resolution, no eval, no I/O).
- Familiar to anyone who has touched Shopify or Jekyll themes — easy to
  document and port existing themes.
- Custom filters/tags are an explicit allowlist we control.

We will define a small set of Ledger-specific filters/tags (e.g.
`{% asset 'logo.png' %}`, `{{ post.published_at | date: '%B %-d, %Y' }}`).
Anything not in that allowlist isn't reachable from a template.

### Theme package format

A theme is a zip archive (`.zip`, max ~5 MB to start) with this layout:

```
manifest.json              # required
templates/
  layout.liquid            # required — wraps every render target
  index.liquid             # required
  post.liquid              # required
  page.liquid              # required
  blog.liquid              # required
  not_found.liquid         # required
  partials/                # optional, included via {% render 'foo' %}
theme.css                  # required — base stylesheet
assets/                    # optional — images, fonts, additional .css/.js
```

**Manifest** declares the customization surface — the tokens a site owner
can tweak in the per-site override UI:

```json
{
  "name": "Studio",
  "slug": "studio",
  "version": "1.0.0",
  "author": "Ledger",
  "description": "Editorial / blue accent.",
  "tokens": [
    { "key": "accent",      "label": "Accent color",    "type": "color",  "default": "#2563eb" },
    { "key": "font_family", "label": "Body font",       "type": "string", "default": "Inter, sans-serif" },
    { "key": "max_width",   "label": "Content width",   "type": "length", "default": "880px" }
  ]
}
```

Tokens are emitted at render time as CSS custom properties on `:root`
(`--accent`, `--font-family`, ...) **and** are available inside Liquid via
`{{ theme.tokens.accent }}`. Site overrides merge over manifest defaults.

### Storage layout

Themes live alongside uploads in the existing `Ledger.Storage` adapter, so
both Local and S3 backends work without new code:

```
themes/
  <theme-slug>/
    <version>/
      manifest.json
      templates/*.liquid
      theme.css
      assets/...
```

Asset URLs resolve through `Storage.url/1`, so the `{% asset 'foo.png' %}`
tag returns `/uploads/themes/studio/1.0.0/assets/foo.png` (local) or the
public S3 URL (production).

### Database schema

```
themes
  id, slug, name, description, version,
  source enum: built_in | uploaded,
  owner_id   nullable references users(id)    -- nil for built-ins
  storage_path string                          -- e.g. "themes/studio/1.0.0"
  manifest    jsonb                            -- parsed manifest
  public      boolean default false            -- listed in library?
  inserted_at, updated_at

sites
  - drop:  theme :string
  + add:   theme_id           references themes(id)
  + add:   theme_tokens       jsonb default '{}'  -- per-site overrides
  + add:   theme_css_overrides text default ''    -- escape hatch
```

Migration path:
1. Add new columns to `sites` (nullable initially).
2. Seed built-in theme rows.
3. Backfill `sites.theme_id` from the legacy `sites.theme` string.
4. Make `sites.theme_id` non-null + drop `sites.theme`.

### Rendering pipeline

`Ledger.Themes.Renderer` replaces the current behaviour dispatch:

1. Look up `theme = Themes.get_for_site(site)` (cache hit on theme_id + version).
2. Compute `tokens = Map.merge(manifest_defaults, site.theme_tokens)`.
3. Build a Liquid context: `site`, `posts`, `post`, `pages`, `page`,
   `body_html` (already sanitized), `theme: %{tokens: tokens, asset_base: ...}`.
4. Render the target template (e.g. `post.liquid`) into a string.
5. Render `layout.liquid` with `content` = step 4's output.
6. Prepend `<style>` block: token CSS-vars + `theme.css` + `site.theme_css_overrides`.
7. Send response.

Parsed templates are cached in `:persistent_term` keyed by `{theme_id,
version}`. Cache is busted when a theme row is updated.

### Template context

Solid can't introspect Ecto structs, and we don't want themes reaching into
schema internals anyway. A **presenter** layer (`Ledger.Themes.Presenter`)
projects each schema into a plain map of explicitly-allowed fields. The
presenter is the only code path between the database and a template — if a
field isn't in the presenter, it isn't reachable from Liquid.

#### Presenter shapes

```elixir
site:
  name, title, description, slug

post:
  title, slug, excerpt, published_at,
  url            # "/posts/<slug>"

page:
  title, slug, format,
  url            # "/<slug>"
```

Fields explicitly NOT exposed: `owner_id`, `site_id`, `inserted_at`,
`updated_at`, the raw `body`, internal IDs. Add fields by extending the
presenter — don't widen the projection ad hoc inside the renderer.

#### Variables available per render target

Every target gets the base context plus target-specific additions:

| Variable | Always | index | post | page | blog | not_found |
|---|---|---|---|---|---|---|
| `site` | ✓ | | | | | |
| `pages` (nav list) | ✓ | | | | | |
| `theme.tokens.*` | ✓ | | | | | |
| `posts` | | ✓ | | | ✓ | |
| `post` | | | ✓ | | | |
| `page` | | | | ✓ | ✓ | |
| `body_html` | | | ✓ | ✓ | ✓ | |

`theme.tokens` is the merge of manifest defaults and per-site overrides.
Token keys come from the manifest, so a theme that declares an `accent`
token can read it as `{{ theme.tokens.accent }}`.

#### The `body_html` contract

`body_html` arrives at the template **already sanitized** by
`Ledger.Content.HTML` (the existing allowlist sanitizer). Solid escapes
output by default, so themes must opt into emitting it raw:

```liquid
{{ body_html | raw }}
```

`raw` is a custom filter we register in `Ledger.Themes.Sandbox`. It is the
only mechanism for emitting pre-rendered HTML from a template. Templates
have no access to the unsanitized `post.body` or `page.body` — those fields
are not in the presenter.

#### Worked example

`post.liquid` reproducing the current `lib/ledger/themes/default.ex:40`
`render_post/1`:

```liquid
{% layout 'layout' %}
<article class="post">
  <header>
    <h1>{{ post.title }}</h1>
    {% if post.published_at %}
      <time datetime="{{ post.published_at | date: '%Y-%m-%dT%H:%M:%SZ' }}">
        {{ post.published_at | date: '%B %-d, %Y' }}
      </time>
    {% endif %}
  </header>
  <div class="post-body">{{ body_html | raw }}</div>
  <footer><a href="/">&larr; Back to {{ site.name }}</a></footer>
</article>
```

`layout.liquid` wrapping every target — receives the same context plus a
`content` variable holding the rendered inner template:

```liquid
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{{ site.title | default: site.name }}</title>
    {% if site.description %}<meta name="description" content="{{ site.description }}" />{% endif %}
    <style>
      :root { --accent: {{ theme.tokens.accent }}; }
      {{ theme_css | raw }}
      {{ site_css_overrides | raw }}
    </style>
  </head>
  <body>
    <nav class="site-nav">
      <a class="brand" href="/">{{ site.name }}</a>
      {% for p in pages %}<a href="{{ p.url }}">{{ p.title }}</a>{% endfor %}
    </nav>
    <main>{{ content | raw }}</main>
  </body>
</html>
```

#### Custom filters & tags (allowlist)

Registered in `Ledger.Themes.Sandbox`; nothing else is callable from a
template:

| Name | Form | Purpose |
|---|---|---|
| `raw` | `{{ value | raw }}` | Emit pre-sanitized HTML without re-escaping. |
| `date` | `{{ dt | date: '%B %-d, %Y' }}` | `Calendar.strftime` wrapper. |
| `default` | `{{ value | default: 'fallback' }}` | Standard Liquid; Solid ships it. |
| `asset` | `{% asset 'logo.png' %}` | Resolves to `Storage.url("themes/<slug>/<ver>/assets/logo.png")`. |

If a theme needs data that isn't in the table above (e.g. a featured-post
slot, a tag list), the path is: extend the presenter and the controller's
assigns — **not** add a tag that performs a DB query. Rendering stays O(1)
DB calls per page.

#### Asset namespaces

Two distinct namespaces, deliberately kept separate:

- **Theme-bundled assets** (`{% asset 'foo.png' %}`) — files shipped inside
  the theme zip, served from `themes/<slug>/<version>/assets/`. Used for
  logos, fonts, icons that belong to the theme.
- **Site uploads** — files in the existing `Uploads` flow. Themes don't see
  these as separate variables; they're already embedded inside `body_html`
  via Markdown/HTML by the time the template runs.

## Phased implementation

Each phase ends with a runnable app and passing tests. Don't merge a phase
without exercising it manually + via integration test.

### Phase 0 — substrate

- Add `:solid` dependency. Spike a tiny render to confirm sandboxing works.
- Create `Ledger.Themes.Sandbox` module: thin wrapper around Solid that
  preloads our custom filter/tag allowlist and rejects unknown ones.
- Create `Ledger.Themes.Manifest` with a JSON-schema-style validator
  (required keys, token type allowlist: `color | string | length | number`).

### Phase 1 — schema & migration prep

- New migration: `create_themes` (columns above).
- New migration: `add_theme_id_to_sites` (nullable `theme_id`, `theme_tokens`,
  `theme_css_overrides`).
- `Ledger.Themes.Theme` schema module replaces the existing behaviour file —
  rename old `theme.ex` to `behaviour.ex` temporarily, then delete in Phase 3.
- `Ledger.Themes` context grows: `list_themes/1` (by owner + public),
  `get_theme!/1`, `create_theme/2`, `update_theme/2`, `delete_theme/1`.

### Phase 2 — built-in themes as packages

- Author Liquid versions of `default`, `studio`, `blank` in
  `priv/themes/<slug>/` (in-repo, version-controlled).
- Write a seed task `Ledger.Themes.Seed` that, on each release boot:
  - For each built-in: compare on-disk version to DB row's version; upsert
    if missing or newer.
  - Copies files into `Storage` under `themes/<slug>/<version>/`.
- Add a migration that backfills `sites.theme_id` from the old `theme`
  string, then makes it non-null and drops `theme`.
- Delete `lib/ledger/themes/{default,studio,blank}.ex` and the behaviour file.
- Update `PublicController` to call `Renderer` instead of `apply/3`.

This is the riskiest single step — every existing site has to come out the
other side rendering identically. Snapshot-test each built-in page (index /
post / page / blog / 404) against the old output before & after.

### Phase 3 — rendering pipeline

- Implement `Ledger.Themes.Renderer` per "Rendering pipeline" above.
- Define custom Liquid tags/filters:
  - `{% asset 'path' %}` → resolves to `Storage.url("themes/<slug>/<v>/assets/path")`.
  - `{{ datetime | format: '%B %-d, %Y' }}` (Calendar.strftime wrapper).
  - `{{ html | raw }}` — explicit, because pre-sanitized `body_html` must not
    be double-escaped.
- Wire `:persistent_term` cache; invalidate from `Themes.update_theme/2`.

### Phase 4 — upload & extraction

- `Ledger.Themes.Package` module:
  - `validate_archive/1`: zip size cap, total uncompressed size cap (zip-bomb),
    file count cap, path traversal check (no `..`, no absolute paths, no
    symlinks), extension allowlist.
  - `extract/2`: stream into a temp dir, validate manifest, parse every
    `.liquid` file (reject on parse error), then promote files into
    `Storage`.
- `LedgerWeb.AdminLive.ThemeLibrary` LiveView at `/themes`:
  - List user's themes + built-ins.
  - Upload form using `Phoenix.LiveView.Uploads`.
  - Per-row: delete (if owner & not in use), set public (later).

### Phase 5 — per-site customization UI

- Extend `LedgerWeb.AdminLive.SiteSettings`:
  - Theme picker now selects a theme row, not a name string.
  - On selection, render a token form derived from the chosen theme's
    `manifest.tokens` (color picker, length input, free-text).
  - Optional collapsible "Custom CSS" textarea → `site.theme_css_overrides`.
- On save, persist `theme_id`, `theme_tokens` (jsonb), `theme_css_overrides`.

### Phase 6 — hardening

- Cap `theme_css_overrides` length (e.g. 50 KB).
- Strip `@import` / `url(javascript:...)` patterns from overrides at render
  time (small allowlist sanitizer — themes are not arbitrary CSS injection).
- Rate-limit theme uploads per user.
- Audit log: theme created / updated / deleted.

### Phase 7 — docs & rollout

- README + new `docs/themes.md`: package format, manifest schema, available
  Liquid filters/tags, examples.
- Ship an example theme repo (`examples/themes/minimal/`) referenced from
  the docs.
- Announce in release notes.

## Files that will change

| Path | Change |
|---|---|
| `mix.exs` | Add `:solid` dep |
| `lib/ledger/themes.ex` | Rewrite — becomes the context module for the new schema |
| `lib/ledger/themes/theme.ex` | Replace behaviour with `Ecto.Schema` |
| `lib/ledger/themes/{default,studio,blank}.ex` | Delete |
| `lib/ledger/themes/manifest.ex` | New — manifest validator |
| `lib/ledger/themes/package.ex` | New — zip validation / extraction |
| `lib/ledger/themes/renderer.ex` | New — Liquid render pipeline |
| `lib/ledger/themes/sandbox.ex` | New — Solid wrapper with filter/tag allowlist |
| `lib/ledger/themes/seed.ex` | New — boot-time seeding of built-ins |
| `lib/ledger/sites/site.ex` | Drop `theme` field, add `theme_id`/`theme_tokens`/`theme_css_overrides` |
| `lib/ledger_web/controllers/public_controller.ex` | Call `Renderer` instead of `apply/3` |
| `lib/ledger_web/live/admin/site_settings.ex` | Theme picker + token form |
| `lib/ledger_web/live/admin/theme_library.ex` | New — library + upload UI |
| `lib/ledger_web/router.ex` | Register `/themes` route |
| `priv/themes/{default,studio,blank}/...` | New — Liquid + CSS sources |
| `priv/repo/migrations/*_create_themes.exs` | New |
| `priv/repo/migrations/*_add_theme_id_to_sites.exs` | New |
| `priv/repo/migrations/*_drop_legacy_theme_column.exs` | New (Phase 2 tail) |

## Risks & open questions

- **Solid coverage**: confirm Solid supports `render` (partials) and
  custom tags before Phase 0 closes. If not, evaluate Liquex.
- **Snapshot equivalence**: porting the three built-in themes to Liquid is
  fiddly. Plan for visual diffs, not exact-byte equality — e.g. attribute
  ordering may shift.
- **Asset hot-linking**: themes referencing absolute external URLs
  (`https://rsms.me/inter/inter.css` in Studio today) — keep allowed for v1,
  document the implications for users uploading their own.
- **Versioning**: storing multiple versions in `themes/<slug>/<version>/`
  is forward-compatible with "users can roll back" but we don't expose that
  in the UI yet. Keep the storage layout, defer the UI.
- **Reserved slugs**: `default`/`studio`/`blank` must be unique system slugs
  that user uploads can't overwrite. Enforce in `Themes.create_theme/2`.

## What "framework is done" means

The framework is finished when:

1. A site has zero references to a hardcoded theme module.
2. All three built-in looks render via the same Liquid pipeline as user uploads.
3. A user can upload a valid zip, see it in the library, pick it on a site,
   and tweak its declared tokens — end to end.
4. The old `lib/ledger/themes/{default,studio,blank}.ex` files no longer
   exist in the tree.
