defmodule Masthead.Sites do
  import Ecto.Query
  alias Masthead.Repo
  alias Masthead.Sites.Site

  def list_sites_for_user(user_id) do
    Repo.all(
      from s in Site, where: s.owner_id == ^user_id and is_nil(s.deleted_at), order_by: s.name
    )
  end

  def get_site!(id), do: Repo.get!(Site, id)

  def get_user_site!(user_id, id) do
    Repo.one!(
      from s in Site, where: s.id == ^id and s.owner_id == ^user_id and is_nil(s.deleted_at)
    )
  end

  def get_user_site_by_slug!(user_id, slug) do
    Repo.one!(
      from s in Site, where: s.slug == ^slug and s.owner_id == ^user_id and is_nil(s.deleted_at)
    )
  end

  @doc """
  Public resolver used by the Subdomain plug. Disabled or soft-deleted
  sites resolve to `nil` so the request 404s.
  """
  def get_site_by_slug(slug) when is_binary(slug) do
    Repo.one(
      from s in Site, where: s.slug == ^slug and is_nil(s.disabled_at) and is_nil(s.deleted_at)
    )
  end

  @doc """
  Resolves a site by an `active` custom domain. Only domains that have
  completed verification + cert issuance route traffic — a merely
  configured-but-not-active domain must not serve a site.
  """
  def get_site_by_custom_domain(host) when is_binary(host) do
    host = host |> String.downcase() |> String.trim_trailing(".")

    Repo.one(
      from s in Site,
        where:
          s.custom_domain == ^host and
            s.custom_domain_status == "active" and
            is_nil(s.disabled_at) and
            is_nil(s.deleted_at)
    )
  end

  @doc """
  All custom domains currently serving traffic. Used to build the
  endpoint's dynamic `check_origin` allow-list.
  """
  def list_active_custom_domains do
    Repo.all(
      from s in Site,
        where:
          s.custom_domain_status == "active" and
            not is_nil(s.custom_domain) and
            is_nil(s.disabled_at) and
            is_nil(s.deleted_at),
        select: s.custom_domain
    )
  end

  # ---- admin ----

  @doc """
  Sites for the admin overview (incl. disabled/soft-deleted), with owner
  preloaded. Capped at `count` rows — the overview is meant to be narrowed
  with the filter + search, not paged through.
  """
  def list_all_sites(filter \\ :all, search_query \\ nil, count \\ 20) do
    from(s in Site, order_by: [desc: s.id], preload: [:owner])
    |> apply_filter(filter)
    |> apply_search(search_query)
    |> limit(^count)
    |> Repo.all()
  end

  @doc "Load any site by slug for an admin entering it. Excludes soft-deleted."
  def get_site_for_admin_by_slug!(slug) when is_binary(slug) do
    Repo.one!(from s in Site, where: s.slug == ^slug and is_nil(s.deleted_at))
  end

  defp set_site_timestamp(%Site{} = site, field, value) do
    site |> Ecto.Changeset.change(%{field => value}) |> Repo.update()
  end

  @doc "Pauses a site (stops resolving). Reversible via `enable_site/1`."
  def disable_site(%Site{} = site), do: set_site_timestamp(site, :disabled_at, truncated_now())

  @doc "Un-pauses a site."
  def enable_site(%Site{} = site), do: set_site_timestamp(site, :disabled_at, nil)

  @doc "Soft-deletes a site (hidden from owner + public; retained for recovery)."
  def soft_delete_site(%Site{} = site), do: set_site_timestamp(site, :deleted_at, truncated_now())

  @doc "Restores a soft-deleted site."
  def restore_site(%Site{} = site), do: set_site_timestamp(site, :deleted_at, nil)

  defp truncated_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "Soft-disables every site owned by `user_id` (account-disable cascade)."
  def disable_sites_for_user(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update_all(
      from(s in Site, where: s.owner_id == ^user_id and is_nil(s.disabled_at)),
      set: [disabled_at: now]
    )
  end

  @doc "Re-enables every site owned by `user_id` (account re-enable)."
  def enable_sites_for_user(user_id) do
    Repo.update_all(
      from(s in Site, where: s.owner_id == ^user_id and not is_nil(s.disabled_at)),
      set: [disabled_at: nil]
    )
  end

  def create_site(attrs) do
    with {:ok, site} <-
           %Site{}
           |> Site.create_changeset(attrs_with_default_theme(attrs))
           |> Repo.insert() do
      maybe_create_onboarding_actions(site)
      {:ok, site}
    end
  end

  # Seed the onboarding checklist for a freshly created site with the content
  # actions only. The "set description" nudge is staggered — it's added later,
  # once the site has its first post or page (see `Masthead.Actions`).
  defp maybe_create_onboarding_actions(%Site{} = site) do
    Masthead.Actions.create_action(site, "create_first_post")
    Masthead.Actions.create_action(site, "create_first_page")
    Masthead.Actions.create_action(site, "import_site")
  end

  defp blank?(nil), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""

  # Every site must have a theme_id (NOT NULL). The signup wizard doesn't
  # ask for one — sites start on the built-in "default" theme and can be
  # changed from the settings screen.
  defp attrs_with_default_theme(attrs) do
    has_theme? =
      Map.has_key?(attrs, "theme_id") or Map.has_key?(attrs, :theme_id)

    if has_theme? do
      attrs
    else
      case Masthead.Themes.get_built_in_by_slug("default") do
        nil -> attrs
        theme -> Map.put(attrs, "theme_id", theme.id)
      end
    end
  end

  def update_settings(%Site{} = site, attrs) do
    with {:ok, site} <-
           site
           |> Site.settings_changeset(attrs)
           |> Repo.update() do
      # Completing is idempotent, so it's safe to call on every save.
      unless blank?(site.description),
        do: Masthead.Actions.complete_action(site, "set_description")

      {:ok, site}
    end
  end

  def change_site(%Site{} = site, attrs \\ %{}) do
    Site.create_changeset(site, attrs)
  end

  def change_settings(%Site{} = site, attrs \\ %{}) do
    Site.settings_changeset(site, attrs)
  end

  defp apply_filter(query, filter) do
    case filter do
      :disabled -> from s in query, where: not is_nil(s.disabled_at)
      :deleted -> from s in query, where: not is_nil(s.deleted_at)
      :enabled -> from s in query, where: is_nil(s.disabled_at) and is_nil(s.deleted_at)
      _ -> query
    end
  end

  defp apply_search(query, search_query) do
    if search_query && search_query != "" do
      from s in query, where: ilike(s.name, ^"%#{search_query}%")
    else
      query
    end
  end
end
