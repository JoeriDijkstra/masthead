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

  Built-ins are read from `priv/themes/<slug>/` via the filesystem.
  Uploaded themes are read through `Ledger.Storage.read/1`, which routes
  to whichever adapter is configured (local disk or S3). This is the
  cold-cache path — once an entry lands in `:persistent_term`, the
  Renderer never touches storage again.
  """
  @spec read_from_source!(Theme.t()) :: entry()
  def read_from_source!(%Theme{source: "built_in", storage_path: path} = theme) do
    reader = priv_reader(path)
    read_with(theme, reader, asset_base_for(path))
  end

  def read_from_source!(%Theme{source: "uploaded", storage_path: path} = theme) do
    reader = storage_reader(path)
    read_with(theme, reader, asset_base_for(path))
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
    reader = priv_reader(storage_path)

    %{
      manifest: read_manifest!(reader),
      templates: read_templates!(reader),
      css: read_css!(reader),
      storage_path: storage_path
    }
  end

  # ---- internal ----

  # A reader is `(relative_path :: String.t()) -> {:ok, binary} | {:error, term}`.
  # We pass it around so file-reading code can be source-agnostic — priv
  # disk for built-ins, Storage adapter (local or S3) for uploads.

  defp priv_reader(storage_path) do
    root = Path.join([:code.priv_dir(:ledger) |> to_string(), storage_path])

    fn rel ->
      case File.read(Path.join(root, rel)) do
        {:ok, body} -> {:ok, body}
        {:error, :enoent} -> {:error, :not_found}
        {:error, _} = err -> err
      end
    end
  end

  defp storage_reader(storage_path) do
    fn rel -> Ledger.Storage.read(Path.join(storage_path, rel)) end
  end

  defp load_and_cache!(theme) do
    entry = read_from_source!(theme)
    :persistent_term.put({@cache_key, theme.id}, entry)
    entry
  end

  defp read_with(%Theme{} = theme, reader, asset_base) do
    %{
      theme: theme,
      manifest: read_manifest!(reader),
      templates: read_templates!(reader),
      css: read_css!(reader),
      asset_base: asset_base
    }
  end

  defp read_manifest!(reader) do
    case reader.("manifest.json") do
      {:ok, body} ->
        case Manifest.parse(body) do
          {:ok, manifest} -> manifest
          {:error, errors} -> raise "invalid manifest: #{Enum.join(errors, ", ")}"
        end

      {:error, reason} ->
        raise "could not read manifest.json: #{inspect(reason)}"
    end
  end

  defp read_templates!(reader) do
    Map.new(@template_names, fn name ->
      rel = "templates/" <> name <> ".liquid"

      case reader.(rel) do
        {:ok, body} ->
          case Sandbox.parse(body) do
            {:ok, template} -> {String.to_atom(name), template}
            {:error, err} -> raise "could not parse #{rel}: #{inspect(err)}"
          end

        {:error, reason} ->
          raise "missing template #{rel}: #{inspect(reason)}"
      end
    end)
  end

  defp read_css!(reader) do
    case reader.("theme.css") do
      {:ok, body} -> body
      {:error, reason} -> raise "missing theme.css: #{inspect(reason)}"
    end
  end

  defp asset_base_for(storage_path), do: "/uploads/" <> storage_path <> "/assets"
end
