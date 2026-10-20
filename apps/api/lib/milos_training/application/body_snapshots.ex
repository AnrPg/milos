defmodule MilosTraining.Application.BodySnapshots do
  @moduledoc """
  Ημερολόγιο › Σώμα for the person (ADR-158): measurement snapshots, the
  series of one metric, and two snapshots compared.

  Metrics come in the person's units (or `units` given with the request)
  and are stored in SI. Every answer goes through the display rules: when
  weight shows as `trend` or `hidden`, no weight or body-fat number leaves
  the server (`withheld_metrics` says one exists under `trend`).

  A snapshot starts from the visibility used last; saving one with a
  visibility makes that the next default.
  """

  alias MilosTraining.Application.{BodyPhotos, BodyPresenter}
  alias MilosTraining.Body

  def list(%{user_id: user_id} = context, params) do
    with {:ok, cursor} <- Body.decode_cursor(param(params, "cursor")) do
      limit = Body.page_limit(param(params, "limit"))
      settings = Body.settings(context, user_id)

      rows = Body.list_snapshots(context, user_id, cursor: cursor, limit: limit + 1)
      {shown, next_cursor} = Body.page(rows, limit)

      {:ok,
       %{
         snapshots: BodyPresenter.snapshots(shown, photos_by_snapshot(context, shown), settings),
         next_cursor: next_cursor
       }}
    end
  end

  def get(%{user_id: user_id} = context, id) do
    with %{} = snapshot <- Body.get_snapshot(context, user_id, id) || {:error, :not_found} do
      {:ok, present(context, snapshot)}
    end
  end

  def create(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    settings = Body.settings(context, user_id)

    with {:ok, units} <- units(params, settings),
         {:ok, metrics} <- metrics(param(params, "metrics") || %{}, units),
         metrics = Body.merge_metrics(%{}, metrics),
         {:ok, prepared} <- BodyPhotos.prepare(context, param(params, "photos") || [], []),
         :ok <- Body.validate_content(metrics, length(prepared)),
         {:ok, visibility} <- visibility(param(params, "visibility"), settings),
         {:ok, notes} <- Body.normalize_notes(param(params, "notes")),
         {:ok, taken_at} <- taken_at(param(params, "taken_at"), now),
         {:ok, taken_tz} <- taken_tz(param(params, "taken_tz")),
         {:ok, snapshot} <-
           Body.create_snapshot(context, %{
             user_id: user_id,
             taken_at: taken_at,
             taken_tz: taken_tz,
             metrics: metrics,
             notes: notes,
             visibility: visibility
           }) do
      case BodyPhotos.attach(context, snapshot, prepared, now) do
        {:ok, _photos} ->
          remember_visibility(context, user_id, settings, visibility)
          {:ok, present(context, snapshot)}

        {:error, reason} ->
          # The snapshot never existed without its photos.
          _photos = cleanup(context, snapshot)
          {:error, reason}
      end
    end
  end

  @doc """
  Edits a snapshot. `metrics` merges: a key sets a value (in the person's
  units), `null` removes it. A snapshot keeps at least one metric or photo.
  """
  def update(%{user_id: user_id} = context, id, params) do
    settings = Body.settings(context, user_id)

    with %{} = snapshot <- Body.get_snapshot(context, user_id, id) || {:error, :not_found},
         {:ok, attrs} <- update_attrs(context, snapshot, params, settings),
         {:ok, updated} <- Body.update_snapshot(context, user_id, snapshot.id, attrs) do
      if Map.has_key?(attrs, :visibility),
        do: remember_visibility(context, user_id, settings, attrs.visibility)

      {:ok, present(context, updated)}
    end
  end

  defp update_attrs(context, snapshot, params, settings) do
    with {:ok, units} <- units(params, settings),
         {:ok, attrs} <- update_metrics(context, snapshot, params, units),
         {:ok, attrs} <- update_field(attrs, params, "visibility", &Body.validate_visibility/1),
         {:ok, attrs} <- update_notes(attrs, params),
         {:ok, attrs} <- update_time(attrs, params) do
      {:ok, attrs}
    end
  end

  defp update_metrics(context, snapshot, params, units) do
    case Map.fetch(stringify(params), "metrics") do
      :error ->
        {:ok, %{}}

      {:ok, changes} ->
        with {:ok, changes} <- metrics(changes, units) do
          merged = snapshot.metrics |> Body.clean_metrics() |> Body.merge_metrics(changes)
          photos = Body.list_photos(context, [snapshot.id])

          with :ok <- Body.validate_content(merged, length(photos)),
               do: {:ok, %{metrics: merged}}
        end
    end
  end

  defp update_field(attrs, params, key, validate) do
    case Map.fetch(stringify(params), key) do
      :error ->
        {:ok, attrs}

      {:ok, value} ->
        with :ok <- validate.(value),
             do: {:ok, Map.put(attrs, String.to_existing_atom(key), value)}
    end
  end

  defp update_notes(attrs, params) do
    case Map.fetch(stringify(params), "notes") do
      :error ->
        {:ok, attrs}

      {:ok, notes} ->
        with {:ok, notes} <- Body.normalize_notes(notes), do: {:ok, Map.put(attrs, :notes, notes)}
    end
  end

  defp update_time(attrs, params) do
    params = stringify(params)

    with {:ok, attrs} <-
           (case Map.fetch(params, "taken_at") do
              :error ->
                {:ok, attrs}

              {:ok, value} ->
                with {:ok, at} <- taken_at(value, nil), do: {:ok, Map.put(attrs, :taken_at, at)}
            end) do
      case Map.fetch(params, "taken_tz") do
        :error ->
          {:ok, attrs}

        {:ok, value} ->
          with {:ok, tz} <- taken_tz(value), do: {:ok, Map.put(attrs, :taken_tz, tz)}
      end
    end
  end

  def delete(%{user_id: user_id} = context, id) do
    with %{} = snapshot <- Body.get_snapshot(context, user_id, id) || {:error, :not_found} do
      cleanup(context, snapshot)
      :ok
    end
  end

  defp cleanup(%{user_id: user_id} = context, snapshot) do
    photos = Body.list_photos(context, [snapshot.id])
    {:ok, _deleted} = Body.delete_snapshot(context, user_id, snapshot.id)
    BodyPhotos.release(context, photos)
  end

  @doc """
  One metric over a range (`1m`, `3m`, `1y`, `all`): points with smoothed
  values and a trend word, as the display rules allow.
  """
  def series(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    metric = param(params, "metric")
    range = param(params, "range") || "3m"

    with true <- Body.known_metric?(metric || "") || {:error, :unknown_metric},
         {:ok, since} <- Body.range_since(range, now) do
      settings = Body.settings(context, user_id)
      points = Body.list_metric_points(context, user_id, metric, since)
      shown = Body.shown_series(metric, points, settings)

      {:ok,
       Map.merge(shown, %{
         metric: metric,
         range: range,
         units: settings.units,
         unit: Body.metric_unit(metric, settings.units)
       })}
    end
  end

  @doc "Two snapshots side by side, with the change of every metric both hold."
  def compare(%{user_id: user_id} = context, params) do
    with %{} = from <-
           Body.get_snapshot(context, user_id, param(params, "from") || "") ||
             {:error, :not_found},
         %{} = to <-
           Body.get_snapshot(context, user_id, param(params, "to") || "") || {:error, :not_found} do
      settings = Body.settings(context, user_id)

      {older, newer} =
        if DateTime.compare(from.taken_at, to.taken_at) == :gt, do: {to, from}, else: {from, to}

      photos = photos_by_snapshot(context, [older, newer])

      {:ok,
       %{
         from: BodyPresenter.snapshot(older, Map.get(photos, older.id, []), settings),
         to: BodyPresenter.snapshot(newer, Map.get(photos, newer.id, []), settings),
         deltas: Body.shown_deltas(older.metrics, newer.metrics, settings),
         units: settings.units
       }}
    end
  end

  @doc "Snapshots for the journal feed (owner only), as feed entries."
  def feed_entries(%{user_id: user_id} = context, bound, limit) do
    settings = Body.settings(context, user_id)

    if Body.section_on?(settings, "body") do
      rows = Body.list_snapshots(context, user_id, bound: bound, limit: limit)
      photos = photos_by_snapshot(context, rows)

      rows
      |> BodyPresenter.snapshots(photos, settings)
      |> Enum.map(fn entry ->
        Map.merge(entry, %{
          organization_id: nil,
          journal_visibility:
            if(Body.shared?(entry.visibility), do: "coach_can_view", else: "private")
        })
      end)
    else
      []
    end
  end

  defp present(context, snapshot) do
    settings = Body.settings(context, snapshot.user_id)
    BodyPresenter.snapshot(snapshot, Body.list_photos(context, [snapshot.id]), settings)
  end

  defp photos_by_snapshot(_context, []), do: %{}

  defp photos_by_snapshot(context, snapshots),
    do:
      context |> Body.list_photos(Enum.map(snapshots, & &1.id)) |> Enum.group_by(& &1.snapshot_id)

  defp remember_visibility(_context, _user_id, %{default_visibility: same}, same), do: :ok

  defp remember_visibility(context, user_id, _settings, visibility) do
    {:ok, _settings} = Body.put_settings(context, user_id, %{default_visibility: visibility})
    :ok
  end

  defp units(params, settings) do
    case param(params, "units") do
      nil -> {:ok, settings.units}
      units -> if units in Body.unit_systems(), do: {:ok, units}, else: {:error, :invalid_units}
    end
  end

  defp metrics(metrics, units) when is_map(metrics) do
    case Body.validate_metrics(metrics, units) do
      {:ok, canonical} -> {:ok, canonical}
      {:error, :invalid_metric, details} -> {:error, :invalid_metric, details}
    end
  end

  defp metrics(_metrics, _units), do: {:error, :invalid_metric, %{reason: "not_an_object"}}

  defp visibility(nil, settings), do: {:ok, settings.default_visibility}

  defp visibility(visibility, _settings) do
    with :ok <- Body.validate_visibility(visibility), do: {:ok, visibility}
  end

  defp taken_at(nil, %DateTime{} = now), do: {:ok, now}
  defp taken_at(%DateTime{} = at, _now), do: {:ok, at}

  defp taken_at(value, _now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _invalid -> {:error, :invalid_taken_at}
    end
  end

  defp taken_at(_value, _now), do: {:error, :invalid_taken_at}

  defp taken_tz(nil), do: {:ok, "UTC"}

  defp taken_tz(zone) when is_binary(zone) do
    case DateTime.now(zone) do
      {:ok, _now} -> {:ok, zone}
      {:error, _reason} -> {:error, :invalid_timezone}
    end
  end

  defp taken_tz(_zone), do: {:error, :invalid_timezone}

  defp stringify(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp param(params, key), do: Map.get(stringify(params), key)
end
