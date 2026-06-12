defmodule Masthead.ContentImportTest do
  use Masthead.DataCase, async: true

  alias Masthead.{Accounts, Content, Sites, Themes}
  alias Masthead.Content.Import

  describe "attrs_from_file/2" do
    test "detects the format from the extension" do
      assert Import.attrs_from_file("a.md", "x")["format"] == "markdown"
      assert Import.attrs_from_file("a.markdown", "x")["format"] == "markdown"
      assert Import.attrs_from_file("a.txt", "x")["format"] == "markdown"
      assert Import.attrs_from_file("a.html", "x")["format"] == "html"
      assert Import.attrs_from_file("a.HTM", "x")["format"] == "html"
    end

    test "humanises the title from the filename" do
      assert Import.attrs_from_file("about-us.md", "x")["title"] == "About us"
      assert Import.attrs_from_file("my_first_post.html", "x")["title"] == "My first post"
      assert Import.attrs_from_file("/tmp/Contact.md", "x")["title"] == "Contact"
    end

    test "falls back to a title when the name is empty" do
      assert Import.attrs_from_file(".md", "x")["title"] == "Untitled"
    end

    test "carries the body through and leaves the slug blank for derivation" do
      attrs = Import.attrs_from_file("notes.md", "# Heading\n\nBody")
      assert attrs["body"] == "# Heading\n\nBody"
      assert attrs["slug"] == ""
    end

    test "files without frontmatter default to draft (unpublished)" do
      assert Import.attrs_from_file("notes.md", "hello")["published"] == "false"
    end
  end

  describe "YAML frontmatter" do
    @with_frontmatter """
    ---
    title: "Compressing images in Elixir with Mogrify"
    date: 2024-02-14T19:57:24+01:00
    draft: false
    ---
    The actual body starts here.
    """

    test "strips the frontmatter, takes the title, and honours draft: false" do
      attrs = Import.attrs_from_file("compressing-images.md", @with_frontmatter)

      assert attrs["title"] == "Compressing images in Elixir with Mogrify"
      assert attrs["body"] == "The actual body starts here.\n"
      refute attrs["body"] =~ "title:"
      refute attrs["body"] =~ "---"
      assert attrs["published"] == "true"
    end

    test "draft: true keeps it unpublished" do
      body = "---\ntitle: Draft post\ndraft: true\n---\nBody"
      attrs = Import.attrs_from_file("x.md", body)
      assert attrs["title"] == "Draft post"
      assert attrs["published"] == "false"
    end

    test "frontmatter without a draft key stays a draft" do
      assert Import.attrs_from_file("x.md", "---\ntitle: Hi\n---\nBody")["published"] == "false"
    end

    test "falls back to the filename title when frontmatter omits title" do
      attrs = Import.attrs_from_file("my-post.md", "---\ndraft: false\n---\nBody")
      assert attrs["title"] == "My post"
      assert attrs["published"] == "true"
    end

    test "handles single-quoted values and CRLF line endings" do
      body = "---\r\ntitle: 'Quoted Title'\r\ndraft: false\r\n---\r\nBody\r\n"
      attrs = Import.attrs_from_file("x.md", body)
      assert attrs["title"] == "Quoted Title"
      assert attrs["published"] == "true"
    end

    test "a body that merely contains --- is left untouched" do
      body = "Intro paragraph.\n\n---\n\nMore text."
      attrs = Import.attrs_from_file("x.md", body)
      assert attrs["body"] == body
      assert attrs["title"] == "X"
    end
  end

  describe "bulk import via the content context" do
    setup do
      Themes.Seed.run()

      {:ok, user} =
        Accounts.register_user(%{
          "email" => "ci-#{System.unique_integer([:positive])}@example.com",
          "password" => "password1234"
        })

      default = Themes.get_built_in_by_slug("default")

      {:ok, site} =
        Sites.create_site(%{
          "slug" => "ci#{System.unique_integer([:positive])}",
          "name" => "CI Test",
          "owner_id" => user.id,
          "theme_id" => default.id
        })

      %{site: site}
    end

    test "creating posts from imported files yields unpublished drafts", %{site: site} do
      files = [{"first.md", "one"}, {"second.html", "<p>two</p>"}]

      for {name, body} <- files do
        {:ok, _} = Content.create_post(site.id, Import.attrs_from_file(name, body))
      end

      posts = Content.list_posts(site.id)
      by_title = Map.new(posts, &{&1.title, &1})

      assert Map.keys(by_title) |> Enum.sort() == ["First", "Second"]
      assert by_title["First"].format == "markdown"
      assert by_title["First"].body == "one"
      assert by_title["First"].slug == "first"
      assert by_title["Second"].format == "html"
      assert Enum.all?(posts, &(&1.published == false))
    end

    test "frontmatter draft: false publishes the imported post", %{site: site} do
      published = "---\ntitle: Live one\ndraft: false\n---\nBody"
      drafted = "---\ntitle: Held back\ndraft: true\n---\nBody"

      for {name, body} <- [{"a.md", published}, {"b.md", drafted}] do
        {:ok, _} = Content.create_post(site.id, Import.attrs_from_file(name, body))
      end

      by_title = Content.list_posts(site.id) |> Map.new(&{&1.title, &1})
      assert by_title["Live one"].published == true
      assert by_title["Held back"].published == false
    end

    test "creating pages from imported files yields drafts", %{site: site} do
      files = [{"about.md", "a"}, {"terms.md", "b"}]

      for {name, body} <- files do
        {:ok, _} = Content.create_page(site.id, Import.attrs_from_file(name, body))
      end

      titles = Content.list_pages(site.id) |> Enum.map(& &1.title) |> Enum.sort()
      assert titles == ["About", "Terms"]
    end
  end
end
