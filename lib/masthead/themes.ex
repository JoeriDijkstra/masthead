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
  alias Masthead.Storage
  alias Masthead.Themes.Theme

  # The canonical files that make up a theme directory.
  @theme_files ["manifest.json", "theme.css"] ++
                 Enum.map(~w(layout index post page blog not_found), &"templates/#{&1}.liquid")

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

  @doc """
  Delete an uploaded theme.

  Built-ins are protected. A theme that is still referenced by one or more
  sites can't be deleted (the `sites.theme_id` foreign key forbids it):
  rather than letting the DB raise an `Ecto.ConstraintError`, we look up
  the referencing sites first and return `{:error, {:in_use, sites}}`,
  where `sites` is a list of `{name, deleted_at}` tuples so the caller can
  tell the user exactly which site is holding the theme. The delete itself
  also carries a `foreign_key_constraint` as a safety net against the race
  where a site adopts the theme between the check and the delete.
  """
  def delete_theme(%Theme{source: "built_in"}), do: {:error, :built_in_protected}

  def delete_theme(%Theme{source: "uploaded"} = theme) do
    case sites_using_theme(theme.id) do
      [] ->
        theme
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.foreign_key_constraint(:id, name: "sites_theme_id_fkey")
        |> Repo.delete()

      sites ->
        {:error, {:in_use, sites}}
    end
  end

  # Sites referencing the theme, including soft-deleted ones — a soft-deleted
  # row still holds the foreign key, so it would block the delete too.
  defp sites_using_theme(theme_id) do
    Repo.all(
      from s in Masthead.Sites.Site,
        where: s.theme_id == ^theme_id,
        order_by: [asc: s.name],
        select: {s.name, s.deleted_at}
    )
  end

  # ---- admin ----

  @doc "Every theme, with owner preloaded. Admin overview."
  def list_all_themes do
    Repo.all(from t in Theme, order_by: ^theme_order(), preload: [:owner])
  end

  @doc """
  Reconstruct an uploaded theme's source files into an in-memory `.zip`.
  Returns `{:ok, filename, zip_binary}` or `{:error, reason}`. Built-in
  themes aren't downloadable (they live in the repo already).
  """
  def package_theme(%Theme{source: "built_in"}), do: {:error, :built_in_not_downloadable}

  def package_theme(%Theme{source: "uploaded", storage_path: path} = theme) do
    entries =
      Enum.reduce_while(@theme_files, [], fn rel, acc ->
        case Storage.read(Path.join(path, rel)) do
          {:ok, bin} -> {:cont, [{String.to_charlist(rel), bin} | acc]}
          {:error, reason} -> {:halt, {:error, {rel, reason}}}
        end
      end)

    with entries when is_list(entries) <- entries,
         filename = "#{theme.slug}-#{theme.version}.zip",
         {:ok, {_name, zip}} <-
           :zip.create(String.to_charlist(filename), Enum.reverse(entries), [:memory]) do
      {:ok, filename, zip}
    else
      {:error, _} = err -> err
    end
  end
end
