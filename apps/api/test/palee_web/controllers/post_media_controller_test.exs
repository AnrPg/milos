defmodule PaleeWeb.PostMediaControllerTest do
  @moduledoc """
  ADR-157: photos and videos in posts, end to end through the API: upload,
  complete, processing, posting, the feed's shape, who sees a post before
  its media are ready, alt text, the report queue preview, deletion and
  the sweeps.
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures
  import Palee.TestSupport.ImageFixtures

  alias Palee.Application.SweepOrphanMedia
  alias Palee.Community.{Post, ProfilePost}
  alias Palee.Media.AccountObject
  alias Palee.{Organizations, Repo}
  alias Palee.TestSupport.MemoryObjectStore

  setup %{conn: conn} do
    MemoryObjectStore.start()
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    slug = Organizations.legacy_organization_slug()

    %{
      coach: person.(:coach),
      member: person.(:member),
      other: person.(:member),
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{slug}/community",
      staff: "/api/org/#{slug}/admin/community"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp wod(as, user) do
    %{"clubs" => clubs} = as.(user) |> get("/api/me/clubs") |> json_response(200)
    club = Enum.find(clubs, &(&1["kind"] == "gym"))
    Enum.find(club["channels"], &(&1["kind"] == "wod"))
  end

  # Reserves an upload and puts the bytes where the presigned PUT would.
  defp reserve(as, user, purpose, content_type, body) do
    %{"media_id" => id, "upload_url" => url} =
      as.(user)
      |> send_json(:post, "/api/me/media/uploads", %{
        purpose: purpose,
        content_type: content_type,
        byte_size: byte_size(body)
      })
      |> json_response(200)

    [_, bucket, key] = Regex.run(~r{/upload/(media_\w+)/([^?]+)}, url)
    :ok = MemoryObjectStore.put_object(String.to_existing_atom(bucket), key, body, content_type)
    {id, key}
  end

  defp complete(as, user, id),
    do:
      as.(user)
      |> post("/api/me/media/#{id}/complete")
      |> json_response(200)
      |> Map.fetch!("media")

  defp photo!(as, user, body \\ jpeg(4032, 3024, [exif_segment()])) do
    {id, _key} = reserve(as, user, "post_photo", "image/jpeg", body)
    assert %{"status" => "ready"} = complete(as, user, id)
    id
  end

  defp feed(as, user),
    do: as.(user) |> get("/api/me/feed") |> json_response(200) |> Map.fetch!("posts")

  defp find(posts, id), do: Enum.find(posts, &(&1["id"] == id))

  test "the compose learns this server's limits", %{as: as, member: member} do
    assert %{"max_photos" => 10, "max_videos" => 1, "video" => true, "max_video_seconds" => 120} =
             as.(member) |> get("/api/me/media/capabilities") |> json_response(200)
  end

  test "a photo is verified, stripped into renditions and posted to a club", ctx do
    %{as: as, member: member, other: other, base: base} = ctx

    {id, key} =
      reserve(as, member, "post_photo", "image/jpeg", jpeg(4032, 3024, [exif_segment()]))

    assert key =~ ~r{^users/#{member.id}/media/posts/#{id}/original\.jpg$}

    assert %{
             "status" => "ready",
             "kind" => "image",
             "content_type" => "image/webp",
             "width" => 2048,
             "height" => 1536,
             "placeholder" => "data:image/webp;base64," <> _,
             "thumb_url" => thumb,
             "feed_url" => feed_url,
             "full_url" => full
           } = complete(as, member, id)

    assert thumb =~ "media_private/users/#{member.id}/media/posts/#{id}/thumb.webp"
    assert feed_url =~ "/feed.webp" and full =~ "/full.webp"

    # The original, with what the camera wrote, is gone; only renditions stay.
    assert :error = MemoryObjectStore.get(:media_private, key)

    assert {:ok, _} =
             MemoryObjectStore.get(
               :media_private,
               String.replace(key, "original.jpg", "feed.webp")
             )

    second = photo!(as, member)

    assert %{"post" => %{"id" => post_id, "media_status" => "ready", "media" => [first, _]}} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod(as, member)["id"],
               media_ids: [id, second]
             })
             |> json_response(201)

    assert first["id"] == id

    # Others read it with URLs signed for its author, in order.
    assert %{"media" => [%{"id" => ^id, "width" => 2048, "feed_url" => url}, %{"id" => ^second}]} =
             other |> then(&feed(as, &1)) |> find(post_id)

    assert url =~ "users/#{member.id}/media/posts/#{id}/feed.webp"

    # An upload goes in one post only.
    assert %{"code" => "invalid_media"} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod(as, member)["id"],
               media_ids: [id]
             })
             |> json_response(422)
  end

  test "a post published while its media upload shows to its author only until ready", ctx do
    %{as: as, member: member, other: other, base: base} = ctx

    {id, _key} = reserve(as, member, "post_photo", "image/jpeg", jpeg(1200, 900))

    assert %{"post" => %{"id" => post_id, "media_status" => "processing", "media" => [pending]}} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod(as, member)["id"],
               body: "PR day",
               media_ids: [id]
             })
             |> json_response(201)

    assert %{"status" => "pending", "feed_url" => nil} = pending
    assert %{"media_status" => "processing"} = member |> then(&feed(as, &1)) |> find(post_id)
    refute other |> then(&feed(as, &1)) |> find(post_id)

    # Its comments are out of reach too.
    assert as.(other) |> get("/api/me/community/posts/#{post_id}/comments") |> json_response(404)

    assert %{"status" => "ready"} = complete(as, member, id)

    assert %{"media_status" => "ready", "media" => [%{"status" => "ready", "feed_url" => url}]} =
             other |> then(&feed(as, &1)) |> find(post_id)

    assert is_binary(url)
  end

  test "the profile's «Πολυμέσα» grid: only posts with media, by the same audience (ADR-231)",
       ctx do
    %{as: as, member: member, other: other, coach: stranger} = ctx
    private_account!(member)

    post! = fn body ->
      as.(member)
      |> send_json(:post, "/api/profile-posts", body)
      |> json_response(201)
      |> get_in(["post", "id"])
    end

    _text_only = post!.(%{audience: "public", body: "Words only"})
    public_photo = post!.(%{audience: "public", media_ids: [photo!(as, member)]})

    followers_photos =
      post!.(%{audience: "followers", media_ids: [photo!(as, member), photo!(as, member)]})

    {pending, _key} = reserve(as, member, "post_photo", "image/jpeg", jpeg(1200, 900))
    processing = post!.(%{audience: "public", media_ids: [pending]})

    grid = fn user ->
      as.(user)
      |> get("/api/people/#{member.id}/media")
      |> json_response(200)
      |> Map.fetch!("posts")
      |> Enum.map(& &1["id"])
    end

    # The author sees their own grid, still-processing posts included.
    assert grid.(member) == [processing, followers_photos, public_photo]
    # Not a follower of a private account: the public posts with ready media only.
    assert grid.(stranger) == [public_photo]

    assert %{"status" => "requested"} =
             as.(other)
             |> send_json(:post, "/api/me/follows", %{target_type: "user", target_id: member.id})
             |> json_response(200)

    assert grid.(other) == [public_photo]

    assert %{"entries" => [%{"follow_id" => follow_id}]} =
             as.(member) |> get("/api/me/follow-requests") |> json_response(200)

    assert as.(member) |> post("/api/me/follow-requests/#{follow_id}/accept") |> response(204)
    assert grid.(other) == [followers_photos, public_photo]

    assert %{"posts" => [%{"media" => [%{"thumb_url" => thumb}, _second]} | _]} =
             as.(other) |> get("/api/people/#{member.id}/media") |> json_response(200)

    assert thumb =~ "users/#{member.id}/media/posts/"

    assert %{"posts_count" => 3, "media_count" => 2} =
             as.(member) |> get("/api/me/social") |> json_response(200)

    assert as.(other) |> get("/api/people/#{Ecto.UUID.generate()}/media") |> response(404)
  end

  test "a photo that cannot be decoded fails the post, for its author only", ctx do
    %{as: as, member: member, other: other} = ctx

    {id, _key} = reserve(as, member, "post_photo", "image/jpeg", jpeg(10, 10) <> "UNREADABLE")

    assert %{"post" => %{"id" => post_id}} =
             as.(member)
             |> send_json(:post, "/api/profile-posts", %{audience: "public", media_ids: [id]})
             |> json_response(201)

    assert %{"status" => "rejected", "rejection_reason" => "media_unreadable"} =
             complete(as, member, id)

    assert %{"media_status" => "failed"} =
             as.(member)
             |> get("/api/people/#{member.id}/posts")
             |> json_response(200)
             |> Map.fetch!("posts")
             |> find(post_id)

    refute as.(other)
           |> get("/api/people/#{member.id}/posts")
           |> json_response(200)
           |> Map.fetch!("posts")
           |> find(post_id)
  end

  test "composition: up to ten photos or one video, only your own uploads", ctx do
    %{as: as, member: member, other: other, base: base} = ctx
    channel = wod(as, member)["id"]

    photos = for _ <- 1..11, do: photo!(as, member, jpeg(800, 600))

    assert %{"errors" => [%{"source" => %{"pointer" => "/media_ids"}}]} =
             as.(member)
             |> send_json(:post, "/api/profile-posts", %{audience: "followers", media_ids: photos})
             |> json_response(422)

    {video, _key} = reserve(as, member, "post_video", "video/mp4", mp4())
    assert %{"status" => "ready"} = complete(as, member, video)

    assert %{"code" => "mixed_media"} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: channel,
               media_ids: [hd(photos), video]
             })
             |> json_response(422)

    theirs = photo!(as, other)

    assert %{"code" => "invalid_media"} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{channel_id: channel, media_ids: [theirs]})
             |> json_response(422)

    # Someone else's upload is not even visible.
    assert as.(member) |> get("/api/me/media/#{theirs}") |> json_response(404)

    assert %{"post" => %{"media" => media}} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: channel,
               media_ids: Enum.take(photos, 10)
             })
             |> json_response(201)

    assert length(media) == 10
  end

  test "a short video becomes one MP4 with a poster; a long one is rejected", ctx do
    %{as: as, member: member, other: other} = ctx

    {video, key} = reserve(as, member, "post_video", "video/quicktime", mov())

    assert %{
             "status" => "ready",
             "kind" => "video",
             "content_type" => "video/mp4",
             "duration_ms" => 12_000,
             "video_url" => video_url,
             "feed_url" => poster
           } = complete(as, member, video)

    assert video_url =~ "/media/posts/#{video}/video.mp4"
    assert poster =~ "/media/posts/#{video}/feed.webp"
    assert :error = MemoryObjectStore.get(:media_private, key)

    assert %{"post" => %{"id" => post_id, "media" => [%{"kind" => "video", "video_url" => _}]}} =
             as.(member)
             |> send_json(:post, "/api/profile-posts", %{
               audience: "public",
               body: "Snatch",
               media_ids: [video]
             })
             |> json_response(201)

    assert %{"media" => [%{"duration_ms" => 12_000, "video_url" => url}]} =
             as.(other)
             |> get("/api/people/#{member.id}/posts")
             |> json_response(200)
             |> Map.fetch!("posts")
             |> find(post_id)

    assert url =~ "users/#{member.id}/"

    {long, _key} = reserve(as, member, "post_video", "video/mp4", mp4() <> "LONG")

    assert %{"status" => "rejected", "rejection_reason" => "video_too_long"} =
             complete(as, member, long)
  end

  test "videos are refused up front where they cannot be transcoded", %{as: as, member: member} do
    Application.put_env(:palee, :fake_video_available, false)
    on_exit(fn -> Application.delete_env(:palee, :fake_video_available) end)

    assert %{"video" => false} =
             as.(member) |> get("/api/me/media/capabilities") |> json_response(200)

    assert %{"code" => "video_unavailable"} =
             as.(member)
             |> send_json(:post, "/api/me/media/uploads", %{
               purpose: "post_video",
               content_type: "video/mp4",
               byte_size: 100
             })
             |> json_response(503)
  end

  test "an upload whose bytes are not what a phone makes is refused and removed", ctx do
    %{as: as, member: member} = ctx
    {id, key} = reserve(as, member, "post_photo", "image/jpeg", "<svg onload=alert(1)>")

    assert %{"code" => "invalid_media_type"} =
             as.(member) |> post("/api/me/media/#{id}/complete") |> json_response(422)

    assert :error = MemoryObjectStore.get(:media_private, key)
    assert as.(member) |> get("/api/me/media/#{id}") |> json_response(404)
  end

  test "alt text: an AI suggestion comes back to you only; what you save reaches the post", ctx do
    %{as: as, member: member, other: other, base: base} = ctx
    id = photo!(as, member)

    assert %{"suggestion" => "Αθλήτρια σηκώνει μπάρα σε box"} =
             as.(member)
             |> send_json(:post, "/api/me/media/#{id}/alt-text-suggestion", %{locale: "el"})
             |> json_response(200)

    assert_received {:described, "el", %{feature: "post_alt_text", user_id: user_id}}
    assert user_id == member.id

    # Nothing was saved.
    assert %{"media" => %{"alt_text" => nil}} =
             as.(member) |> get("/api/me/media/#{id}") |> json_response(200)

    # Without a language asked for, the person's own.
    assert %{"suggestion" => "An athlete lifts a barbell in a gym"} =
             as.(member)
             |> send_json(:post, "/api/me/media/#{id}/alt-text-suggestion", %{})
             |> json_response(200)

    assert %{"post" => %{"id" => post_id}} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod(as, member)["id"],
               media_ids: [id]
             })
             |> json_response(201)

    assert %{"media" => %{"alt_text" => "Άρση θανάτου"}} =
             as.(member)
             |> send_json(:patch, "/api/me/media/#{id}", %{alt_text: "  Άρση θανάτου "})
             |> json_response(200)

    assert %{"media" => [%{"alt_text" => "Άρση θανάτου"}]} =
             other |> then(&feed(as, &1)) |> find(post_id)

    Application.put_env(:palee, :fake_describer_configured, false)
    on_exit(fn -> Application.delete_env(:palee, :fake_describer_configured) end)

    assert %{"code" => "alt_text_unavailable"} =
             as.(member)
             |> send_json(:post, "/api/me/media/#{id}/alt-text-suggestion", %{})
             |> json_response(503)
  end

  test "the staff report queue shows a reported post's photos", ctx do
    %{as: as, member: member, other: other, coach: coach, base: base, staff: staff} = ctx
    id = photo!(as, member)

    assert %{"post" => %{"id" => post_id}} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod(as, member)["id"],
               media_ids: [id]
             })
             |> json_response(201)

    assert %{"reported" => true} =
             as.(other)
             |> send_json(:post, "/api/me/community/reports", %{
               target_type: "post",
               target_id: post_id,
               reason: "inappropriate"
             })
             |> json_response(201)

    assert %{"reports" => [%{"preview" => %{"media_status" => "ready", "media" => [thumb]}}]} =
             as.(coach) |> get("#{staff}/reports") |> json_response(200)

    assert %{"id" => ^id, "thumb_url" => url} = thumb
    assert url =~ "users/#{member.id}/media/posts/#{id}/thumb.webp"

    # Removing the post removes its photos.
    assert %{"resolved" => 1} =
             as.(coach)
             |> send_json(:post, "#{staff}/reports/actions", %{
               target_type: "post",
               target_id: post_id,
               action: "delete"
             })
             |> json_response(200)

    refute Repo.get(AccountObject, id)
    assert [] = objects(member.id, id)
  end

  test "deleting a post deletes its uploads and their renditions", ctx do
    %{as: as, member: member} = ctx
    id = photo!(as, member)
    assert [_ | _] = objects(member.id, id)

    assert %{"post" => %{"id" => post_id}} =
             as.(member)
             |> send_json(:post, "/api/profile-posts", %{audience: "followers", media_ids: [id]})
             |> json_response(201)

    assert %{"code" => "media_in_post"} =
             as.(member) |> delete("/api/me/media/#{id}") |> json_response(409)

    assert as.(member) |> delete("/api/profile-posts/#{post_id}") |> response(204)
    refute Repo.get(AccountObject, id)
    assert [] = objects(member.id, id)
  end

  test "an upload taken out of the compose can be discarded", %{as: as, member: member} do
    id = photo!(as, member)
    assert as.(member) |> delete("/api/me/media/#{id}") |> response(204)
    refute Repo.get(AccountObject, id)
    assert [] = objects(member.id, id)
  end

  test "sweeps: orphans after a day, stale uploads in posts, uploads of posts that are gone",
       ctx do
    %{as: as, member: member, base: base} = ctx
    orphan = photo!(as, member)

    {stale, _key} = reserve(as, member, "post_photo", "image/jpeg", jpeg(800, 600))

    assert %{"post" => %{"id" => stale_post}} =
             as.(member)
             |> send_json(:post, "#{base}/posts", %{
               channel_id: wod(as, member)["id"],
               media_ids: [stale]
             })
             |> json_response(201)

    gone = photo!(as, member)

    assert %{"post" => %{"id" => gone_post}} =
             as.(member)
             |> send_json(:post, "/api/profile-posts", %{audience: "followers", media_ids: [gone]})
             |> json_response(201)

    # The post vanished without releasing its upload (e.g. a purge).
    Repo.delete_all(from(p in ProfilePost, where: p.id == ^gone_post))

    later = DateTime.add(DateTime.utc_now(), 2 * 86_400)
    {:ok, _count} = SweepOrphanMedia.call(later, dangling: true)

    refute Repo.get(AccountObject, orphan)
    assert [] = objects(member.id, orphan)
    refute Repo.get(AccountObject, gone)

    assert %AccountObject{status: "rejected", rejection_reason: "media_processing_timeout"} =
             Repo.get(AccountObject, stale)

    assert %Post{media_status: "failed"} = Repo.get(Post, stale_post)
  end

  test "the quota caps open uploads per person", %{as: as, member: member} do
    for _ <- 1..Palee.Media.Domain.MediaPolicy.max_open_uploads() do
      Repo.insert!(%AccountObject{
        user_id: member.id,
        purpose: "post_photo",
        object_key: "users/#{member.id}/media/posts/#{Ecto.UUID.generate()}/original.jpg",
        content_type: "image/jpeg"
      })
    end

    assert %{"code" => "media_quota_exceeded"} =
             as.(member)
             |> send_json(:post, "/api/me/media/uploads", %{
               purpose: "post_photo",
               content_type: "image/jpeg",
               byte_size: 100
             })
             |> json_response(422)
  end

  test "a PR prefills the compose with its card", %{as: as, member: member} do
    assert %{"pr" => %{"id" => pr_id}} =
             as.(member)
             |> send_json(:post, "/api/prs", %{
               name: "Back squat",
               current_score: 140,
               unit: "kg",
               beaten_on: "2026-10-20"
             })
             |> json_response(201)

    assert %{
             "attachment_type" => "pr",
             "attachment_id" => ^pr_id,
             "attachment" => %{"title" => "Back squat", "unit" => "kg"} = card
           } = as.(member) |> get("/api/me/post-attachments/pr/#{pr_id}") |> json_response(200)

    refute Map.has_key?(card, "previous_visibility")
  end

  defp objects(user_id, media_id) do
    {:ok, list} =
      MemoryObjectStore.list_objects(:media_private, "users/#{user_id}/media/posts/#{media_id}/")

    list
  end

  defp mp4, do: <<0, 0, 0, 32, "ftypisom", 0, 0, 2, 0>> <> :binary.copy(<<0>>, 64)
  defp mov, do: <<0, 0, 0, 20, "ftypqt  ", 0, 0, 2, 0>> <> :binary.copy(<<0>>, 64)
end
