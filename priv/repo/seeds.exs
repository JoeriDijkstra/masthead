alias Ledger.Accounts
alias Ledger.Sites
alias Ledger.Content

# Demo user
{:ok, user} =
  case Accounts.get_user_by_email("joeri@example.com") do
    nil -> Accounts.register_user(%{"email" => "joeri@example.com", "password" => "password1234"})
    existing -> {:ok, existing}
  end

# Demo site
{:ok, site} =
  case Sites.get_site_by_slug("joeri") do
    nil ->
      Sites.create_site(%{
        "slug" => "joeri",
        "name" => "Joeri's Notebook",
        "title" => "Joeri's Notebook",
        "description" => "Notes on building things in Elixir, distributed systems, and the messy middle of company-building.",
        "owner_id" => user.id
      })

    existing ->
      {:ok, existing}
  end

# Sample posts (only if site has no posts yet)
case Content.list_posts(site.id) do
  [] ->
    posts = [
      %{
        "title" => "Hello from Ledger",
        "excerpt" => "First post on Ledger — what it is, why it exists, and what's intentionally missing.",
        "body" => """
        ## Welcome

        This is the first post on **Ledger**, a minimal multi-tenant blogging platform
        I built to scratch my own itch. The whole thing is a few thousand lines of
        Phoenix + LiveView and it deploys as a single OTP release.

        ### What it does

        - Each user can create one or more *sites*
        - Each site is served on its own subdomain (`<slug>.lvh.me` in dev)
        - Posts and pages are written in Markdown
        - Themes are Elixir modules — no admin theme editor, on purpose

        ### What it deliberately doesn't do

        - No WYSIWYG editor
        - No plugin system
        - No analytics dashboard
        - No team accounts (yet)
        - No custom domains (yet)

        The goal is to keep the codebase small enough that any single person can
        read it in an afternoon and understand the whole thing.

        > Software grows by accretion. Removing things is the work.
        """,
        "published" => true
      },
      %{
        "title" => "Why subdomains, not paths",
        "excerpt" => "A note on why each Ledger site lives at its own subdomain instead of `/users/joeri/posts/...`.",
        "body" => """
        Multi-tenant SaaS apps tend to split into two camps:

        1. **Path-based tenancy:** `app.com/u/joeri/posts/hello`
        2. **Subdomain-based tenancy:** `joeri.app.com/posts/hello`

        Ledger picks subdomains. Here's why.

        ### Identity belongs in the host

        A site is a thing in the world. It has its own brand, its own home, its
        own audience. Putting `joeri/` in a URL path makes every visitor a tenant
        of the larger app. Putting it in the subdomain makes the site feel like
        the destination.

        ### Custom domains become a config flip

        Once you're serving by `Host:` header, custom domains (`blog.joeri.dev`)
        are just another row in the `sites` table mapping host → site_id. With
        path-based tenancy you'd have to rewrite every link.

        ### The cost

        Subdomains need wildcard DNS and HTTPS. In dev you get `*.lvh.me` for
        free. In prod, Let's Encrypt + a wildcard cert handles it.
        """,
        "published" => true
      },
      %{
        "title" => "Draft: what's next",
        "excerpt" => "Drafts are hidden from public listings.",
        "body" => "This is a draft. It shouldn't show up on the homepage of the site.",
        "published" => false
      }
    ]

    for attrs <- posts do
      {:ok, _} = Content.create_post(site.id, attrs)
    end

    {:ok, _about} =
      Content.create_page(site.id, %{
        "title" => "About",
        "slug" => "about",
        "body" => """
        ## About this site

        This is the example blog seeded with Ledger. It exists so I have something
        concrete to point at when I tell people what Ledger is.

        I'm **Joeri** — Elixir/Phoenix developer based in the Netherlands, currently
        exploring B2B SaaS as a solo founder.

        Find me at [eyra.co](https://eyra.co).
        """,
        "published" => true
      })

  _ ->
    IO.puts("Site already has posts; skipping seed content.")
end

IO.puts("""

Seeded:
  user:  joeri@example.com / password1234
  site:  http://joeri.lvh.me:4000
  admin: http://localhost:4000/admin
""")
