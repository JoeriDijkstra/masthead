defmodule Masthead.UploadsTest do
  use Masthead.DataCase

  alias Masthead.{Accounts, Sites, Uploads}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "up-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "up#{System.unique_integer([:positive])}",
        "name" => "Up Test",
        "owner_id" => user.id
      })

    %{site: site}
  end

  defp store(site, filename, content_type) do
    tmp = Path.join(System.tmp_dir!(), "ut-#{System.unique_integer([:positive])}")
    File.write!(tmp, "bytes")

    result =
      Uploads.store_image(site, %{filename: filename, content_type: content_type, path: tmp})

    File.rm(tmp)
    result
  end

  test "accepts PDF uploads", %{site: site} do
    assert {:ok, upload} = store(site, "doc.pdf", "application/pdf")
    assert upload.content_type == "application/pdf"
    refute Uploads.image?(upload)
  end

  test "accepts .ico uploads", %{site: site} do
    assert {:ok, upload} = store(site, "favicon.ico", "image/x-icon")
    assert Uploads.image?(upload)
  end

  test "accepts .ico by extension even when the browser sends a blank MIME", %{site: site} do
    assert {:ok, _upload} = store(site, "favicon.ico", "")
  end

  test "still rejects unsupported types", %{site: site} do
    assert {:error, :unsupported_type} = store(site, "evil.exe", "application/x-msdownload")
  end

  test "image?/1 classifies common types" do
    assert Uploads.image?("image/png")
    assert Uploads.image?("image/svg+xml")
    refute Uploads.image?("application/pdf")
    refute Uploads.image?(nil)
  end
end
