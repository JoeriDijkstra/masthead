defmodule Masthead.Content.TagTest do
  use Masthead.DataCase

  alias Masthead.{Accounts, Content, Sites}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "tag-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "tag#{System.unique_integer([:positive])}",
        "name" => "Tag Site",
        "owner_id" => user.id
      })

    %{user: user, site: site}
  end

  describe "tag CRUD" do
    test "create_tag derives a slug from the name", %{site: site} do
      {:ok, tag} = Content.create_tag(site.id, %{"name" => "Frequently Asked"})
      assert tag.slug == "frequently-asked"
      assert tag.site_id == site.id
    end

    test "create_tag honours an explicit slug", %{site: site} do
      {:ok, tag} = Content.create_tag(site.id, %{"name" => "FAQ", "slug" => "faqs"})
      assert tag.slug == "faqs"
    end

    test "tag slugs are unique per site", %{site: site} do
      {:ok, _} = Content.create_tag(site.id, %{"name" => "News"})
      {:error, changeset} = Content.create_tag(site.id, %{"name" => "News"})
      assert %{slug: [_ | _]} = errors_on(changeset)
    end

    test "the same slug is allowed on different sites", %{site: site, user: user} do
      {:ok, other_site} =
        Sites.create_site(%{
          "slug" => "tagother#{System.unique_integer([:positive])}",
          "name" => "Other",
          "owner_id" => user.id
        })

      {:ok, _} = Content.create_tag(site.id, %{"name" => "News"})
      assert {:ok, _} = Content.create_tag(other_site.id, %{"name" => "News"})
    end

    test "update_tag and delete_tag", %{site: site} do
      {:ok, tag} = Content.create_tag(site.id, %{"name" => "Draft name"})
      {:ok, tag} = Content.update_tag(tag, %{"name" => "Renamed", "slug" => "renamed"})
      assert tag.slug == "renamed"

      {:ok, _} = Content.delete_tag(tag)
      assert Content.list_tags(site.id) == []
    end

    test "list_tags is site-scoped and ordered by name", %{site: site} do
      {:ok, _} = Content.create_tag(site.id, %{"name" => "Zeta"})
      {:ok, _} = Content.create_tag(site.id, %{"name" => "Alpha"})
      assert ["Alpha", "Zeta"] == Content.list_tags(site.id) |> Enum.map(& &1.name)
    end
  end

  describe "list_tags_by_ids/2" do
    test "ignores ids belonging to another site", %{site: site, user: user} do
      {:ok, other_site} =
        Sites.create_site(%{
          "slug" => "tagx#{System.unique_integer([:positive])}",
          "name" => "X",
          "owner_id" => user.id
        })

      {:ok, mine} = Content.create_tag(site.id, %{"name" => "Mine"})
      {:ok, theirs} = Content.create_tag(other_site.id, %{"name" => "Theirs"})

      resolved = Content.list_tags_by_ids(site.id, [mine.id, theirs.id])
      assert Enum.map(resolved, & &1.id) == [mine.id]
    end
  end

  describe "attaching tags to posts" do
    setup %{site: site} do
      {:ok, a} = Content.create_tag(site.id, %{"name" => "Alpha"})
      {:ok, b} = Content.create_tag(site.id, %{"name" => "Beta"})
      %{tag_a: a, tag_b: b}
    end

    test "create_post attaches submitted tag_ids", %{site: site, tag_a: a, tag_b: b} do
      {:ok, post} =
        Content.create_post(site.id, %{
          "title" => "Tagged",
          "tag_ids" => [to_string(a.id), to_string(b.id)]
        })

      slugs = Content.get_post!(site.id, post.id).tags |> Enum.map(& &1.slug) |> Enum.sort()
      assert slugs == ["alpha", "beta"]
    end

    test "update_post replaces the tag set", %{site: site, tag_a: a, tag_b: b} do
      {:ok, post} = Content.create_post(site.id, %{"title" => "P", "tag_ids" => [a.id]})
      {:ok, _} = Content.update_post(post, %{"tag_ids" => [b.id]})

      slugs = Content.get_post!(site.id, post.id).tags |> Enum.map(& &1.slug)
      assert slugs == ["beta"]
    end

    test "update_post with an empty tag_ids clears tags", %{site: site, tag_a: a} do
      {:ok, post} = Content.create_post(site.id, %{"title" => "P", "tag_ids" => [a.id]})
      {:ok, _} = Content.update_post(post, %{"tag_ids" => []})
      assert Content.get_post!(site.id, post.id).tags == []
    end

    test "update_post without a tag_ids key leaves tags untouched", %{site: site, tag_a: a} do
      {:ok, post} = Content.create_post(site.id, %{"title" => "P", "tag_ids" => [a.id]})
      {:ok, _} = Content.update_post(post, %{"title" => "P (edited)"})

      tags = Content.get_post!(site.id, post.id).tags
      assert Enum.map(tags, & &1.slug) == ["alpha"]
    end

    test "a forged tag id from another site is ignored", %{site: site, user: user, tag_a: a} do
      {:ok, other_site} =
        Sites.create_site(%{
          "slug" => "tagf#{System.unique_integer([:positive])}",
          "name" => "F",
          "owner_id" => user.id
        })

      {:ok, foreign} = Content.create_tag(other_site.id, %{"name" => "Foreign"})

      {:ok, post} =
        Content.create_post(site.id, %{"title" => "P", "tag_ids" => [a.id, foreign.id]})

      slugs = Content.get_post!(site.id, post.id).tags |> Enum.map(& &1.slug)
      assert slugs == ["alpha"]
    end
  end

  describe "list_posts/2 filtering and search" do
    setup %{site: site} do
      {:ok, tag} = Content.create_tag(site.id, %{"name" => "News"})

      {:ok, tagged} =
        Content.create_post(site.id, %{"title" => "Tagged one", "tag_ids" => [tag.id]})

      {:ok, untagged} = Content.create_post(site.id, %{"title" => "Lonely"})
      %{tag: tag, tagged: tagged, untagged: untagged}
    end

    test "filters by tag slug", %{site: site, tag: tag, tagged: tagged} do
      ids = Content.list_posts(site.id, filter: tag.slug) |> Enum.map(& &1.id)
      assert ids == [tagged.id]
    end

    test "filters untagged posts", %{site: site, untagged: untagged} do
      ids = Content.list_posts(site.id, filter: :untagged) |> Enum.map(& &1.id)
      assert ids == [untagged.id]
    end

    test "searches by title", %{site: site, tagged: tagged} do
      ids = Content.list_posts(site.id, search: "tagged") |> Enum.map(& &1.id)
      assert ids == [tagged.id]
    end
  end

  describe "blog page filter tags" do
    setup %{site: site} do
      {:ok, news} = Content.create_tag(site.id, %{"name" => "News"})
      {:ok, faq} = Content.create_tag(site.id, %{"name" => "FAQ"})

      {:ok, news_post} =
        Content.create_post(site.id, %{
          "title" => "Newsy",
          "published" => "true",
          "tag_ids" => [news.id]
        })

      {:ok, faq_post} =
        Content.create_post(site.id, %{
          "title" => "Question",
          "published" => "true",
          "tag_ids" => [faq.id]
        })

      {:ok, plain} = Content.create_post(site.id, %{"title" => "Plain", "published" => "true"})

      %{news: news, faq: faq, news_post: news_post, faq_post: faq_post, plain: plain}
    end

    test "create_page attaches submitted filter_tag_ids", %{site: site, news: news} do
      {:ok, page} =
        Content.create_page(site.id, %{
          "title" => "Blog",
          "format" => "blog",
          "filter_tag_ids" => [to_string(news.id)]
        })

      assert Content.get_page!(site.id, page.id).filter_tags |> Enum.map(& &1.slug) == ["news"]
    end

    test "update_page replaces the filter tag set", %{site: site, news: news, faq: faq} do
      {:ok, page} =
        Content.create_page(site.id, %{"title" => "B", "filter_tag_ids" => [news.id]})

      {:ok, _} = Content.update_page(page, %{"filter_tag_ids" => [faq.id]})
      assert Content.get_page!(site.id, page.id).filter_tags |> Enum.map(& &1.slug) == ["faq"]
    end

    test "list_published_posts_filtered keeps only posts with a matching tag", %{
      site: site,
      news: news,
      news_post: news_post
    } do
      ids = Content.list_published_posts_filtered(site.id, [news.id]) |> Enum.map(& &1.id)
      assert ids == [news_post.id]
    end

    test "filtering matches posts carrying any of the tags", %{
      site: site,
      news: news,
      faq: faq,
      news_post: news_post,
      faq_post: faq_post
    } do
      ids =
        Content.list_published_posts_filtered(site.id, [news.id, faq.id])
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([news_post.id, faq_post.id])
    end

    test "an empty filter returns all published posts", %{site: site} do
      assert length(Content.list_published_posts_filtered(site.id, [])) == 3
    end
  end

  describe "search_posts/2" do
    setup %{site: site} do
      {:ok, _} =
        Content.create_post(site.id, %{
          "title" => "Elixir tips",
          "body" => "pattern matching",
          "published" => "true"
        })

      {:ok, _} =
        Content.create_post(site.id, %{"title" => "Draft", "body" => "elixir secret"})

      :ok
    end

    test "matches published posts by title or body, case-insensitively", %{site: site} do
      titles = Content.search_posts(site.id, "ELIXIR") |> Enum.map(& &1.title)
      assert titles == ["Elixir tips"]
    end

    test "a blank query returns all published posts", %{site: site} do
      titles = Content.search_posts(site.id, "  ") |> Enum.map(& &1.title)
      assert titles == ["Elixir tips"]
    end
  end
end
