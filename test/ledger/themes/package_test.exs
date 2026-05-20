defmodule Ledger.Themes.PackageTest do
  use Ledger.DataCase

  alias Ledger.{Accounts, Themes}
  alias Ledger.Themes.Package

  setup do
    # Built-ins must exist for slug-reservation checks.
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "package-test-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    %{user: user}
  end

  test "installs a valid theme zip end-to-end", %{user: user} do
    slug = "valid#{System.unique_integer([:positive])}"
    zip_path = build_zip(valid_files(slug))

    assert {:ok, theme} = Package.install(zip_path, user.id)
    assert theme.slug == slug
    assert theme.source == "uploaded"
    assert theme.owner_id == user.id

    File.rm(zip_path)
  end

  test "rejects an archive that exceeds the size cap", %{user: user} do
    slug = "bloat#{System.unique_integer([:positive])}"
    # 26 MB of repeating chars compresses to a few KB but trips the 25 MB
    # uncompressed cap.
    junk = String.duplicate("x", 26 * 1024 * 1024)
    files = valid_files(slug) |> Map.put("theme.css", junk)
    zip_path = build_zip(files)

    assert {:error, reason} = Package.install(zip_path, user.id)

    assert match?({:archive_too_large, _, _}, reason) or
             match?({:uncompressed_too_large, _, _}, reason)

    File.rm(zip_path)
  end

  test "rejects a missing manifest", %{user: user} do
    slug = "nomanifest#{System.unique_integer([:positive])}"
    files = valid_files(slug) |> Map.delete("manifest.json")
    zip_path = build_zip(files)

    assert {:error, :manifest_missing} = Package.install(zip_path, user.id)
    File.rm(zip_path)
  end

  test "rejects a missing template", %{user: user} do
    slug = "notpl#{System.unique_integer([:positive])}"
    files = valid_files(slug) |> Map.delete("templates/post.liquid")
    zip_path = build_zip(files)

    assert {:error, {:template_missing, "post"}} = Package.install(zip_path, user.id)
    File.rm(zip_path)
  end

  test "rejects a slug reserved by a built-in", %{user: user} do
    zip_path = build_zip(valid_files("default"))

    assert {:error, {:slug_reserved, "default"}} = Package.install(zip_path, user.id)
    File.rm(zip_path)
  end

  test "rejects a syntactically invalid liquid template", %{user: user} do
    slug = "badtpl#{System.unique_integer([:positive])}"

    files =
      valid_files(slug)
      |> Map.put("templates/index.liquid", "{% if %}{% endfor %}")

    zip_path = build_zip(files)

    assert {:error, {:template_invalid, "index", _}} = Package.install(zip_path, user.id)
    File.rm(zip_path)
  end

  test "updates the existing theme in place when the version is newer", %{user: user} do
    slug = "upd#{System.unique_integer([:positive])}"

    z1 = build_zip(valid_files(slug) |> put_version("1.0.0"))
    assert {:ok, t1} = Package.install(z1, user.id)
    assert t1.version == "1.0.0"
    File.rm(z1)

    z2 = build_zip(valid_files(slug) |> put_version("1.1.0"))
    assert {:ok, t2} = Package.install(z2, user.id)
    File.rm(z2)

    assert t2.id == t1.id
    assert t2.version == "1.1.0"
  end

  test "rejects an upload whose version is not newer than the installed one", %{user: user} do
    slug = "same#{System.unique_integer([:positive])}"

    z1 = build_zip(valid_files(slug) |> put_version("2.0.0"))
    assert {:ok, _} = Package.install(z1, user.id)
    File.rm(z1)

    z_eq = build_zip(valid_files(slug) |> put_version("2.0.0"))

    assert {:error, {:version_not_newer, ^slug, "2.0.0", "2.0.0"}} =
             Package.install(z_eq, user.id)

    File.rm(z_eq)

    z_old = build_zip(valid_files(slug) |> put_version("1.9.0"))

    assert {:error, {:version_not_newer, ^slug, "2.0.0", "1.9.0"}} =
             Package.install(z_old, user.id)

    File.rm(z_old)
  end

  test "rejects updating when the uploaded version is not valid semver", %{user: user} do
    slug = "sem#{System.unique_integer([:positive])}"

    z1 = build_zip(valid_files(slug) |> put_version("1.0.0"))
    assert {:ok, _} = Package.install(z1, user.id)
    File.rm(z1)

    z2 = build_zip(valid_files(slug) |> put_version("banana"))
    assert {:error, {:version_unparseable, "banana"}} = Package.install(z2, user.id)
    File.rm(z2)
  end

  # ---- helpers ----

  defp put_version(files, version) do
    {:ok, m} = Jason.decode(files["manifest.json"])
    Map.put(files, "manifest.json", Jason.encode!(Map.put(m, "version", version)))
  end

  defp valid_files(slug) do
    %{
      "manifest.json" =>
        Jason.encode!(%{
          "name" => "Demo #{slug}",
          "slug" => slug,
          "version" => "1.0.0",
          "tokens" => []
        }),
      "templates/layout.liquid" => "<html><head></head><body>{{ content }}</body></html>",
      "templates/index.liquid" => "<h1>{{ site.name | escape }}</h1>",
      "templates/post.liquid" => "<article>{{ body_html }}</article>",
      "templates/page.liquid" => "<article>{{ body_html }}</article>",
      "templates/blog.liquid" => "<h1>{{ page.title | escape }}</h1>",
      "templates/not_found.liquid" => "<h1>Not found</h1>",
      "theme.css" => "body { background: white; }"
    }
  end

  defp build_zip(files) do
    tmp =
      Path.join(System.tmp_dir!(), "theme-test-#{System.unique_integer([:positive])}.zip")

    entries =
      Enum.map(files, fn {name, body} -> {String.to_charlist(name), body} end)

    {:ok, _} = :zip.create(String.to_charlist(tmp), entries)
    tmp
  end
end
