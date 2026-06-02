defmodule Masthead.Themes do
  @moduledoc """
  Context for themes.

  Themes used to be plain Elixir modules registered in a hardcoded map.
  They are migrating to data — rows in the `themes` table plus on-disk /
  object-storage files — so that end users can upload and customize them.

  Every theme is a row here; templates and CSS live on disk (priv for
  built-ins, object storage for uploads).
  """

  import Ecto.Query
  alias Masthead.Repo
  alias Masthead.Themes.Theme

  @doc """
  List every theme visible to the given user:

    * all built-ins,
    * the user's own uploads,
    * public uploads from other users (currently always empty — the
      `public` flag isn't exposed in v1).
  """
  def list_themes(user_id) when is_integer(user_id) do
    Repo.all(
      from t in Theme,
        where: t.source == "built_in" or t.owner_id == ^user_id or t.public == true,
        order_by: ^theme_order()
    )
  end

  def list_themes(nil) do
    Repo.all(from t in Theme, where: t.source == "built_in", order_by: ^theme_order())
  end

  @doc "List only built-in themes."
  def list_built_ins do
    Repo.all(from t in Theme, where: t.source == "built_in", order_by: ^theme_order())
  end

  # Built-ins first, then uploads. Within built-ins the canonical Default
  # always leads (it's what every site starts on), then the rest of the
  # built-ins alphabetically. Uploads come after, by name.
  defp theme_order do
    [
      asc: dynamic([t], t.source),
      asc: dynamic([t], fragment("CASE WHEN ? = 'default' THEN 0 ELSE 1 END", t.slug)),
      asc: dynamic([t], t.name)
    ]
  end

  def get_theme!(id), do: Repo.get!(Theme, id)
  def get_theme(id), do: Repo.get(Theme, id)

  def get_built_in_by_slug(slug) when is_binary(slug) do
    Repo.one(from t in Theme, where: t.slug == ^slug and t.source == "built_in")
  end

  @doc """
  Used by the seed task. Inserts a built-in row if absent, updates it if
  the on-disk version is newer, no-ops otherwise.
  """
  def upsert_built_in(attrs) when is_map(attrs) do
    slug = Map.fetch!(attrs, :slug)

    case get_built_in_by_slug(slug) do
      nil ->
        %Theme{}
        |> Theme.built_in_changeset(attrs)
        |> Repo.insert()

      existing ->
        if existing.version == attrs[:version] do
          {:ok, existing}
        else
          existing
          |> Theme.built_in_changeset(attrs)
          |> Repo.update()
        end
    end
  end

  @doc "Create an uploaded theme. Owner is taken from `attrs.owner_id`."
  def create_upload(attrs) do
    %Theme{} |> Theme.upload_changeset(attrs) |> Repo.insert()
  end

  def update_theme(%Theme{source: "uploaded"} = theme, attrs) do
    theme |> Theme.upload_changeset(attrs) |> Repo.update()
  end

  def delete_theme(%Theme{source: "uploaded"} = theme), do: Repo.delete(theme)
  def delete_theme(%Theme{source: "built_in"}), do: {:error, :built_in_protected}
end
