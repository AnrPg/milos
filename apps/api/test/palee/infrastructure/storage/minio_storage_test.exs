defmodule Palee.Infrastructure.Storage.MinioStorageTest do
  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Storage.MinioStorage

  test "bucket probe uses a body-bearing GET operation compatible with Hackney" do
    operation = MinioStorage.bucket_probe_operation("milos-avatars")

    assert operation.http_method == :get
    assert operation.bucket == "milos-avatars"
    assert operation.resource == "location"
  end

  test "the public media bucket exposes only avatars and tenant logos (ADR-121)" do
    %{Statement: [%{Action: action, Resource: resource}]} =
      MinioStorage.public_read_policy("milos-avatars")

    assert action == ["s3:GetObject"]

    assert resource == [
             "arn:aws:s3:::milos-avatars/users/*/avatars/*",
             "arn:aws:s3:::milos-avatars/organizations/*/branding/logo/*",
             "arn:aws:s3:::milos-avatars/organizations/*/media/public/*"
           ]
  end

  test "only branding and public media objects have a public URL" do
    assert {:ok, media_url} =
             MinioStorage.public_object_url(
               :media_public,
               "organizations/o/media/public/box/x.jpg"
             )

    assert String.ends_with?(media_url, "/organizations/o/media/public/box/x.jpg")
    assert {:error, :not_public} = MinioStorage.public_object_url(:media_private, "x")

    assert {:ok, url} =
             MinioStorage.public_object_url(:branding, "organizations/o/branding/logo/x.png")

    assert String.ends_with?(url, "/organizations/o/branding/logo/x.png")
    assert {:error, :not_public} = MinioStorage.public_object_url(:documents, "x")
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

  test "list-objects responses are parsed without SweetXml, including pagination tokens" do
    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Name>milos-invoices</Name><IsTruncated>true</IsTruncated>
      <NextContinuationToken>tok&amp;en</NextContinuationToken>
      <Contents><Key>organizations/o/invoices/1/a&amp;b.pdf</Key><Size>42</Size></Contents>
      <Contents><Key>organizations/o/branding/logo.png</Key><Size>7</Size></Contents>
    </ListBucketResult>
    """

    assert {[
              %{key: "organizations/o/invoices/1/a&b.pdf", size: 42},
              %{key: "organizations/o/branding/logo.png", size: 7}
            ], "tok&en"} = MinioStorage.parse_list_objects_xml(body)

    assert {[], nil} =
             MinioStorage.parse_list_objects_xml(
               "<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>"
             )
  end
end
