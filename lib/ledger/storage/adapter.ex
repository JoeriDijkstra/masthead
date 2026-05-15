defmodule Ledger.Storage.Adapter do
  @moduledoc """
  Behaviour for storage adapters. Two implementations ship with Ledger:

    * `Ledger.Storage.Local` — files on disk, served via `Plug.Static`
    * `Ledger.Storage.S3`    — S3-compatible storage (Tigris, R2, AWS, ...)

  Pick one by setting `config :ledger, Ledger.Storage, adapter: <Module>`.
  """

  @doc """
  Store a binary at the given location. Returns the storage path (relative
  to wherever the adapter considers its root).
  """
  @callback put(site_slug :: String.t(), key :: String.t(), binary()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Same as `put/3` but reads the bytes from a path on the local fs."
  @callback stream_into(site_slug :: String.t(), key :: String.t(), source_path :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback delete(rel_path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Rename / move an object. Must refuse with `{:error, :already_exists}` if
  the target already exists, and `{:error, :not_found}` if the source
  doesn't.
  """
  @callback rename(old_rel :: String.t(), new_rel :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Public URL for the given storage path. Local adapter returns a
  relative `/uploads/…` URL served by Phoenix. S3 adapter returns the
  full external URL (e.g. `https://fly.storage.tigris.dev/<bucket>/<key>`).
  """
  @callback url(rel_path :: String.t()) :: String.t()

  @doc """
  Read the bytes at `rel_path`. Returns `{:error, :not_found}` if the
  file does not exist.
  """
  @callback read(rel_path :: String.t()) :: {:ok, binary()} | {:error, term()}
end
