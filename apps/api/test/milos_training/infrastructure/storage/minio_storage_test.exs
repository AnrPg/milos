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
    assert operation.headers["range"] == "bytes=0-0"
  end

end
