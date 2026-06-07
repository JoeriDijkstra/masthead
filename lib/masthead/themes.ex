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

  Built-ins are protected. A theme still referenced by a *live* site can't
  be deleted (the `sites.theme_id` foreign key forbids it): rather than
  letting the DB raise an `Ecto.ConstraintError`, we look those sites up
  first and return `{:error, {:in_use, names}}` so the caller can name
  them. A *disabled* site still counts — its owner can re-enable it.

  Soft-deleted sites are different: they render nothing, but their row
  still holds the foreign key, so they would otherwise pin the theme
  forever. We detach them onto the built-in `default` theme before
  deleting, so they no longer block (they'd come back on `default` if ever
  restored). The delete also carries a `foreign_key_constraint` as a
  safety net against a site adopting the theme mid-operation.
  """
  def delete_theme(%Theme{source: "built_in"}), do: {:error, :built_in_protected}

  def delete_theme(%Theme{source: "uploaded"} = theme) do
    case live_sites_using_theme(theme.id) do
      [] ->
        detach_deleted_sites(theme.id)

        theme
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.foreign_key_constraint(:id, name: "sites_theme_id_fkey")
        |> Repo.delete()

      names ->
        {:error, {:in_use, names}}
    end
  end

  # Names of non-deleted sites referencing the theme. Only `deleted_at`
  # excludes a site; a disabled site can be re-enabled, so it still blocks.
  defp live_sites_using_theme(theme_id) do
    Repo.all(
      from s in Masthead.Sites.Site,
        where: s.theme_id == ^theme_id and is_nil(s.deleted_at),
        order_by: [asc: s.name],
        select: s.name
    )
  end

  # Re-point any soft-deleted sites off the doomed theme and onto `default`,
  # so the foreign key no longer blocks its deletion.
  defp detach_deleted_sites(theme_id) do
    case get_built_in_by_slug("default") do
      %Theme{id: default_id} ->
        Repo.update_all(
          from(s in Masthead.Sites.Site,
            where: s.theme_id == ^theme_id and not is_nil(s.deleted_at)
          ),
          set: [theme_id: default_id]
        )

        :ok

      nil ->
        :ok
    end
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
