defmodule Ledger.ActionsTest do
  use Ledger.DataCase

  alias Ledger.{Accounts, Content, Sites, Actions}
  alias Ledger.Actions.Action

  setup do
    Ledger.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "act-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    %{user: user}
  end

  # A new site is seeded with onboarding actions: create_first_post,
  # create_first_page, and set_description (unless a description is given).
  defp new_site(user, attrs \\ %{}) do
    {:ok, site} =
      Sites.create_site(
        Map.merge(
          %{
            "slug" => "act#{System.unique_integer([:positive])}",
            "name" => "Act Test",
            "owner_id" => user.id
          },
          attrs
        )
      )

    site
  end

  # A site with its seeded onboarding actions cleared, for exercising the
  # action mechanics in isolation.
  defp blank_site(user) do
    site = new_site(user, %{"description" => "blank"})
    Repo.delete_all(from a in Action, where: a.site_id == ^site.id)
    site
  end

  defp pending_keys(site), do: site |> Actions.list_pending() |> Enum.map(& &1.key)
  defp pending?(site, key), do: key in pending_keys(site)

  describe "create_action/2" do
    test "creates a known action from the registry", %{user: user} do
      site = blank_site(user)

      assert {:ok, %Action{} = action} = Actions.create_action(site, "set_description")
      assert action.key == "set_description"
      assert action.status == "pending"
      assert action.priority == 100
      assert action.path == "/#{site.slug}/settings"
      assert is_binary(action.message)
    end

    test "is idempotent — a duplicate (site, key) is a no-op", %{user: user} do
      site = blank_site(user)

      assert {:ok, %Action{}} = Actions.create_action(site, "set_description")
      assert {:ok, :exists} = Actions.create_action(site, "set_description")
      assert Actions.count_pending(site) == 1
    end

    test "rejects an unknown key", %{user: user} do
      site = blank_site(user)
      assert {:error, :unknown_key} = Actions.create_action(site, "does_not_exist")
    end
  end

  describe "complete_action/2" do
    test "completes a pending action and is idempotent", %{user: user} do
      site = blank_site(user)
      {:ok, _} = Actions.create_action(site, "set_description")
      assert Actions.count_pending(site) == 1

      assert :ok = Actions.complete_action(site, "set_description")
      assert Actions.count_pending(site) == 0

      # completing again is safe
      assert :ok = Actions.complete_action(site, "set_description")
      assert Actions.count_pending(site) == 0
    end

    test "accepts a bare site id", %{user: user} do
      site = blank_site(user)
      {:ok, _} = Actions.create_action(site, "set_description")

      assert :ok = Actions.complete_action(site.id, "set_description")
      assert Actions.count_pending(site) == 0
    end

    test "is a no-op when the action is absent", %{user: user} do
      site = blank_site(user)
      assert :ok = Actions.complete_action(site, "set_description")
      assert Actions.count_pending(site) == 0
    end
  end

  describe "dismiss_action/2" do
    test "dismisses a pending action so it leaves pending queries", %{user: user} do
      site = blank_site(user)
      {:ok, _} = Actions.create_action(site, "set_description")
      assert pending?(site, "set_description")

      assert :ok = Actions.dismiss_action(site, "set_description")
      refute pending?(site, "set_description")
      assert Actions.count_pending(site) == 0
    end

    test "is idempotent and safe when absent", %{user: user} do
      site = blank_site(user)
      assert :ok = Actions.dismiss_action(site, "set_description")

      {:ok, _} = Actions.create_action(site, "set_description")
      assert :ok = Actions.dismiss_action(site, "set_description")
      assert :ok = Actions.dismiss_action(site, "set_description")
      assert Actions.count_pending(site) == 0
    end

    test "leaves an already-completed action untouched", %{user: user} do
      site = blank_site(user)
      {:ok, _} = Actions.create_action(site, "set_description")
      :ok = Actions.complete_action(site, "set_description")

      :ok = Actions.dismiss_action(site, "set_description")

      action = Repo.get_by!(Action, site_id: site.id, key: "set_description")
      assert action.status == "completed"
    end
  end

  describe "querying" do
    test "top_action returns the highest-priority pending action", %{user: user} do
      site = blank_site(user)
      {:ok, _} = Actions.create_action(site, "set_description")

      Repo.insert!(%Action{
        site_id: site.id,
        key: "low_priority",
        status: "pending",
        message: "later",
        priority: 1
      })

      assert %Action{key: "set_description"} = Actions.top_action(site)
      assert length(Actions.list_pending(site)) == 2
    end

    test "completed actions are excluded from pending queries", %{user: user} do
      site = blank_site(user)
      {:ok, _} = Actions.create_action(site, "set_description")
      :ok = Actions.complete_action(site, "set_description")

      assert Actions.list_pending(site) == []
      assert Actions.top_action(site) == nil
    end
  end

  describe "site lifecycle hooks" do
    test "a new site is seeded with only the content actions", %{user: user} do
      site = new_site(user)
      assert Enum.sort(pending_keys(site)) == ["create_first_page", "create_first_post"]
    end

    test "top_action for a new site is to create the first post", %{user: user} do
      site = new_site(user)
      assert %Action{key: "create_first_post"} = Actions.top_action(site)
    end

    test "set_description is staggered in once the site gets its first post", %{user: user} do
      site = new_site(user)
      refute pending?(site, "set_description")

      {:ok, _post} = Content.create_post(site.id, %{"title" => "Hello", "slug" => "hello"})
      assert pending?(site, "set_description")
    end

    test "creating the first page also unlocks set_description", %{user: user} do
      site = new_site(user)
      refute pending?(site, "set_description")

      {:ok, _page} = Content.create_page(site.id, %{"title" => "About", "slug" => "about"})
      assert pending?(site, "set_description")
    end

    test "the description nudge is skipped when one is already set", %{user: user} do
      site = new_site(user, %{"description" => "Already described"})

      {:ok, _post} = Content.create_post(site.id, %{"title" => "Hello", "slug" => "hello"})
      refute pending?(site, "set_description")
    end

    test "saving a description completes the unlocked set_description action", %{user: user} do
      site = new_site(user)
      {:ok, _post} = Content.create_post(site.id, %{"title" => "Hello", "slug" => "hello"})
      assert pending?(site, "set_description")

      {:ok, site} = Sites.update_settings(site, %{"description" => "Now described"})
      refute pending?(site, "set_description")
    end

    test "creating the first post completes create_first_post", %{user: user} do
      site = new_site(user)
      assert pending?(site, "create_first_post")

      {:ok, _post} = Content.create_post(site.id, %{"title" => "Hello", "slug" => "hello"})
      refute pending?(site, "create_first_post")
    end

    test "creating the first page completes create_first_page", %{user: user} do
      site = new_site(user)
      assert pending?(site, "create_first_page")

      {:ok, _page} = Content.create_page(site.id, %{"title" => "About", "slug" => "about"})
      refute pending?(site, "create_first_page")
    end
  end
end
