defmodule MilosTraining.Application.ClientBody do
  @moduledoc """
  `GET /api/org/:slug/staff/clients/:user_id/body` (ADR-158): a coach reads
  the body snapshots a client shared, in the coach's tenant session.

  - Only a coach of the gym who may see the client's health data
    (`view_health`: their own clients, every client for a head coach), and
    only while the client is an active member there.
  - Only snapshots shared with the coach (`coach_numbers`, `coach_full`);
    nothing tells the coach that private ones exist. Row security admits
    the same and nothing else.
  - Photos only on `coach_full` and only while the client's body-photo
    consent is active; withdrawing it hides them at once.
  - The client's display choice applies: under `trend` or `hidden` a coach
    never sees weight or body-fat numbers either. Notes stay the client's.
  - `series` gives one metric over a range from the shared snapshots, under
    the same display rules (under `trend`: the word and a 0..1 shape only).
  - Every read is written to the client's access log; the client sees it
    (no notification).
  """

  alias MilosTraining.Application.{AuthorizeClientAccess, BodyPresenter}
  alias MilosTraining.{Body, Organizations}

  def list(context, client_id, params) do
    with {:ok, client_id} <- authorize(context, client_id),
         {:ok, cursor} <- Body.decode_cursor(param(params, "cursor")) do
      limit = Body.page_limit(param(params, "limit"))

      Body.with_context(context, fn ->
        settings = Body.settings(context, client_id)

        rows =
          Body.list_snapshots(context, client_id,
            shared_only: true,
            cursor: cursor,
            limit: limit + 1
          )

        {shown, next_cursor} = Body.page(rows, limit)
        {snapshots, photos_shown?} = present(context, client_id, shown, settings)
        log(context, client_id, "list", shown, photos_shown?)

        {:ok, %{snapshots: snapshots, next_cursor: next_cursor}}
      end)
    end
  end

  def show(context, client_id, snapshot_id) do
    with {:ok, client_id} <- authorize(context, client_id) do
      Body.with_context(context, fn ->
        case Body.get_snapshot(context, client_id, snapshot_id, shared_only: true) do
          nil ->
            {:error, :not_found}

          snapshot ->
            settings = Body.settings(context, client_id)
            {[presented], photos_shown?} = present(context, client_id, [snapshot], settings)
            log(context, client_id, "snapshot", [snapshot], photos_shown?)
            {:ok, presented}
        end
      end)
    end
  end

  @doc """
  One metric of a client over a range, from the snapshots they shared, as
  the client's display choice allows: numbers, the trend word with a
  normalized shape (no values), or nothing. The read is logged.
  """
  def series(context, client_id, params, now \\ DateTime.utc_now()) do
    metric = param(params, "metric")
    range = param(params, "range") || "3m"

    with {:ok, client_id} <- authorize(context, client_id),
         true <- Body.known_metric?(metric || "") || {:error, :unknown_metric},
         {:ok, since} <- Body.range_since(range, now) do
      Body.with_context(context, fn ->
        settings = Body.settings(context, client_id)
        points = Body.list_metric_points(context, client_id, metric, since, shared_only: true)
        shown = Body.shown_series(metric, points, settings)

        read =
          if shown.display == "hidden",
            do: [],
            else: points |> Enum.map(&%{id: &1.snapshot_id}) |> Enum.uniq()

        log(context, client_id, "series", read, false)

        {:ok,
         Map.merge(shown, %{
           metric: metric,
           range: range,
           units: settings.units,
           unit: Body.metric_unit(metric, settings.units)
         })}
      end)
    end
  end

  defp present(context, client_id, snapshots, settings) do
    consent? = snapshots != [] and Body.photos_consented?(context, client_id)

    with_photos =
      snapshots
      |> Enum.filter(&Body.photos_visible_to_coach?(&1.visibility, consent?))
      |> Enum.map(& &1.id)

    photos =
      context
      |> Body.list_photos(with_photos)
      |> Enum.filter(&(&1.snapshot_id in with_photos))
      |> Enum.group_by(& &1.snapshot_id)

    {BodyPresenter.snapshots(snapshots, photos, settings, audience: :coach), photos != %{}}
  end

  defp log(context, client_id, subject, snapshots, photos_shown?) do
    Body.record_access(context, %{
      organization_id: context.organization_id,
      user_id: client_id,
      reader_user_id: context.user_id,
      subject: subject,
      snapshot_ids: Enum.map(snapshots, & &1.id),
      photos_shown: photos_shown?
    })
  end

  defp authorize(%{organization_id: organization_id} = context, client_id)
       when is_binary(organization_id) do
    with {:ok, client_id} <- cast(client_id),
         true <- Organizations.acting_user_coaches?(context) || {:error, :forbidden},
         true <-
           client_id in Organizations.list_active_membership_user_ids(context) ||
             {:error, :not_found},
         :ok <- AuthorizeClientAccess.call(context, :view_health, client_id) do
      {:ok, client_id}
    end
  end

  defp authorize(_context, _client_id), do: {:error, :organization_context_required}

  defp cast(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp param(params, key),
    do: Map.get(params, key) || Map.get(params, String.to_existing_atom(key))
end
