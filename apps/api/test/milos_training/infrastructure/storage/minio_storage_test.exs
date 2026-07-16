defmodule MilosTraining.Infrastructure.Storage.MinioStorageTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Infrastructure.Storage.MinioStorage

  test "bucket probe uses a body-bearing GET operation compatible with Hackney" do
    operation = MinioStorage.bucket_probe_operation("milos-avatars")

    assert operation.http_method == :get
    assert operation.bucket == "milos-avatars"
    assert operation.resource == "location"
  end
end
