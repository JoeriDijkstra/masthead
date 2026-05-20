defmodule Ledger.Storage do
  @moduledoc """
  Thin storage adapter. Delegates to whichever module is configured under
  `config :ledger, Ledger.Storage, adapter: <Module>`:

    * `Ledger.Storage.Local` (default — files under `priv/uploads/`)
    * `Ledger.Storage.S3`    (S3-compatible: Tigris, R2, AWS)

  Call sites are stable across adapters; switch storage backends by
  flipping the config, not by touching `Ledger.Uploads`.
  """

  def put(site_slug, key, binary), do: adapter().put(site_slug, key, binary)

  def stream_into(site_slug, key, source_path),
    do: adapter().stream_into(site_slug, key, source_path)

  def delete(rel), do: adapter().delete(rel)
  def rename(old_rel, new_rel), do: adapter().rename(old_rel, new_rel)
  def url(rel), do: adapter().url(rel)

  @doc """
  Local-disk-only helper kept on the top-level module so the Endpoint's
  `Plug.Static` can resolve it at startup regardless of which adapter is
  active. Returns the local storage root even when the S3 adapter is in
  use — the directory may be empty in that case, which is fine; Plug.Static
  just returns 404s for missing files.
  """
  def root_path, do: Ledger.Storage.Local.root_path()

  defp adapter do
    Application.get_env(:ledger, __MODULE__)[:adapter] || Ledger.Storage.Local
  end
end
