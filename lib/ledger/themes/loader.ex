defmodule Ledger.Themes.Loader do
  @moduledoc """
  Loads a theme's source files (manifest, templates, CSS) into memory and
  caches the parsed result in `:persistent_term`.

  Two source roots are supported:

    * `built_in` themes live in `priv/themes/<slug>/`
    * `uploaded` themes live under `Ledger.Storage` at the theme's
      `storage_path` (handled in Phase 4 once uploads land)

  The loader is the only file-reading code path for themes — once it has
  cached a theme, `Renderer` works entirely off the in-memory entry.
  """

  alias Ledger.Themes.{Manifest, Sandbox, Theme}

  @cache_key __MODULE__
  @template_names ~w(layout index post page blog not_found)

  @typedoc "Cached entry shape stored in :persistent_term."
  @type entry :: %{
          theme: Theme.t(),
          manifest: Manifest.t(),
          css: String.t(),
          templates: %{atom() => Solid.Template.t()},
          asset_base: String.t()
        }

  @doc """
  Return the cached entry for a theme, loading and caching it on cache
  miss. Raises if the theme's source files are missing or fail to parse —
  this is a "should not happen at runtime" situation that means seeding /
  upload validation didn't do its job.
  """
  @spec fetch!(Theme.t()) :: entry()
  def fetch!(%Theme{id: id} = theme) do
    case :persistent_term.get({@cache_key, id}, :miss) do
      :miss -> load_and_cache!(theme)
      entry -> entry
    end
  end

  @doc "Drop the cache entry for a theme. Called after update/delete."
  @spec invalidate(integer()) :: :ok
  def invalidate(theme_id) when is_integer(theme_id) do
    _ = :persistent_term.erase({@cache_key, theme_id})
    :ok
  end

  @doc """
  Read a theme from its source root without consulting the cache.
  Used by the seed task to compute manifest+version before deciding
  whether to upsert, and by `fetch!/1` on cache miss.
  """
  @spec read_from_source!(Theme.t()) :: entry()
  def read_from_source!(%Theme{source: "built_in", storage_path: path} = theme) do
    root = Path.join([:code.priv_dir(:ledger) |> to_string(), path])
    read_root!(theme, root, asset_base_for_built_in(path))
  end

  def read_from_source!(%Theme{source: "uploaded", storage_path: path} = theme) do
    root = Path.join(Ledger.Storage.Local.root_path(), path)
    read_root!(theme, root, asset_base_for_uploaded(path))
  end

  @doc """
  Read a theme's source files given a slug under `priv/themes/`. Used by
  the seed task before a `Theme` row exists.
  """
  @spec read_built_in_source!(String.t()) :: %{
          manifest: Manifest.t(),
          css: String.t(),
          templates: %{atom() => Solid.Template.t()},
          storage_path: String.t()
        }
  def read_built_in_source!(slug) when is_binary(slug) do
    storage_path = Path.join("themes", slug)
    root = Path.join([:code.priv_dir(:ledger) |> to_string(), storage_path])

    manifest = read_manifest!(root)
    templates = read_templates!(root)
    css = read_css!(root)

    %{
      manifest: manifest,
      templates: templates,
      css: css,
      storage_path: storage_path
    }
  end

  # ---- internal ----

  defp load_and_cache!(theme) do
    entry = read_from_source!(theme)
    :persistent_term.put({@cache_key, theme.id}, entry)
    entry
  end

  defp read_root!(%Theme{} = theme, root, asset_base) do
    manifest = read_manifest!(root)
    templates = read_templates!(root)
    css = read_css!(root)

    %{
      theme: theme,
      manifest: manifest,
      templates: templates,
      css: css,
      asset_base: asset_base
    }
  end

  defp read_manifest!(root) do
    path = Path.join(root, "manifest.json")

    case File.read(path) do
      {:ok, body} ->
        case Manifest.parse(body) do
          {:ok, manifest} -> manifest
          {:error, errors} -> raise "invalid manifest at #{path}: #{Enum.join(errors, ", ")}"
        end

      {:error, reason} ->
        raise "could not read manifest at #{path}: #{:file.format_error(reason)}"
    end
  end

  defp read_templates!(root) do
    Map.new(@template_names, fn name ->
      path = Path.join([root, "templates", name <> ".liquid"])

      case File.read(path) do
        {:ok, body} ->
          case Sandbox.parse(body) do
            {:ok, template} -> {String.to_atom(name), template}
            {:error, err} -> raise "could not parse #{path}: #{inspect(err)}"
          end

        {:error, reason} ->
          raise "missing template #{path}: #{:file.format_error(reason)}"
      end
    end)
  end

  defp read_css!(root) do
    path = Path.join(root, "theme.css")

    case File.read(path) do
      {:ok, body} -> body
      {:error, reason} -> raise "missing theme.css at #{path}: #{:file.format_error(reason)}"
    end
  end

  # Built-in assets are served from priv via the same `/uploads/themes/...`
  # mount used for uploaded themes. We'll wire the priv mount in Phase 4
  # alongside the upload pipeline. For now, return the placeholder path —
  # nothing references it in the v1 built-in templates.
  defp asset_base_for_built_in(storage_path), do: "/uploads/" <> storage_path <> "/assets"

  defp asset_base_for_uploaded(storage_path), do: "/uploads/" <> storage_path <> "/assets"
end
