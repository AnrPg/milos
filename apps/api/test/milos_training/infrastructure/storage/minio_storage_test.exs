defmodule MilosTraining.Infrastructure.Storage.MinioStorageTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Infrastructure.Storage.MinioStorage

  test "bucket probe uses a body-bearing GET operation compatible with Hackney" do
    operation = MinioStorage.bucket_probe_operation("milos-avatars")

    assert operation.http_method == :get
    assert operation.bucket == "milos-avatars"
    assert operation.resource == "location"
  end

  test "avatar uploads only require headers browsers may set" do
    assert MinioStorage.avatar_upload_headers("image/jpeg") == [
             {"content-type", "image/jpeg"}
           ]
  end

  test "avatar metadata probe uses a bounded body-bearing GET" do
    operation = MinioStorage.avatar_probe_operation("milos-avatars", "avatars/user/avatar.jpg")

    assert operation.http_method == :get
    assert operation.bucket == "milos-avatars"
    assert operation.path == "avatars/user/avatar.jpg"
    assert operation.headers["range"] == "bytes=0-15"
  end

  test "avatar probe falls back to the public object URL when the private endpoint misses" do
    public_probe = fn ->
      {:ok,
       %{
         headers: [
           {"content-type", "image/jpeg"},
           {"content-range", "bytes 0-15/91390"}
         ],
         body: <<0xFF, 0xD8, 0xFF, 0xE0, "jpeg-rest">>
       }}
    end

    assert MinioStorage.avatar_probe_result(
             {:error, {:http_error, 404, %{}}},
             public_probe
           ) ==
             {:ok,
              %{
                headers: [
                  {"content-type", "image/jpeg"},
                  {"content-range", "bytes 0-15/91390"}
                ],
                body: <<0xFF, 0xD8, 0xFF, 0xE0, "jpeg-rest">>
              }}
  end

  test "avatar metadata accepts generic storage content type when bytes are a supported image" do
    headers = [
      {"content-type", "application/octet-stream"},
      {"content-range", "bytes 0-15/91713"}
    ]

    assert MinioStorage.avatar_metadata(headers, <<0xFF, 0xD8, 0xFF, 0xE0, "jpeg-rest">>) ==
             {:ok, "image/jpeg", 91_713}
  end

  test "avatar metadata detects additional supported image formats by bytes" do
    headers = [
      {"content-type", "application/octet-stream"},
      {"content-range", "bytes 0-15/1024"}
    ]

    assert MinioStorage.avatar_metadata(headers, <<"GIF89a", 0::80>>) == {:ok, "image/gif", 1024}
    assert MinioStorage.avatar_metadata(headers, <<"BM", 0::112>>) == {:ok, "image/bmp", 1024}

    assert MinioStorage.avatar_metadata(headers, <<0, 0, 0, 24, "ftypavif", 0::32>>) ==
             {:ok, "image/avif", 1024}
  end

  test "avatar metadata reports unsupported bytes separately from upload policy errors" do
    headers = [
      {"content-type", "image/jpeg"},
      {"content-range", "bytes 0-15/91713"}
    ]

    assert MinioStorage.avatar_metadata(headers, "not an image") ==
             {:error, :unsupported_avatar_type}
  end

  test "avatar metadata reports missing object size separately" do
    headers = [
      {"content-type", "image/jpeg"}
    ]

    assert MinioStorage.avatar_metadata(headers, <<0xFF, 0xD8, 0xFF, 0xE0, "jpeg-rest">>) ==
             {:error, :avatar_upload_metadata_missing}
  end
end
