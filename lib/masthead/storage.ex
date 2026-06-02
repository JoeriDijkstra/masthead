defmodule Masthead.Storage do
  @moduledoc """
  Thin storage adapter. Delegates to whichever module is configured under
  `config :masthead, Masthead.Storage, adapter: <Module>`:

    * `Masthead.Storage.Local` (default — files under `priv/uploads/`)
    * `Masthead.Storage.S3`    (S3-compatible: Tigris, R2, AWS)

  Call sites are stable across adapters; switch storage backends by
  flipping the config, not by touching `Masthead.Uploads`.
  """

  def put(site_slug, key, binary), do: adapter().put(site_slug, key, binary)

  def stream_into(site_slug, key, source_path),
    do: adapter().stream_into(site_slug, key, source_path)

  def delete(rel), do: adapter().delete(rel)
  def rename(old_rel, new_rel), do: adapter().rename(old_rel, new_rel)
  def url(rel), do: adapter().url(rel)

  @doc """
  Read the bytes at `rel_path` from the configured adapter. Used by the
  theme renderer to repopulate its cache on a cold miss.
  """
  def read(rel_path), do: adapter().read(rel_path)

  @doc """
  Local-disk-only helper kept on the top-level module so the Endpoint's
  `Plug.Static` can resolve it at startup regardless of which adapter is
  active. Returns the local storage root even when the S3 adapter is in
  use — the directory may be empty in that case, which is fine; Plug.Static
  just returns 404s for missing files.
  """
  def root_path, do: Masthead.Storage.Local.root_path()

  defp adapter do
    Application.get_env(:masthead, __MODULE__)[:adapter] || Masthead.Storage.Local
  end
end
