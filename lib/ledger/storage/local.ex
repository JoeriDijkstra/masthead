defmodule Ledger.Storage.Local do
  @moduledoc """
  Local-disk storage adapter. Files live under `priv/uploads/` (overridable
  via `config :ledger, Ledger.Storage, root: "/some/path"`) and are served
  by `Plug.Static` mounted at `/uploads`.
  """
  @behaviour Ledger.Storage.Adapter

  @impl true
  def put(site_slug, key, binary) when is_binary(binary) do
    rel = Path.join(site_slug, key)
    abs = absolute(rel)
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, binary)
    {:ok, rel}
  end

  @impl true
  def stream_into(site_slug, key, source_path) do
    rel = Path.join(site_slug, key)
    abs = absolute(rel)
    File.mkdir_p!(Path.dirname(abs))
    File.cp!(source_path, abs)
    {:ok, rel}
  end

  @impl true
  def delete(rel_path) when is_binary(rel_path) do
    case File.rm(absolute(rel_path)) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
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

  @impl true
  def url(rel_path), do: "/uploads/" <> rel_path

  def absolute(rel_path), do: Path.join(root_path(), rel_path)

  @doc "Storage root on disk. Public so Plug.Static can call into it."
  def root_path do
    Application.get_env(:ledger, Ledger.Storage)[:root] ||
      Path.join(:code.priv_dir(:ledger) |> to_string(), "uploads")
  end
end
