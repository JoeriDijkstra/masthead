defmodule Masthead.Themes.DeleteThemeTest do
  use Masthead.DataCase

  alias Masthead.{Accounts, Sites, Themes}

  setup do
    # Built-ins (notably "default") must exist — soft-deleted sites are
    # detached onto the default theme when their theme is deleted.
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "del-theme-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, theme} =
      Themes.create_upload(%{
        slug: "ut#{System.unique_integer([:positive])}",
        name: "Uploaded Theme",
        version: "1.0.0",
        storage_path: "themes/uploaded/1.0.0",
        owner_id: user.id
      })

    %{user: user, theme: theme}
  end

  defp site_using(user, theme, name) do
    {:ok, site} =
      Sites.create_site(%{
        "slug" => "uses#{System.unique_integer([:positive])}",
        "name" => name,
        "owner_id" => user.id,
        "theme_id" => theme.id
      })

    site
  end

  test "deletes an uploaded theme that no site uses", %{theme: theme} do
    assert {:ok, _} = Themes.delete_theme(theme)
    refute Themes.get_theme(theme.id)
  end

  test "refuses to delete a theme used by a live site and names it", %{user: user, theme: theme} do
    site = site_using(user, theme, "Live Site")

    assert {:error, {:in_use, names}} = Themes.delete_theme(theme)
    assert site.name in names
    assert Themes.get_theme(theme.id)
  end

  test "a disabled site still blocks deletion", %{user: user, theme: theme} do
    site = site_using(user, theme, "Disabled Site")
    {:ok, _} = Sites.disable_site(site)

    assert {:error, {:in_use, names}} = Themes.delete_theme(theme)
    assert site.name in names
  end

  test "a soft-deleted site no longer blocks: it is detached onto default", %{
    user: user,
    theme: theme
  } do
    site = site_using(user, theme, "Gone Site")
    {:ok, _} = Sites.soft_delete_site(site)

    assert {:ok, _} = Themes.delete_theme(theme)
    refute Themes.get_theme(theme.id)

    default = Themes.get_built_in_by_slug("default")
    assert Repo.get(Masthead.Sites.Site, site.id).theme_id == default.id
  end
end
