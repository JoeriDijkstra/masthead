defmodule Ledger.Storage do
  @moduledoc """
  Thin storage adapter. Local-disk only for MVP.

  Behind this module we keep the call sites consistent so an S3/R2 adapter
  can be swapped in without touching the rest of the app.
  """

  @doc """
  Stores binary content under `priv/uploads/<site_slug>/<key>` and returns
  the storage path (relative to the storage root) on success.

  `key` should already be unique (caller generates it, typically as
  `<random>-<basename>`).
  """
  def put(site_slug, key, binary) when is_binary(binary) do
    rel = Path.join(site_slug, key)
    abs = absolute(rel)
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, binary)
    {:ok, rel}
  end

  def stream_into(site_slug, key, source_path) do
    rel = Path.join(site_slug, key)
    abs = absolute(rel)
    File.mkdir_p!(Path.dirname(abs))
    File.cp!(source_path, abs)
    {:ok, rel}
  end

  def delete(rel_path) when is_binary(rel_path) do
    File.rm(absolute(rel_path))
  end

  @doc """
  Moves a file from `old_rel` to `new_rel` (both relative to the storage root).
  Returns `{:ok, new_rel}` on success or `{:error, reason}` if the target
  already exists or rename fails.
  """
  def rename(old_rel, new_rel) when is_binary(old_rel) and is_binary(new_rel) do
    old_abs = absolute(old_rel)
    new_abs = absolute(new_rel)

    cond do
      not File.exists?(old_abs) ->
        {:error, :not_found}

      File.exists?(new_abs) ->
        {:error, :already_exists}

      true ->
        File.mkdir_p!(Path.dirname(new_abs))

        case File.rename(old_abs, new_abs) do
          :ok -> {:ok, new_rel}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def absolute(rel_path) do
    Path.join(root_path(), rel_path)
  end

  def url(rel_path), do: "/uploads/" <> rel_path

  @doc "Storage root on disk. Public so Plug.Static can call into it."
  def root_path do
    Application.get_env(:ledger, __MODULE__)[:root] ||
      Path.join(:code.priv_dir(:ledger) |> to_string(), "uploads")
  end
end
