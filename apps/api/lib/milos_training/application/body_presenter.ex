defmodule MilosTraining.Application.BodyPresenter do
  @moduledoc """
  How a body snapshot leaves the server (ADR-158), for its owner or for a
  coach. Every number passes `Body.shown_metrics/2`, so weight and body fat
  never show when the person chose `trend` or `hidden`, to them or to a
  coach. Photo URLs are presigned for the owner's private prefix and
  short-lived; callers decide whether photos may be shown at all.
  """

  alias MilosTraining.Application.MediaStorage
  alias MilosTraining.Body

  @renditions ~w(thumb feed full)

  @doc """
  A snapshot as its owner sees it. `photos` are the snapshot's photo rows.
  Opts: `audience: :owner | :coach` (a coach never gets the notes).
  """
  def snapshot(snapshot, photos, settings, opts \\ []) do
    audience = Keyword.get(opts, :audience, :owner)
    shown = Body.shown_metrics(snapshot.metrics, settings)

    %{
      id: snapshot.id,
      taken_at: snapshot.taken_at,
      taken_tz: snapshot.taken_tz,
      units: settings.units,
      metrics: shown.metrics,
      withheld_metrics: shown.withheld,
      weight_display: settings.weight_display,
      visibility: snapshot.visibility,
      source: Map.get(snapshot, :source, "manual"),
      notes: if(audience == :owner, do: snapshot.notes),
      photos: Enum.map(photos, &photo(&1, snapshot.user_id)),
      photo_count: length(photos),
      inserted_at: snapshot.inserted_at,
      updated_at: snapshot.updated_at
    }
  end

  @doc "Snapshots with their photos (`photos_by_snapshot` keyed by snapshot id)."
  def snapshots(snapshots, photos_by_snapshot, settings, opts \\ []) do
    Enum.map(snapshots, fn snapshot ->
      snapshot(snapshot, Map.get(photos_by_snapshot, snapshot.id, []), settings, opts)
    end)
  end

  @doc "One photo; URLs only once its renditions exist."
  def photo(photo, owner_id) do
    owner = {:account, owner_id}
    variants = if photo.status == "ready", do: photo.variants || %{}, else: %{}

    %{
      id: photo.id,
      snapshot_id: photo.snapshot_id,
      pose: photo.pose,
      status: photo.status,
      width: photo.width,
      height: photo.height,
      placeholder: photo.placeholder
    }
    |> Map.merge(
      Map.new(@renditions, fn name ->
        {String.to_atom(name <> "_url"), url(owner, variants, name)}
      end)
    )
    |> maybe_taken_at(photo)
  end

  defp maybe_taken_at(map, %{taken_at: %DateTime{} = at}), do: Map.put(map, :taken_at, at)
  defp maybe_taken_at(map, _photo), do: map

  @doc "The person's settings as the client reads them."
  def settings(settings) do
    %{
      units: settings.units,
      weight_display: settings.weight_display,
      journal_sections: settings.journal_sections,
      measure_reminder_weeks: settings.measure_reminder_weeks,
      default_visibility: settings.default_visibility,
      blur_photos: settings.blur_photos,
      compare_mode: settings.compare_mode
    }
  end

  defp url(owner, variants, name) do
    with %{"key" => key} <- Map.get(variants, name),
         {:ok, url} <- MediaStorage.read_url(owner, :media_private, key) do
      url
    else
      _missing -> nil
    end
  end
end
