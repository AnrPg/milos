defmodule Palee.Application.BoxPhotoCovers do
  @moduledoc """
  Covers of open clubs (ADR-143) and club events (ADR-153): a `box_photo`
  upload of the gym (ADR-148), checked ready before use, marked attached
  while in use and released when replaced.
  """

  alias Palee.Application.{MediaUrls, ReleaseMedia}
  alias Palee.Media

  @doc "Cover URLs by media id for rows carrying `organization_id` and `cover_media_id`."
  def urls(rows) do
    rows
    |> Enum.reject(&is_nil(&1.cover_media_id))
    |> Enum.group_by(& &1.organization_id, & &1.cover_media_id)
    |> Enum.flat_map(fn {organization_id, ids} ->
      gym = %{organization_id: organization_id}
      gym |> Media.list(:tenant, Enum.uniq(ids)) |> then(&MediaUrls.present_all(gym, &1))
    end)
    |> Map.new(&{&1.id, &1.url})
  end

  @doc "A cover being set must be one of the gym's ready box photos."
  def ready(context, id) when is_binary(id) do
    case Media.fetch_ready(context, "box_photo", [id]) do
      {:ok, _media} -> :ok
      error -> error
    end
  end

  def ready(_context, _id), do: :ok

  @doc """
  The new cover is in use; the one it replaced is released unless
  `still_used?` says something else still shows it.
  """
  def settle(context, before, now, still_used? \\ fn _id -> false end)

  def settle(_context, same, same, _still_used?), do: :ok

  def settle(context, before, now, still_used?) do
    if now, do: :ok = Media.set_attached(context, :tenant, [now], DateTime.utc_now())
    if before && not still_used?.(before), do: ReleaseMedia.call(context, :tenant, [before])
    :ok
  end
end
