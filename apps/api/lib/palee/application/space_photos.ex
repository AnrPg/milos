defmodule Palee.Application.SpacePhotos do
  @moduledoc """
  Photos of a room and its visual cleaning checklist (ADR-290).

    * Room photos (`:photos`, `space_photo` media) give an idea of the room.
      Each one starts off the public box page; whoever uploads turns it on.
    * Cleaning points (`:points`, `cleaning_photo` media) are a photo of a
      part of the room and what to clean there; the janitor answers each one
      when finishing a cleaning (`CleaningLog`).

  Owners, admins (`manage_spaces`) and front desk (`edit_space_details`)
  manage both, for the spaces of the branches they work at.
  """

  alias Palee.Application.{MediaUrls, ReleaseMedia, SpaceDirectory}
  alias Palee.{Media, Spaces}

  @purposes %{photos: "space_photo", points: "cleaning_photo"}
  @fields %{photos: [:caption, :public], points: [:instruction]}

  def purpose(kind), do: Map.fetch!(@purposes, kind)

  @doc "A space's photos and cleaning points, with URLs."
  def for_space(context, space_id) do
    %{
      photos:
        present(context, :photos, Spaces.list_photos(context, :photos, %{space_ids: [space_id]})),
      points:
        present(context, :points, Spaces.list_photos(context, :points, %{space_ids: [space_id]}))
    }
  end

  @doc "Adds a ready upload to a space as a room photo or a cleaning point."
  def add(context, kind, space_id, params) do
    media_id = Map.get(params, :media_id)

    with {:ok, space} <- SpaceDirectory.fetch(context, space_id),
         {:ok, [_media]} <- Media.fetch_ready(context, purpose(kind), [media_id]),
         attrs = params |> Map.take(@fields[kind]) |> Map.put(:media_id, media_id),
         {:ok, row} <- Spaces.add_photo(context, kind, space.id, attrs) do
      _ = Media.set_attached(context, :tenant, [media_id], DateTime.utc_now())
      {:ok, hd(present(context, kind, [row]))}
    end
  end

  @doc """
  Changes a photo's caption or whether it is public, or a point's
  instruction or photo (the old photo is deleted).
  """
  def update(context, kind, id, params) do
    attrs = Map.take(params, [:media_id | @fields[kind]])

    with {:ok, row} <- fetch(context, kind, id),
         :ok <- new_media(context, kind, row, Map.get(attrs, :media_id)),
         {:ok, updated} <- Spaces.update_photo(context, kind, row.id, attrs) do
      if updated.media_id != row.media_id,
        do: ReleaseMedia.call(context, :tenant, [row.media_id])

      {:ok, hd(present(context, kind, [updated]))}
    end
  end

  def delete(context, kind, id) do
    with {:ok, row} <- fetch(context, kind, id),
         {:ok, deleted} <- Spaces.delete_photo(context, kind, row.id) do
      :ok = ReleaseMedia.call(context, :tenant, [deleted.media_id])
      {:ok, deleted}
    end
  end

  @doc "Reorders a space's photos or points by `ids`."
  def order(context, kind, space_id, ids) do
    with {:ok, space} <- SpaceDirectory.fetch(context, space_id) do
      {:ok, present(context, kind, Spaces.order_photos(context, kind, space.id, List.wrap(ids)))}
    end
  end

  @doc "Rows with `url`, `width` and `height` from their ready media (missing media dropped)."
  def present(_context, _kind, []), do: []

  def present(context, kind, rows) do
    media =
      context
      |> Media.list(:tenant, rows |> Enum.map(& &1.media_id) |> Enum.uniq())
      |> Enum.filter(&(&1.status == "ready" and &1.purpose == purpose(kind)))
      |> Map.new(&{&1.id, MediaUrls.present(context, &1)})

    rows
    |> Enum.filter(&Map.has_key?(media, &1.media_id))
    |> Enum.map(fn row ->
      shown = media[row.media_id]
      Map.merge(row, %{url: shown.url, width: shown.width, height: shown.height})
    end)
  end

  # The row, when its space is one the caller works at.
  defp fetch(context, kind, id) do
    with %{} = row <- Spaces.get_photo(context, kind, id) || {:error, :not_found},
         {:ok, _space} <- SpaceDirectory.fetch(context, row.space_id) do
      {:ok, row}
    else
      {:error, :space_not_found} -> {:error, :not_found}
      error -> error
    end
  end

  defp new_media(_context, _kind, _row, nil), do: :ok
  defp new_media(_context, _kind, %{media_id: same}, same), do: :ok

  defp new_media(context, :points, _row, media_id) do
    with {:ok, [_media]} <- Media.fetch_ready(context, purpose(:points), [media_id]) do
      _ = Media.set_attached(context, :tenant, [media_id], DateTime.utc_now())
      :ok
    end
  end

  defp new_media(_context, :photos, _row, _media_id), do: {:error, :invalid_media}
end
