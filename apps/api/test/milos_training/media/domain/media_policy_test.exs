defmodule MilosTraining.Media.Domain.MediaPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Media.Domain.MediaPolicy

  test "allocates keys per purpose under the owner's media folder" do
    assert {:ok,
            %{scope: :tenant, bucket: :media_public, relative_key: "media/public/box/abc.jpg"}} =
             MediaPolicy.allocate("box_photo", "image/jpeg", 1_000, "abc")

    assert {:ok, %{scope: :tenant, bucket: :media_private, relative_key: "media/posts/abc.webp"}} =
             MediaPolicy.allocate("post_photo", "image/webp", 1_000, "abc")

    assert {:ok, %{scope: :account, bucket: :media_private, relative_key: "media/body/abc.jpg"}} =
             MediaPolicy.allocate("body_photo", "image/jpeg", 1_000, "abc")
  end

  test "rejects unknown purposes, types and sizes" do
    assert {:error, :invalid_media_purpose} = MediaPolicy.allocate("avatar", "image/jpeg", 1, "a")
    assert {:error, :invalid_media_type} = MediaPolicy.allocate("box_photo", "image/png", 1, "a")

    assert {:error, :invalid_media_type} =
             MediaPolicy.allocate("box_photo", "image/svg+xml", 1, "a")

    assert {:error, :invalid_media_size} = MediaPolicy.allocate("box_photo", "image/jpeg", 0, "a")

    assert {:error, :media_too_large} =
             MediaPolicy.allocate("box_photo", "image/jpeg", MediaPolicy.max_bytes() + 1, "a")
  end

  test "the stored object must match what was requested" do
    inspected = %{content_type: "image/jpeg", width: 100, height: 100}
    assert :ok = MediaPolicy.validate_stored("image/jpeg", inspected, 10)

    assert {:error, :media_type_mismatch} =
             MediaPolicy.validate_stored("image/webp", inspected, 10)

    assert {:error, :media_upload_missing} =
             MediaPolicy.validate_stored("image/jpeg", inspected, 0)

    assert {:error, :media_too_large} =
             MediaPolicy.validate_stored("image/jpeg", %{inspected | width: 5_000}, 10)
  end

  test "unattached uploads become orphans after a day" do
    now = ~U[2026-10-18 12:00:00Z]
    assert MediaPolicy.orphan?(%{attached_at: nil, inserted_at: ~U[2026-10-17 11:59:59Z]}, now)
    refute MediaPolicy.orphan?(%{attached_at: nil, inserted_at: ~U[2026-10-18 00:00:00Z]}, now)
    refute MediaPolicy.orphan?(%{attached_at: now, inserted_at: ~U[2026-10-01 00:00:00Z]}, now)
  end
end
