# Ledger

Open-source, multi-tenant publishing platform for blogs and small business
sites. Each site runs on its own subdomain, content is written in Markdown
or HTML, and the whole project deploys as a single application.

A hosted instance runs at [**ledger-cloud.com**](https://ledger-cloud.com)
— sign up there to use Ledger without operating it yourself, or follow the
instructions below to self-host.

## What you get

- **Unlimited sites, one account.** Manage multiple brands or products
  from a single dashboard.
- **Custom subdomains with HTTPS.** Wildcard TLS is provisioned
  automatically; every site is served at `<slug>.<your-domain>`.
- **Markdown and HTML editors.** Live preview, syntax-aware textarea.
- **Built-in blog pages.** Mark any page as a blog and the post list is
  generated for you. Set it as the homepage to make it the front page.
- **Image library.** Upload once, paste ready-made Markdown or HTML embed
  snippets into any post or page.
- **Safe HTML by default.** All rendered content is run through a
  configurable allowlist sanitizer before reaching the browser.
- **Three themes shipped.** Default (compact / typographic), Studio
  (editorial / blue accent), and Blank (zero chrome — bring your own HTML).

## Architecture

- Phoenix LiveView app, single Postgres database, single OTP release.
- Multi-tenancy resolved at the `Host:` header by
  `LedgerWeb.Plugs.Subdomain` — site rows in the `sites` table are looked
  up by subdomain on every request and assigned to
  `conn.assigns.current_site`.
- Two routers: `LedgerWeb.PublicRouter` serves site-scoped public URLs
  (`/`, `/posts/:slug`, `/:slug`); `LedgerWeb.Router` serves the admin
  and marketing surface on the bare app host.
- Object storage is pluggable via `Ledger.Storage.Adapter`. Ships with a
  local-disk adapter (dev) and an S3-compatible adapter (prod —
  tested against [Tigris](https://www.tigrisdata.com)).

## Run it locally

Requires Elixir 1.18+, Erlang/OTP 28+, Postgres 14+.

```bash
mix deps.get
mix ecto.setup        # creates DB, migrates, seeds an example site
mix phx.server
```

Open:

- `http://localhost:4000` — admin and marketing pages
- `http://joeri.lvh.me:4000` — seeded example site

`*.lvh.me` is a public DNS record that resolves to `127.0.0.1`, so
subdomain-based tenancy works in dev without `/etc/hosts` edits.

Default seeded credentials:

```
email:    joeri@example.com
password: password1234
```

## Configuration

All prod config is read from environment variables (see
[`config/runtime.exs`](config/runtime.exs)).

### Required

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Postgres connection string |
| `SECRET_KEY_BASE` | Cookie / LiveView token signing key (`mix phx.gen.secret`) |
| `PHX_SERVER` | `true` to start the HTTP server |
| `PHX_HOST` | The canonical hostname (e.g. `ledger-cloud.com`) |
| `APP_HOSTS` | Comma-separated hostnames treated as the bare app surface. Subdomains of any of these are routed as sites. Defaults to `PHX_HOST`. |

### Optional — object storage (S3-compatible)

If `BUCKET_NAME` is set, the S3 storage adapter takes over. Files go to
the configured bucket and public URLs are generated as
`https://<bucket>.<endpoint-host>/<key>`.

| Var | Example |
|---|---|
| `BUCKET_NAME` | `your-bucket-name` |
| `AWS_ENDPOINT_URL_S3` | `https://fly.storage.tigris.dev` |
| `AWS_REGION` | `auto` |
| `AWS_ACCESS_KEY_ID` | _from your storage provider_ |
| `AWS_SECRET_ACCESS_KEY` | _from your storage provider_ |

The bucket must be configured for public read (either via bucket policy
or per-object ACL) for image embeds to resolve in browsers.

## Deploy

Quick summary for [Fly.io](https://fly.io) with Tigris object storage:

```bash
fly launch                                      # detects Phoenix
fly postgres create && fly postgres attach ...  # provision DB
fly storage create                              # provision Tigris bucket
fly secrets set \
  PHX_HOST=your-domain.com \
  APP_HOSTS=your-domain.com \
  SECRET_KEY_BASE=$(mix phx.gen.secret)
fly certs add your-domain.com
fly certs add "*.your-domain.com"               # wildcard for subdomains
# Add the DNS records Fly prints, then:
fly deploy
```

Set bucket access to public in the Tigris dashboard, or apply a public
bucket policy. Wildcard TLS issuance via Let's Encrypt requires the
DNS-01 challenge — Fly prints the TXT record to add at your registrar.

## Project layout

```
lib/
├── ledger/                          # business logic
│   ├── accounts/                    # users + session auth
│   ├── sites/                       # tenant sites
│   ├── content/                     # posts, pages, HTML sanitizer
│   ├── uploads/                     # file metadata
│   ├── storage/                     # local + S3 adapters
│   └── themes/                      # default, studio, blank
└── ledger_web/
    ├── plugs/subdomain.ex           # host → site resolution
    ├── public_router.ex             # site-scoped routes
    ├── router.ex                    # admin + marketing routes
    ├── controllers/                 # public + auth controllers
    └── live/admin/                  # all admin LiveViews
```

## Contributing

Issues and pull requests welcome at
[github.com/JoeriDijkstra/ledger](https://github.com/JoeriDijkstra/ledger).

## License

MIT.
