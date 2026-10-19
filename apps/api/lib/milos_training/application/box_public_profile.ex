defmodule MilosTraining.Application.BoxPublicProfile do
  @moduledoc """
  ADR-142: a gym's public profile as staff edit it (Σχετικά of the public
  box page): the draft with its photos resolved to URLs, whether it is
  published, whether the draft differs from what visitors see, and what is
  still missing before it can be published. A gym without a stored profile
  reads as an empty, unpublished one.
  """

  alias MilosTraining.Application.MediaUrls
  alias MilosTraining.{Media, Organizations}

  @snapshot_fields ~w(about disciplines audiences amenities services languages cover_photo_id photo_ids)a

  def get(context) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings) do
      {:ok, present(context, Organizations.get_public_profile(context))}
    end
  end

  def vocabulary, do: Organizations.box_vocabulary()

  @doc "The fields visitors see, as stored in the published snapshot."
  def snapshot(profile),
    do: Map.new(@snapshot_fields, &{Atom.to_string(&1), Map.get(profile, &1)})

  @doc "Every media id the draft or the published snapshot uses."
  def media_ids(nil), do: []

  def media_ids(profile) do
    published = profile.published_snapshot || %{}

    [profile.cover_photo_id, published["cover_photo_id"]]
    |> Enum.concat(profile.photo_ids)
    |> Enum.concat(published["photo_ids"] || [])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc "A profile map with `cover` and `photos` in place of their ids."
  def present(context, nil), do: present(context, empty(context))

  def present(context, profile) do
    by_id =
      context
      |> Media.list(:tenant, Enum.reject([profile.cover_photo_id | profile.photo_ids], &is_nil/1))
      |> then(&MediaUrls.present_all(context, &1))
      |> Map.new(&{&1.id, &1})

    published = not is_nil(profile.published_at)

    profile
    |> Map.drop([:photo_ids, :cover_photo_id, :published_snapshot])
    |> Map.merge(%{
      cover: profile.cover_photo_id && by_id[profile.cover_photo_id],
      photos: profile.photo_ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1),
      published: published,
      unpublished_changes: published and snapshot(profile) != (profile.published_snapshot || %{}),
      missing: Organizations.box_profile_missing(profile)
    })
  end

  defp empty(context) do
    %{
      organization_id: context.organization_id,
      about: nil,
      disciplines: [],
      languages: [],
      audiences: [],
      amenities: [],
      services: [],
      cover_photo_id: nil,
      photo_ids: [],
      published_snapshot: nil,
      published_at: nil,
      lock_version: 0,
      updated_at: nil
    }
  end
end
