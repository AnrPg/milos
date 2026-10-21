defmodule MilosTraining.Application.BoxPublicProfileTest do
  @moduledoc "ADR-142/ADR-148: the public profile editor and its photo uploads."

  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures
  import MilosTraining.TestSupport.ImageFixtures

  alias MilosTraining.Application.{
    BoxPublicProfile,
    CompleteMediaUpload,
    PublishBoxPublicProfile,
    RequestMediaUpload,
    SuggestBoxTag,
    SweepOrphanMedia,
    UpdateBoxPublicProfile
  }

  alias MilosTraining.{Media, Organizations}
  alias MilosTraining.TestSupport.MemoryObjectStore

  setup do
    MemoryObjectStore.start()
    %{a: organization_with(:owner), b: organization_with(:owner)}
  end

  test "an unedited gym reads as an empty, unpublished profile", %{a: a} do
    assert {:ok,
            %{
              about: nil,
              cover: nil,
              photos: [],
              published: false,
              missing: ["about", "disciplines"],
              languages: ["el", "en"],
              lock_version: 0
            }} = BoxPublicProfile.get(a.context)
  end

  test "the first save keeps Greek and English unless languages are sent", %{a: a, b: b} do
    assert {:ok, %{languages: ["el", "en"]}} =
             UpdateBoxPublicProfile.call(a.context, %{"about" => "Box"})

    assert {:ok, %{languages: ["de"]}} =
             UpdateBoxPublicProfile.call(b.context, %{"languages" => ["de"]})

    assert {:ok, %{languages: ["el", "en"]}} =
             UpdateBoxPublicProfile.call(a.context, %{"about" => "Box Κυψέλη"})
  end

  test "upload, verify, attach, reorder and release box photos", %{a: a} do
    first = upload!(a.context, jpeg(1600, 1200))
    second = upload!(a.context, webp_lossy(800, 600))
    cover = upload!(a.context, jpeg(1200, 600))

    assert {:ok, profile} =
             UpdateBoxPublicProfile.call(a.context, %{
               "about" => "  Ένα box στην Κυψέλη.  ",
               "disciplines" => ["crossfit", "hyrox"],
               "languages" => ["EL", "en"],
               "audiences" => ["beginners"],
               "amenities" => ["showers", "parking"],
               "services" => ["open_gym"],
               "cover_photo_id" => cover.id,
               "photo_ids" => [second.id, first.id]
             })

    assert profile.about == "Ένα box στην Κυψέλη."
    assert profile.languages == ["el", "en"]
    assert profile.amenities == ["showers", "parking"]
    refute profile.published
    assert profile.missing == []
    assert %{id: cover_id, width: 1200} = profile.cover
    assert cover_id == cover.id
    assert [%{id: id2, width: 800}, %{id: id1, width: 1600}] = profile.photos
    assert {id1, id2} == {first.id, second.id}
    assert hd(profile.photos).url =~ "https://media.test/media_public/organizations/"

    {:ok, profile} = PublishBoxPublicProfile.publish(a.context)
    assert profile.published
    refute profile.unpublished_changes
    published_at = profile.published_at

    # Dropped from the draft but still on the live page: kept until republished.
    assert {:ok, profile} =
             UpdateBoxPublicProfile.call(a.context, %{
               "photo_ids" => [first.id],
               "cover_photo_id" => nil,
               "lock_version" => profile.lock_version
             })

    assert profile.unpublished_changes
    assert profile.cover == nil
    assert [%{id: ^id1}] = profile.photos
    assert Media.get(a.context, :tenant, second.id)
    assert Media.get(a.context, :tenant, cover.id)

    {:ok, profile} =
      PublishBoxPublicProfile.publish(a.context, %{"lock_version" => profile.lock_version})

    assert profile.published_at == published_at
    refute profile.unpublished_changes
    assert Media.get(a.context, :tenant, second.id) == nil
    assert Media.get(a.context, :tenant, cover.id) == nil
    assert MemoryObjectStore.get(:media_public, second.object_key) == :error
  end

  test "a stale editor loses, publishing needs text and a discipline, unpublishing keeps the draft",
       %{a: a} do
    assert {:error, :public_profile_empty} = PublishBoxPublicProfile.publish(a.context)

    {:ok, profile} = UpdateBoxPublicProfile.call(a.context, %{"disciplines" => ["yoga"]})
    assert profile.missing == ["about"]
    assert {:error, :public_profile_empty} = PublishBoxPublicProfile.publish(a.context)

    assert {:error, :stale_profile} =
             UpdateBoxPublicProfile.call(a.context, %{"about" => "x", "lock_version" => 99})

    {:ok, profile} =
      UpdateBoxPublicProfile.call(a.context, %{
        "about" => "Yoga",
        "lock_version" => profile.lock_version
      })

    assert {:error, :stale_profile} =
             PublishBoxPublicProfile.publish(a.context, %{"lock_version" => 1_000})

    {:ok, profile} =
      PublishBoxPublicProfile.publish(a.context, %{"lock_version" => profile.lock_version})

    assert profile.published

    {:ok, profile} = PublishBoxPublicProfile.unpublish(a.context)
    refute profile.published
    assert profile.published_at == nil
    assert profile.about == "Yoga"
  end

  test "tags come from the canonical lists and stay consistent", %{a: a} do
    assert {:error, %Ecto.Changeset{}} =
             UpdateBoxPublicProfile.call(a.context, %{"amenities" => ["helipad"]})

    assert {:error, %Ecto.Changeset{errors: [audiences: _]}} =
             UpdateBoxPublicProfile.call(a.context, %{"audiences" => ["returning_from_injury"]})

    assert {:ok, %{audiences: ["returning_from_injury"]}} =
             UpdateBoxPublicProfile.call(a.context, %{
               "disciplines" => ["physio_rehab"],
               "audiences" => ["returning_from_injury"]
             })
  end

  test "owners suggest missing tags and the platform reviews them", %{a: a, b: b} do
    assert {:ok, %{id: id, status: "pending"}} =
             SuggestBoxTag.call(a.context, %{"list" => "disciplines", "name" => " Animal flow "})

    assert {:error, %Ecto.Changeset{}} =
             SuggestBoxTag.call(b.context, %{"list" => "colours", "name" => "Red"})

    assert [%{id: ^id, name: "Animal flow", list: "disciplines", organization_name: name}] =
             Enum.filter(SuggestBoxTag.pending(), &(&1.id == id))

    assert name == a.organization.name
    assert :ok = SuggestBoxTag.resolve(id, "added")
    assert {:error, :not_found} = SuggestBoxTag.resolve(id, "declined")
    refute Enum.any?(SuggestBoxTag.pending(), &(&1.id == id))
  end

  test "photos must be this gym's ready box photos", %{a: a, b: b} do
    other_gym = upload!(b.context, jpeg(100, 100))

    assert {:error, :invalid_media} =
             UpdateBoxPublicProfile.call(a.context, %{"photo_ids" => [other_gym.id]})

    {:ok, pending} =
      RequestMediaUpload.call(a.context, "box_photo", %{
        "content_type" => "image/jpeg",
        "byte_size" => 10
      })

    assert {:error, :invalid_media} =
             UpdateBoxPublicProfile.call(a.context, %{"photo_ids" => [pending.media_id]})
  end

  test "an image with EXIF is refused and deleted", %{a: a} do
    {:ok, upload} =
      RequestMediaUpload.call(a.context, "box_photo", %{
        "content_type" => "image/jpeg",
        "byte_size" => 10
      })

    media = Media.get(a.context, :tenant, upload.media_id)

    :ok =
      MemoryObjectStore.put_object(
        :media_public,
        media.object_key,
        jpeg(10, 10, [exif_segment()]),
        "x"
      )

    assert {:error, :media_has_metadata} =
             CompleteMediaUpload.call(a.context, "box_photo", upload.media_id)

    assert Media.get(a.context, :tenant, upload.media_id) == nil
    assert MemoryObjectStore.get(:media_public, media.object_key) == :error
  end

  test "members without settings rights cannot upload or edit", %{a: a} do
    member = user_fixture()
    add_member(a.organization, member, :member)
    {:ok, context} = Organizations.resolve_tenant_context(member, a.organization.slug)

    assert {:error, :forbidden} =
             RequestMediaUpload.call(context, "box_photo", %{
               "content_type" => "image/jpeg",
               "byte_size" => 10
             })

    assert {:error, _forbidden} = UpdateBoxPublicProfile.call(context, %{"about" => "x"})
  end

  test "the sweep deletes unattached uploads after a day and keeps attached ones", %{a: a} do
    kept = upload!(a.context, jpeg(10, 10))
    orphan = upload!(a.context, jpeg(10, 10))
    {:ok, _profile} = UpdateBoxPublicProfile.call(a.context, %{"photo_ids" => [kept.id]})

    {:ok, account_upload} =
      Media.create(%{user_id: a.owner.id}, :account, %{
        id: Ecto.UUID.generate(),
        purpose: "body_photo",
        object_key: "users/#{a.owner.id}/media/body/x.jpg",
        content_type: "image/jpeg"
      })

    assert {:ok, 0} = SweepOrphanMedia.call(DateTime.utc_now())
    assert {:ok, deleted} = SweepOrphanMedia.call(DateTime.add(DateTime.utc_now(), 2, :day))
    assert deleted >= 2

    assert Media.get(a.context, :tenant, orphan.id) == nil
    assert Media.get(a.context, :tenant, kept.id)
    assert Media.get(%{user_id: a.owner.id}, :account, account_upload.id) == nil
  end

  defp upload!(context, body) do
    content_type = if String.starts_with?(body, "RIFF"), do: "image/webp", else: "image/jpeg"

    {:ok, upload} =
      RequestMediaUpload.call(context, "box_photo", %{
        "content_type" => content_type,
        "byte_size" => byte_size(body)
      })

    media = Media.get(context, :tenant, upload.media_id)
    :ok = MemoryObjectStore.put_object(:media_public, media.object_key, body, content_type)
    {:ok, _ready} = CompleteMediaUpload.call(context, "box_photo", upload.media_id)
    Media.get(context, :tenant, upload.media_id)
  end

  defp organization_with(role) do
    owner = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Profile Gym #{System.unique_integer([:positive])}"
      })

    add_member(organization, owner, role)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    %{organization: organization, owner: owner, context: context}
  end

  defp add_member(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
