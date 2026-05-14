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

  def get_site_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Site, slug: slug)
  end

  def create_site(attrs) do
    %Site{}
    |> Site.create_changeset(attrs)
    |> Repo.insert()
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
