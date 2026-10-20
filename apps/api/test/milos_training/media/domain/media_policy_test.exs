defmodule MilosTraining.Media.Domain.MediaPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Media.Domain.MediaPolicy

  test "allocates keys per purpose under the owner's media folder" do
    assert {:ok,
            %{scope: :tenant, bucket: :media_public, relative_key: "media/public/box/abc.jpg"}} =
             MediaPolicy.allocate("box_photo", "image/jpeg", 1_000, "abc")

    assert {:ok,
            %{
              scope: :account,
              bucket: :media_private,
              relative_key: "media/posts/abc/original.heic"
            }} =
             MediaPolicy.allocate("post_photo", "image/heic", 1_000, "abc")

    assert {:ok, %{scope: :account, relative_key: "media/posts/abc/original.mov"}} =
             MediaPolicy.allocate("post_video", "video/quicktime", 1_000, "abc")

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

  test "post uploads accept what a phone produces, within each kind's cap" do
    assert {:error, :invalid_media_type} = MediaPolicy.allocate("post_photo", "video/mp4", 1, "a")

    assert {:error, :invalid_media_type} =
             MediaPolicy.allocate("post_video", "image/jpeg", 1, "a")

    assert {:error, :invalid_media_type} = MediaPolicy.allocate("post_photo", "image/gif", 1, "a")

    assert {:error, :media_too_large} =
             MediaPolicy.allocate(
               "post_photo",
               "image/png",
               MediaPolicy.max_bytes("post_photo") + 1,
               "a"
             )

    assert {:ok, _video} =
             MediaPolicy.allocate(
               "post_video",
               "video/mp4",
               MediaPolicy.max_bytes("post_photo") + 1,
               "a"
             )

    assert MediaPolicy.kind("post_video") == "video"
    assert MediaPolicy.processing("post_photo") == :server
    assert MediaPolicy.processing("box_photo") == :inspect
  end

  test "the stored bytes of a post upload decide its type" do
    assert {:ok, "image/heic"} = MediaPolicy.validate_upload("post_photo", "image/heic", 10)

    assert {:error, :invalid_media_type} =
             MediaPolicy.validate_upload("post_photo", "video/mp4", 10)

    assert {:error, :media_upload_missing} =
             MediaPolicy.validate_upload("post_photo", "image/png", 0)

    assert {:error, :media_too_large} =
             MediaPolicy.validate_upload(
               "post_photo",
               "image/png",
               MediaPolicy.max_bytes("post_photo") + 1
             )
  end

  test "images too large to decode and videos over two minutes are rejected" do
    assert :ok = MediaPolicy.validate_image(%{width: 4_032, height: 3_024})

    assert {:error, :media_too_large} =
             MediaPolicy.validate_image(%{width: 10_000, height: 10_000})

    assert {:error, :media_unreadable} = MediaPolicy.validate_image(%{width: 0, height: 10})

    video = %{duration_ms: 119_000, width: 1_920, height: 1_080, has_video: true}
    assert :ok = MediaPolicy.validate_video(video)
    assert :ok = MediaPolicy.validate_video(%{video | duration_ms: 120_400})
    assert {:error, :video_too_long} = MediaPolicy.validate_video(%{video | duration_ms: 121_000})
    assert {:error, :media_unreadable} = MediaPolicy.validate_video(%{video | has_video: false})
    assert {:error, :media_unreadable} = MediaPolicy.validate_video(%{video | duration_ms: 0})
  end

  test "renditions sit next to the original" do
    assert MediaPolicy.variant_key("users/u/media/posts/m/original.heic", "feed", "webp") ==
             "users/u/media/posts/m/feed.webp"
  end

  test "the quota caps open uploads and stored bytes" do
    assert :ok = MediaPolicy.check_quota(%{open_uploads: 3, bytes: 1_000})

    assert {:error, :media_quota_exceeded} =
             MediaPolicy.check_quota(%{open_uploads: MediaPolicy.max_open_uploads(), bytes: 0})

    assert {:error, :media_quota_exceeded} =
             MediaPolicy.check_quota(%{open_uploads: 0, bytes: MediaPolicy.max_account_bytes()})
  end

  test "processing failures that reject versus retry" do
    assert MediaPolicy.rejection?(:video_too_long)
    assert MediaPolicy.rejection?(:media_unreadable)
    refute MediaPolicy.rejection?(:media_storage_unavailable)
  end

  test "unattached uploads become orphans after a day" do
    now = ~U[2026-10-18 12:00:00Z]
    assert MediaPolicy.orphan?(%{attached_at: nil, inserted_at: ~U[2026-10-17 11:59:59Z]}, now)
    refute MediaPolicy.orphan?(%{attached_at: nil, inserted_at: ~U[2026-10-18 00:00:00Z]}, now)
    refute MediaPolicy.orphan?(%{attached_at: now, inserted_at: ~U[2026-10-01 00:00:00Z]}, now)
  end
end
