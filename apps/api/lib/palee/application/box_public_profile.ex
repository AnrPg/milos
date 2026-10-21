defmodule Palee.Application.BoxPublicProfile do
  @moduledoc """
  ADR-142: a gym's public profile as staff edit it (Σχετικά of the public
  box page): the draft with its photos resolved to URLs, whether it is
  published, whether the draft differs from what visitors see, and what is
  still missing before it can be published. A gym without a stored profile
  reads as an empty, unpublished one
  (with the default languages pre-picked).
  """

  alias Palee.Application.MediaUrls
  alias Palee.{Identity, Media, Organizations}

  @snapshot_fields ~w(about disciplines audiences amenities services languages cover_photo_id photo_ids coach_ids)a

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

    candidates = coach_candidates(context.organization_id)
    picked = Map.new(candidates, &{&1.id, &1})

    profile
    |> Map.drop([:photo_ids, :cover_photo_id, :published_snapshot, :coach_ids])
    |> Map.merge(%{
      cover: profile.cover_photo_id && by_id[profile.cover_photo_id],
      photos: profile.photo_ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1),
      coaches:
        profile |> Map.get(:coach_ids, []) |> Enum.map(&picked[&1]) |> Enum.reject(&is_nil/1),
      coach_candidates: candidates,
      published: published,
      unpublished_changes: published and snapshot(profile) != published_view(profile),
      missing: Organizations.box_profile_missing(profile)
    })
  end

  @doc """
  The gym's staff the owner may show as coaches (board 4 Q4), as people:
  someone who leaves the staff drops off the page without an edit.
  """
  def coach_candidates(organization_id) do
    ids = organization_id |> Organizations.list_staff() |> Enum.map(& &1.user_id)

    ids
    |> Identity.list_by_ids()
    |> Enum.map(&%{id: &1.id, nickname: &1.nickname, avatar_url: Map.get(&1, :avatar_url)})
    |> Enum.sort_by(&(&1.nickname || ""))
  end

  # Snapshots published before a field existed read as its empty value.
  defp published_view(profile),
    do: Map.merge(%{"coach_ids" => []}, profile.published_snapshot || %{})

  defp empty(context) do
    %{
      organization_id: context.organization_id,
      about: nil,
      disciplines: [],
      languages: Organizations.default_box_languages(),
      audiences: [],
      amenities: [],
      services: [],
      cover_photo_id: nil,
      photo_ids: [],
      coach_ids: [],
      published_snapshot: nil,
      published_at: nil,
      lock_version: 0,
      updated_at: nil
    }
  end
end
