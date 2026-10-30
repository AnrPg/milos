defmodule Palee.Infrastructure.Partners.EctoSuggestionStore do
  @moduledoc """
  Ecto adapter of the «Κλείστε μαζί» suggestions store (ADR-280 §4,
  migration `20270325200000_partner_suggestions`). The pair, blocked and
  shared-box reads go through SECURITY DEFINER functions that answer only for
  an active match of the session user; the counters are written only through
  `palee_partner_suggestion_count/1`.
  """

  @behaviour Palee.Partners.Ports.SuggestionStore

  import Ecto.Query

  alias Palee.Partners.SuggestionFeedback
  alias Palee.Repo

  @impl true
  def pair(_context, match_id) do
    case Ecto.UUID.dump(match_id || "") do
      {:ok, id} ->
        "SELECT user_id, level, times, latitude, longitude FROM palee_partner_suggestion_pair($1::uuid)"
        |> query([id])
        |> Enum.map(fn [user_id, level, times, latitude, longitude] ->
          %{
            user_id: Ecto.UUID.load!(user_id),
            level: level,
            times: times || [],
            point: point(latitude, longitude)
          }
        end)

      :error ->
        []
    end
  end

  @impl true
  def blocked(_context, match_id, ids) do
    "SELECT palee_partner_suggestion_blocked($1::uuid, $2::uuid[])"
    |> query([Ecto.UUID.dump!(match_id), Enum.map(ids, &Ecto.UUID.dump!/1)])
    |> Enum.map(fn [id] -> Ecto.UUID.load!(id) end)
  end

  @impl true
  def shared_organizations(_context, a, b) do
    "SELECT palee_partner_shared_organizations($1::uuid, $2::uuid)"
    |> query([Ecto.UUID.dump!(a), Ecto.UUID.dump!(b)])
    |> Enum.map(fn [id] -> Ecto.UUID.load!(id) end)
  end

  @impl true
  def put_feedback(_context, attrs, now) do
    attrs
    |> SuggestionFeedback.changeset()
    |> Repo.insert(
      on_conflict: [set: [reason: Map.get(attrs, :reason), updated_at: now]],
      conflict_target: [:user_id, :match_id, :suggestion_key],
      returning: true
    )
  end

  @impl true
  def count(_context, event) do
    query("SELECT palee_partner_suggestion_count($1::text)", [event])
    :ok
  end

  @impl true
  def list_counters(_context, %Date{} = since) do
    "SELECT day, event, count FROM partner_suggestion_events WHERE day >= $1 ORDER BY day, event"
    |> query([since])
    |> Enum.map(fn [day, event, count] -> %{day: day, event: event, count: count} end)
  end

  @impl true
  def feedback_reasons(_context, %DateTime{} = since) do
    SuggestionFeedback
    |> where([f], f.updated_at >= ^since)
    |> group_by([f], f.reason)
    |> select([f], {f.reason, count(f.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp query(sql, params), do: Repo.query!(sql, params).rows

  defp point(latitude, longitude) when is_number(latitude) and is_number(longitude),
    do: {latitude * 1.0, longitude * 1.0}

  defp point(_latitude, _longitude), do: nil
end
