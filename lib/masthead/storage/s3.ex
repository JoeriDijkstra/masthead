defmodule Masthead.Storage.S3 do
  @moduledoc """
  S3-compatible storage adapter. Tested against Fly's Tigris service but
  works with any S3-compatible endpoint (AWS S3, Cloudflare R2, MinIO).

  Reads config from environment variables:

    * `AWS_ACCESS_KEY_ID`
    * `AWS_SECRET_ACCESS_KEY`
    * `AWS_ENDPOINT_URL_S3`   — e.g. `https://fly.storage.tigris.dev`
    * `AWS_REGION`            — `auto` is fine for Tigris
    * `BUCKET_NAME`           — the bucket to write into

  Objects are uploaded with `public-read` ACL so they can be served
  directly to browsers without pre-signed URLs. The bucket also needs
  to be configured for public read access in the Tigris dashboard.
  """
  @behaviour Masthead.Storage.Adapter

  alias ExAws.S3

  @impl true
  def put(site_slug, key, binary) when is_binary(binary) do
    rel = Path.join(site_slug, key)

    bucket()
    |> S3.put_object(rel, binary, put_options(rel))
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, rel}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stream_into(site_slug, key, source_path) do
    put(site_slug, key, File.read!(source_path))
  end

  @impl true
  def delete(rel_path) do
    bucket()
    |> S3.delete_object(rel_path)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def rename(old_rel, new_rel) do
    cond do
      not exists?(old_rel) ->
        {:error, :not_found}

      exists?(new_rel) ->
        {:error, :already_exists}

      true ->
        with {:ok, _} <- copy(old_rel, new_rel),
             :ok <- delete(old_rel) do
          {:ok, new_rel}
        end
    end
  end

  @impl true
  def read(rel_path) do
    bucket()
    |> S3.get_object(rel_path)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def url(rel_path) do
    # Virtual-hosted style URL: <scheme>://<bucket>.<host>/<key>.
    # Tigris (and most S3-compatible services) serve public objects via
    # the bucket-as-subdomain form. Path-style works for authenticated
    # API calls but not for anonymous browser access on Tigris.
    uri = URI.parse(endpoint())
    "#{uri.scheme}://#{bucket()}.#{uri.host}/#{rel_path}"
  end

  # ---- helpers ----

  defp copy(src, dest) do
    bucket()
    |> S3.put_object_copy(dest, bucket(), src, acl: :public_read)
    |> ExAws.request()
  end

  defp exists?(rel_path) do
    bucket()
    |> S3.head_object(rel_path)
    |> ExAws.request()
    |> case do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp put_options(rel_path) do
    [
      acl: :public_read,
      content_type: content_type_for(rel_path),
      cache_control: "public, max-age=31536000, immutable"
    ]
  end

  defp content_type_for(path) do
    case Path.extname(path) |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end

  defp bucket, do: System.fetch_env!("BUCKET_NAME")

  defp endpoint do
    System.get_env("AWS_ENDPOINT_URL_S3", "https://fly.storage.tigris.dev")
    |> String.trim_trailing("/")
  end
end
