defmodule Masthead.Uploads do
  import Ecto.Query
  alias Masthead.Repo
  alias Masthead.Uploads.Upload
  alias Masthead.Storage

  @allowed_upload_types ~w(
    image/png image/jpeg image/gif image/webp image/svg+xml
    image/x-icon image/vnd.microsoft.icon application/pdf
  )

  # Browsers send inconsistent (or empty) MIME types for .ico, so we also
  # accept by extension as a fallback and infer the MIME from it.
  @ext_content_types %{
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".svg" => "image/svg+xml",
    ".ico" => "image/x-icon",
    ".pdf" => "application/pdf"
  }
  @allowed_extensions Map.keys(@ext_content_types)

  # Content types that render directly in an <img>. Everything else (PDF)
  # gets a filename/extension placeholder in the UI instead of a broken
  # thumbnail. (.ico renders fine in browsers, so it counts as an image.)
  @image_content_types ~w(
    image/png image/jpeg image/gif image/webp image/svg+xml
    image/x-icon image/vnd.microsoft.icon
  )

  @doc "True when the upload renders directly in an `<img>` tag."
  def image?(%Upload{content_type: content_type}), do: image?(content_type)
  def image?(content_type) when is_binary(content_type), do: content_type in @image_content_types
  def image?(_), do: false

  def list_uploads(site_id) do
    Repo.all(from u in Upload, where: u.site_id == ^site_id, order_by: [desc: u.inserted_at])
  end

  def get_upload!(site_id, id) do
    Repo.one!(from u in Upload, where: u.site_id == ^site_id and u.id == ^id)
  end

  @doc """
  Site-scoped fetch that returns `nil` instead of raising when the upload
  is missing. Used by the theme renderer to resolve `file` token ids,
  where a dangling reference (deleted upload) must degrade to "no file"
  rather than crash the public page.
  """
  def get_upload(site_id, id) do
    Repo.one(from u in Upload, where: u.site_id == ^site_id and u.id == ^id)
  end

  @doc """
  Stores an upload tied to a site. `source` must be a path to a file on disk
  (which is what Phoenix.LiveView `consume_uploaded_entries` and
  Plug.Upload both give you).
  """
  def store_image(site, %{filename: filename, content_type: content_type, path: path}) do
    content_type = normalize_content_type(content_type, filename)

    cond do
      not allowed_upload?(content_type, filename) ->
        {:error, :unsupported_type}

      true ->
        ext = Path.extname(filename) |> String.downcase()
        key = "#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}#{ext}"

        # Stat the source file before handing it to the storage adapter so we
        # don't need a "read back the stored object" call (which the S3
        # adapter would have to make over the network).
        %{size: byte_size} = File.stat!(path)

        case Storage.stream_into(site.slug, key, path) do
          {:ok, rel} ->
            %Upload{}
            |> Upload.changeset(%{
              site_id: site.id,
              filename: filename,
              content_type: content_type,
              byte_size: byte_size,
              path: rel
            })
            |> Repo.insert()

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def delete_upload(%Upload{} = upload) do
    _ = Storage.delete(upload.path)
    Repo.delete(upload)
  end

  def url(%Upload{path: path}), do: Storage.url(path)

  defp allowed_upload?(content_type, filename) do
    content_type in @allowed_upload_types or
      String.downcase(Path.extname(filename)) in @allowed_extensions
  end

  # When the browser omits or genericises the MIME (common for .ico), infer
  # it from the extension so a known file type still stores with a real
  # content type rather than a blank one.
  defp normalize_content_type(content_type, filename)
       when content_type in [nil, "", "application/octet-stream"] do
    ext = String.downcase(Path.extname(filename))
    Map.get(@ext_content_types, ext) || content_type
  end

  defp normalize_content_type(content_type, _filename), do: content_type

  @doc """
  Renames the file on disk to `new_filename` (which should include the
  extension) and updates both `filename` and `path` on the DB row so the
  public URL reflects the change. The new path lives in the same site
  directory as the old one.

  Returns:

    * `{:ok, upload}` on success
    * `{:error, :empty}` if the filename is blank
    * `{:error, :invalid_chars}` if it contains path separators
    * `{:error, :already_exists}` if a sibling file with that name is taken
    * `{:error, changeset}` if the DB update fails
  """
  def rename(%Upload{} = upload, new_filename) when is_binary(new_filename) do
    new_filename =
      new_filename
      |> String.trim()
      |> preserve_extension(upload.path)

    with :ok <- validate_filename(new_filename),
         new_path = Path.join(Path.dirname(upload.path), new_filename),
         true <- new_path != upload.path or {:error, :unchanged},
         {:ok, ^new_path} <- Storage.rename(upload.path, new_path) do
      upload
      |> Upload.changeset(%{filename: new_filename, path: new_path})
      |> Repo.update()
      |> case do
        {:ok, _} = ok ->
          ok

        {:error, _} = err ->
          # roll back the disk move so DB and disk don't diverge
          Storage.rename(new_path, upload.path)
          err
      end
    end
  end

  defp validate_filename(""), do: {:error, :empty}

  defp validate_filename(name) when is_binary(name) do
    cond do
      String.contains?(name, ["/", "\\"]) -> {:error, :invalid_chars}
      String.starts_with?(name, ".") -> {:error, :invalid_chars}
      String.length(name) > 200 -> {:error, :invalid_chars}
      true -> :ok
    end
  end

  # If the user dropped the extension (or the new name has none), re-attach
  # the original extension. Files served without an extension can confuse
  # browsers, break content-type sniffing, and silently break Markdown
  # `![](url)` snippets — better to keep the type intact than honor a
  # literal rename.
  defp preserve_extension(new_name, original_path) do
    case Path.extname(new_name) do
      ext when ext in ["", "."] ->
        original_ext = Path.extname(original_path)
        new_name |> String.trim_trailing(".") |> Kernel.<>(original_ext)

      _ext ->
        new_name
    end
  end
end
