defmodule Ledger.Sites do
  import Ecto.Query
  alias Ledger.Repo
  alias Ledger.Sites.Site

  def list_sites_for_user(user_id) do
    Repo.all(from s in Site, where: s.owner_id == ^user_id, order_by: s.name)
  end

  def get_site!(id), do: Repo.get!(Site, id)

  def get_user_site!(user_id, id) do
    Repo.one!(from s in Site, where: s.id == ^id and s.owner_id == ^user_id)
  end

  def get_user_site_by_slug!(user_id, slug) do
    Repo.one!(from s in Site, where: s.slug == ^slug and s.owner_id == ^user_id)
  end

  @doc """
  Public resolver used by the Subdomain plug. Disabled sites (the owning
  account was disabled) resolve to `nil` so the request 404s.
  """
  def get_site_by_slug(slug) when is_binary(slug) do
    Repo.one(from s in Site, where: s.slug == ^slug and is_nil(s.disabled_at))
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
            is_nil(s.disabled_at)
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
            is_nil(s.disabled_at),
        select: s.custom_domain
    )
  end

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
    %Site{}
    |> Site.create_changeset(attrs_with_default_theme(attrs))
    |> Repo.insert()
  end

  # Every site must have a theme_id (NOT NULL). The signup wizard doesn't
  # ask for one — sites start on the built-in "default" theme and can be
  # changed from the settings screen.
  defp attrs_with_default_theme(attrs) do
    has_theme? =
      Map.has_key?(attrs, "theme_id") or Map.has_key?(attrs, :theme_id)

    if has_theme? do
      attrs
    else
      case Ledger.Themes.get_built_in_by_slug("default") do
        nil -> attrs
        theme -> Map.put(attrs, "theme_id", theme.id)
      end
    end
  end

  def update_settings(%Site{} = site, attrs) do
    site
    |> Site.settings_changeset(attrs)
    |> Repo.update()
  end

  def change_site(%Site{} = site, attrs \\ %{}) do
    Site.create_changeset(site, attrs)
  end

  def change_settings(%Site{} = site, attrs \\ %{}) do
    Site.settings_changeset(site, attrs)
  end
end
