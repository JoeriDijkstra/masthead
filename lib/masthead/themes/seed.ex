defmodule Masthead.Themes.Seed do
  @moduledoc """
  Idempotent seeder for built-in themes.

  On every application boot we walk `priv/themes/*/` and upsert one DB row
  per directory. The row is the index entry; the actual template/CSS bytes
  stay on disk and are read on demand by `Masthead.Themes.Loader`.

  Bumping the `version` field in a theme's `manifest.json` will trigger an
  update on the next boot — older rows are not deleted automatically, so
  rolling back a deploy is non-destructive.
  """

  require Logger
  alias Masthead.Themes
  alias Masthead.Themes.Loader

  @doc """
  Walk `priv/themes/` and upsert every theme found. Returns
  `:ok | {:error, [reason, ...]}`.
  """
  def run do
    case discover() do
      {:ok, slugs} ->
        Enum.each(slugs, &upsert_one!/1)
        :ok

      {:error, reason} ->
        Logger.warning("theme seed: no priv/themes/ directory (#{inspect(reason)})")
        :ok
    end
  end

  @doc false
  def discover do
    root = Path.join(:code.priv_dir(:masthead) |> to_string(), "themes")

    case File.ls(root) do
      {:ok, entries} ->
        slugs =
          entries
          |> Enum.filter(fn name -> File.dir?(Path.join(root, name)) end)
          |> Enum.sort()

        {:ok, slugs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_one!(slug) do
    source = Loader.read_built_in_source!(slug)
    manifest = source.manifest

    attrs = %{
      slug: manifest.slug,
      name: manifest.name,
      description: manifest.description || "",
      version: manifest.version,
      storage_path: source.storage_path,
      manifest:
        Map.from_struct(manifest) |> Map.update!(:tokens, &Enum.map(&1, fn t -> Map.new(t) end))
    }

    case Themes.upsert_built_in(attrs) do
      {:ok, theme} ->
        # If we just changed a built-in's row, drop any cached parse so the
        # next render picks up the new templates/css.
        Loader.invalidate(theme.id)
        :ok

      {:error, changeset} ->
        raise "failed to upsert built-in theme #{slug}: #{inspect(changeset.errors)}"
    end
  end
end
