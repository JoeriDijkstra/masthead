defmodule Masthead.Themes.DeleteThemeTest do
  use Masthead.DataCase

  alias Masthead.{Accounts, Sites, Themes}

  setup do
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

  test "deletes an uploaded theme that no site uses", %{theme: theme} do
    assert {:ok, _} = Themes.delete_theme(theme)
    refute Themes.get_theme(theme.id)
  end

  test "refuses to delete a theme in use and names the site", %{user: user, theme: theme} do
    {:ok, site} =
      Sites.create_site(%{
        "slug" => "uses#{System.unique_integer([:positive])}",
        "name" => "Live Site",
        "owner_id" => user.id,
        "theme_id" => theme.id
      })

    assert {:error, {:in_use, sites}} = Themes.delete_theme(theme)
    assert {site.name, nil} in sites
    # The theme is untouched.
    assert Themes.get_theme(theme.id)
  end

  test "a soft-deleted site still blocks deletion and is flagged", %{user: user, theme: theme} do
    {:ok, site} =
      Sites.create_site(%{
        "slug" => "uses#{System.unique_integer([:positive])}",
        "name" => "Gone Site",
        "owner_id" => user.id,
        "theme_id" => theme.id
      })

    {:ok, _} = Sites.soft_delete_site(site)

    assert {:error, {:in_use, [{name, deleted_at}]}} = Themes.delete_theme(theme)
    assert name == site.name
    refute is_nil(deleted_at)
  end
end
