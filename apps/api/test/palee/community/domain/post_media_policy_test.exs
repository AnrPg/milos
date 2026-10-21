defmodule Palee.Community.Domain.PostMediaPolicyTest do
  @moduledoc "ADR-157: what media a post may carry and who sees it before they are ready."

  use ExUnit.Case, async: true

  alias Palee.Community.Domain.PostMediaPolicy

  test "up to ten photos, or one video, never both" do
    assert :ok = PostMediaPolicy.compose([])
    assert :ok = PostMediaPolicy.compose(List.duplicate("image", 10))
    assert :ok = PostMediaPolicy.compose(["video"])
    assert {:error, :too_many_media} = PostMediaPolicy.compose(List.duplicate("image", 11))
    assert {:error, :too_many_media} = PostMediaPolicy.compose(["video", "video"])
    assert {:error, :mixed_media} = PostMediaPolicy.compose(["image", "video"])
    assert {:error, :invalid_media} = PostMediaPolicy.compose(["audio"])
  end

  test "a post is ready once every media item is, failed when one could not be processed" do
    assert PostMediaPolicy.status([]) == "ready"
    assert PostMediaPolicy.status(["ready", "ready"]) == "ready"
    assert PostMediaPolicy.status(["ready", "processing"]) == "processing"
    assert PostMediaPolicy.status(["pending"]) == "processing"
    assert PostMediaPolicy.status(["ready", "rejected", "processing"]) == "failed"
    assert PostMediaPolicy.status(["missing"]) == "failed"
  end

  test "only the author sees a post whose media are not ready" do
    author = Ecto.UUID.generate()
    other = Ecto.UUID.generate()

    for status <- ["processing", "failed"] do
      post = %{author_id: author, media_status: status}
      assert PostMediaPolicy.visible?(post, author)
      refute PostMediaPolicy.visible?(post, other)
      refute PostMediaPolicy.visible?(post, nil)
    end

    assert PostMediaPolicy.visible?(%{author_id: author, media_status: "ready"}, other)
    assert PostMediaPolicy.visible?(%{author_id: author, media_status: "ready"}, nil)
  end
end
