defmodule Palee.Application.WellnessSummarySharing do
  @moduledoc """
  The coach's weekly wellness summary (ADR-160 §4, the M11 board answer).

  The member owns two toggles in Κοινοποίηση & ορατότητα: «Ευεξία ·
  εβδομαδιαία σύνοψη» and «Λιγούρες στη σύνοψη». Each is a grant record
  (granted, withdrawn), so the member and an audit can see since when a
  coach could read it.

  `GET /api/org/:slug/staff/clients/:user_id/wellness-summary`: a coach of
  the gym who may see the client's health data (`view_health`, their own
  clients or all for a head coach), while the client is active there, reads
  one week: nights at the sleep goal, water days on goal, days with meals
  logged; cravings (count and times only) only with the second toggle.
  Without the first toggle the coach learns only that nothing is shared.

  The coach's session never reads the member's wellness rows: after the
  coach seam and the active grant pass, the counts are computed in the
  member's own session from M11's day summaries, and only the counts leave.

  Every coach read is written to the member's wellness access log (who, in
  which gym, which week, whether craving moments were shown), which the
  member reads at `GET /api/me/wellness-summary-sharing/access-log`.
  """

  alias Palee.Application.AuthorizeClientAccess
  alias Palee.{Buddies, Identity, Organizations, Wellness}

  @access_log_limit 200

  # The member's toggles.

  def show(%{user_id: user_id} = context) do
    {:ok, context |> Buddies.list_summary_grants(user_id) |> Buddies.summary_toggles()}
  end

  def update(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    toggles = context |> Buddies.list_summary_grants(user_id) |> Buddies.summary_toggles()

    with {:ok, %{grant: grant, withdraw: withdraw}} <- Buddies.summary_changes(toggles, params) do
      Buddies.with_context(context, fn ->
        Enum.each(withdraw, &Buddies.withdraw_summary(context, user_id, &1, now))
        Enum.each(grant, &Buddies.grant_summary(context, user_id, &1, now))
      end)

      show(context)
    end
  end

  # The coach's read.

  def client_summary(context, client_id, params, now \\ DateTime.utc_now()) do
    with {:ok, client_id} <- authorize(context, client_id),
         {:ok, week_date} <- week_param(params) do
      member = %{user_id: client_id}
      toggles = member |> Buddies.list_summary_grants(client_id) |> Buddies.summary_toggles()
      {from, _to} = week = week(Buddies.settings(member, client_id).tz, week_date, now)
      summary = if toggles.wellness, do: compute(client_id, toggles, week)

      :ok =
        Buddies.record_wellness_access(context, %{
          organization_id: context.organization_id,
          user_id: client_id,
          reader_user_id: context.user_id,
          week_start: from,
          shared: toggles.wellness,
          cravings_shown: toggles.wellness and toggles.cravings
        })

      {:ok, %{shared: toggles.wellness, summary: summary}}
    end
  end

  @doc """
  The member's week as the coach sees it, computed in the member's own
  session: counts, and craving moments only with the second toggle.
  """
  def compute(client_id, toggles, {from, to} = week) do
    member = %{user_id: client_id}

    {week_line, cravings} =
      Wellness.with_context(member, fn ->
        prefs = Wellness.preferences(client_id)
        entries = Wellness.list_entries(client_id, from, to)
        cravings = Wellness.list_cravings(client_id, from, to)
        days = Wellness.summarize_days(Date.range(from, to), entries, cravings, %{}, prefs)
        {Wellness.week_line(days), if(toggles.cravings, do: cravings, else: [])}
      end)

    Buddies.coach_summary(week, toggles, week_line, cravings)
  end

  @doc "Which coaches read your weekly wellness summary, newest first."
  def access_log(%{user_id: user_id} = context) do
    entries = Buddies.list_wellness_access(context, user_id, @access_log_limit)

    readers =
      entries
      |> Enum.map(& &1.reader_user_id)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    gyms =
      entries
      |> Enum.map(& &1.organization_id)
      |> Enum.uniq()
      |> Map.new(fn id ->
        {id,
         case Organizations.get_by_id(id) do
           %{name: name} -> name
           _missing -> nil
         end}
      end)

    {:ok,
     Enum.map(entries, fn entry ->
       %{
         id: entry.id,
         read_at: entry.read_at,
         week_start: entry.week_start,
         shared: entry.shared,
         cravings_shown: entry.cravings_shown,
         reader: %{id: entry.reader_user_id, nickname: Map.get(readers, entry.reader_user_id)},
         organization: %{id: entry.organization_id, name: Map.get(gyms, entry.organization_id)}
       }
     end)}
  end

  # A given week (any date in it), or the last completed one.
  defp week(tz, nil, now), do: Buddies.previous_week(tz, now)

  defp week(_tz, %Date{} = date, _now) do
    from = Date.add(date, 1 - Date.day_of_week(date))
    {from, Date.add(from, 6)}
  end

  defp week_param(params) do
    case Map.get(params, "week", Map.get(params, :week)) do
      nil ->
        {:ok, nil}

      %Date{} = date ->
        {:ok, date}

      value when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          {:error, _reason} -> {:error, :invalid_date}
        end

      _other ->
        {:error, :invalid_date}
    end
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
end
