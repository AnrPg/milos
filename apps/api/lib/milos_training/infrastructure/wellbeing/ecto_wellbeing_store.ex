defmodule MilosTraining.Infrastructure.Wellbeing.EctoWellbeingStore do
  @behaviour MilosTraining.Wellbeing.Ports.WellbeingStore

  import Ecto.Query

  alias Ecto.Multi
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Repo
  alias MilosTraining.Infrastructure.Journal.FeedBound
  alias MilosTraining.Wellbeing.{CheckIn, InjuryReport, InjuryStatusEvent}
  alias MilosTraining.Wellbeing.Domain.CheckInQuestions

  @impl true
  def report_injury(user_id, actor_id, actor_role, params) do
    report_params =
      params
      |> string_key_map()
      |> Map.merge(%{
        "user_id" => user_id,
        "reported_by_id" => actor_id,
        "reported_by_role" => actor_role,
        "status" => "active"
      })

    Multi.new()
    |> Multi.insert(:injury_report, InjuryReport.changeset(%InjuryReport{}, report_params))
    |> Multi.insert(:status_event, fn %{injury_report: injury_report} ->
      InjuryStatusEvent.changeset(%InjuryStatusEvent{}, %{
        injury_report_id: injury_report.id,
        actor_id: actor_id,
        event_type: "reported",
        occurred_at: DateTime.utc_now(),
        payload: %{
          body_area: injury_report.body_area,
          severity: injury_report.severity,
          tags: injury_report.tags || []
        }
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{injury_report: injury_report}} -> {:ok, normalize_injury(injury_report)}
      {:error, _step, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @impl true
  def mark_healed(injury_report_id, actor_id, healed_on) do
    case InjuryReport |> scoped_to_owner_or_tenant() |> Repo.get(injury_report_id) do
      nil ->
        {:error, :not_found}

      %InjuryReport{} = injury_report ->
        healed_on = healed_on || Date.utc_today()

        with :ok <- validate_healing(injury_report, healed_on) do
          Multi.new()
          |> Multi.update(
            :injury_report,
            InjuryReport.changeset(injury_report, %{
              status: "healed",
              healed_on: healed_on
            })
          )
          |> Multi.insert(:status_event, fn %{injury_report: updated_report} ->
            InjuryStatusEvent.changeset(%InjuryStatusEvent{}, %{
              injury_report_id: updated_report.id,
              actor_id: actor_id,
              event_type: "marked_healed",
              occurred_at: DateTime.utc_now(),
              payload: %{healed_on: healed_on}
            })
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{injury_report: updated_report}} -> {:ok, normalize_injury(updated_report)}
            {:error, _step, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
            {:error, _step, reason, _changes} -> {:error, reason}
          end
        end
    end
  end

  @impl true
  def update_injury(injury_report_id, actor_id, build) when is_function(build, 1) do
    case InjuryReport |> scoped_to_owner_or_tenant() |> Repo.get(injury_report_id) do
      nil ->
        {:error, :not_found}

      %InjuryReport{} = injury_report ->
        with {:ok, attrs, payload} <- build.(normalize_injury(injury_report)) do
          injury_report
          |> InjuryReport.changeset(attrs)
          |> record_event(actor_id, "updated", payload)
        end
    end
  end

  @impl true
  def reopen_injury(injury_report_id, actor_id) do
    case InjuryReport |> scoped_to_owner_or_tenant() |> Repo.get(injury_report_id) do
      nil ->
        {:error, :not_found}

      %InjuryReport{status: "active"} ->
        {:error, :injury_already_active}

      %InjuryReport{} = injury_report ->
        injury_report
        |> InjuryReport.changeset(%{status: "active", healed_on: nil})
        |> record_event(actor_id, "reopened", %{"healed_on" => injury_report.healed_on})
    end
  end

  defp record_event(changeset, actor_id, event_type, payload) do
    Multi.new()
    |> Multi.update(:injury_report, changeset, force: true)
    |> Multi.insert(:status_event, fn %{injury_report: updated_report} ->
      InjuryStatusEvent.changeset(%InjuryStatusEvent{}, %{
        injury_report_id: updated_report.id,
        actor_id: actor_id,
        event_type: event_type,
        occurred_at: DateTime.utc_now(),
        payload: payload
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{injury_report: updated_report}} ->
        {:ok, updated_report |> Repo.preload(:events, force: true) |> normalize_injury()}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @impl true
  def get_injury_for_user(user_id, injury_report_id) do
    InjuryReport
    |> scoped_to_owner_or_tenant()
    |> where([injury], injury.id == ^injury_report_id and injury.user_id == ^user_id)
    |> where([injury], injury.visibility == "user_and_admin")
    |> preload(:events)
    |> Repo.one()
    |> case do
      nil -> nil
      %InjuryReport{} = injury_report -> normalize_injury(injury_report)
    end
  end

  @impl true
  def list_injuries_for_user(user_id) do
    InjuryReport
    |> scoped_to_owner_or_tenant()
    |> where([injury], injury.user_id == ^user_id)
    |> where([injury], injury.visibility == "user_and_admin")
    |> order_by([injury], desc: injury.inserted_at)
    |> preload(:events)
    |> Repo.all()
    |> Enum.map(&normalize_injury/1)
  end

  # ADR-124 staff safety warnings: organization-provenance only. The tenant
  # predicate (not the owner-or-tenant disjunction) keeps the acting staff
  # member's own injuries and every personal self-report out of the result.
  @impl true
  def list_active_tenant_injuries_for_users(user_ids) when is_list(user_ids) do
    InjuryReport
    |> scoped_to_tenant()
    |> where([injury], injury.user_id in ^user_ids and injury.status == "active")
    |> order_by([injury], desc: injury.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_injury/1)
  end

  @impl true
  def list_injuries(filters) do
    filters = string_key_map(filters || %{})

    InjuryReport
    |> scoped_to_tenant()
    |> maybe_filter(:status, filters["status"])
    |> maybe_filter(:severity, filters["severity"])
    |> maybe_filter(:body_area, filters["body_area"])
    |> order_by([injury], desc: injury.inserted_at)
    |> offset(^parse_offset(filters["offset"]))
    |> limit(^parse_limit(filters["limit"]))
    |> preload(:events)
    |> Repo.all()
    |> Enum.map(&normalize_injury/1)
  end

  @impl true
  def injury_summary(filters) do
    filters = string_key_map(filters || %{})
    since = summary_since(filters["days"])

    %{
      since: since,
      total: count_injuries(since),
      active_count: count_status("active", since),
      healed_count: count_status("healed", since),
      by_body_area: count_injuries_by(:body_area, since),
      by_severity: count_injuries_by(:severity, since),
      by_status: count_injuries_by(:status, since)
    }
  end

  defp maybe_filter(query, _field, value) when value in [nil, "", "all"], do: query

  defp maybe_filter(query, field, value) do
    where(query, [record], field(record, ^field) == ^value)
  end

  defp normalize_injury(%InjuryReport{} = injury_report) do
    %{
      id: injury_report.id,
      organization_id: injury_report.organization_id,
      user_id: injury_report.user_id,
      reported_by_id: injury_report.reported_by_id,
      reported_by_role: injury_report.reported_by_role,
      body_area: injury_report.body_area,
      severity: injury_report.severity,
      status: injury_report.status,
      started_on: injury_report.started_on,
      healed_on: injury_report.healed_on,
      description: injury_report.description,
      training_limitations: injury_report.training_limitations,
      tags: injury_report.tags || [],
      visibility: injury_report.visibility,
      params: injury_report.params || %{},
      events: normalize_events(injury_report.events),
      inserted_at: injury_report.inserted_at,
      updated_at: injury_report.updated_at
    }
  end

  # The injury's timeline (ADR-140 §3), oldest first; empty when not loaded.
  defp normalize_events(%Ecto.Association.NotLoaded{}), do: []

  defp normalize_events(events) do
    events
    |> Enum.sort_by(& &1.occurred_at, DateTime)
    |> Enum.map(
      &%{
        id: &1.id,
        event_type: &1.event_type,
        actor_id: &1.actor_id,
        occurred_at: &1.occurred_at,
        payload: &1.payload || %{}
      }
    )
  end

  defp parse_limit(nil), do: 100
  defp parse_limit(limit) when is_integer(limit), do: limit |> min(250) |> max(1)

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> parse_limit(value)
      _ -> 100
    end
  end

  defp parse_offset(nil), do: 0
  defp parse_offset(offset) when is_integer(offset), do: max(offset, 0)

  defp parse_offset(offset) when is_binary(offset) do
    case Integer.parse(offset) do
      {value, ""} -> parse_offset(value)
      _ -> 0
    end
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp count_injuries(since) do
    InjuryReport
    |> scoped_to_tenant()
    |> where([injury], injury.inserted_at >= ^since)
    |> Repo.aggregate(:count)
  end

  defp validate_healing(%InjuryReport{status: "healed"}, _healed_on),
    do: {:error, :injury_already_healed}

  defp validate_healing(%InjuryReport{started_on: %Date{} = started_on}, %Date{} = healed_on) do
    if Date.compare(healed_on, started_on) == :lt do
      {:error, :injury_healed_before_started}
    else
      :ok
    end
  end

  defp validate_healing(_injury_report, _healed_on), do: :ok

  defp count_status(status, since) do
    InjuryReport
    |> scoped_to_tenant()
    |> where([injury], injury.status == ^status)
    |> where([injury], injury.inserted_at >= ^since)
    |> Repo.aggregate(:count)
  end

  defp count_injuries_by(field, since) do
    InjuryReport
    |> scoped_to_tenant()
    |> where([injury], injury.inserted_at >= ^since)
    |> group_by([injury], field(injury, ^field))
    |> select([injury], {field(injury, ^field), count(injury.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp summary_since(nil), do: DateTime.add(DateTime.utc_now(), -30 * 86_400, :second)

  defp summary_since(days) when is_integer(days) do
    DateTime.add(DateTime.utc_now(), -max(days, 1) * 86_400, :second)
  end

  defp summary_since(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} -> summary_since(value)
      _ -> summary_since(nil)
    end
  end

  # Organization-scoped reads: the admin injury list and the analytics summary
  # describe ONE organization, so they must never widen to the acting admin's
  # own reports filed elsewhere. Fails closed with no organization open rather
  # than reading across every tenant.
  defp scoped_to_tenant(query) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        where(query, [row], row.organization_id == ^organization_id)

      _missing_scope ->
        where(query, [row], false)
    end
  end

  # Owner-scoped reads: personal injury records deliberately follow the member
  # across every organization they belong to (product decision, 2026-08-07 -
  # see F-28). The disjunction is intentional here: `user_id` matches the
  # member's own records regardless of which gym they were filed in, while
  # `organization_id` covers an admin reading a member's dossier within their
  # own tenant. Do NOT reuse this for organization-scoped listings.
  defp scoped_to_owner_or_tenant(query) do
    user_id = RepoContext.current_setting("app.user_id")
    organization_id = RepoContext.current_setting("app.organization_id")

    cond do
      is_binary(user_id) and is_binary(organization_id) ->
        where(query, [row], row.user_id == ^user_id or row.organization_id == ^organization_id)

      is_binary(user_id) ->
        where(query, [row], row.user_id == ^user_id)

      is_binary(organization_id) ->
        where(query, [row], row.organization_id == ^organization_id)

      true ->
        query
    end
  end

  @impl true
  def create_check_in(attrs) do
    attrs
    |> CheckIn.create_changeset()
    |> Repo.insert()
    |> normalize_check_in_result()
  end

  @impl true
  def delete_check_in(id, user_id, now) do
    case live_check_in(id, user_id) do
      nil ->
        {:error, :not_found}

      check_in ->
        check_in |> CheckIn.delete_changeset(now) |> Repo.update() |> normalize_check_in_result()
    end
  end

  @impl true
  def get_check_in_for_user(id, user_id) do
    case live_check_in(id, user_id) do
      nil -> nil
      check_in -> normalize_check_in(check_in)
    end
  end

  @impl true
  def set_check_in_visibility(id, user_id, rung) do
    case live_check_in(id, user_id) do
      nil ->
        {:error, :not_found}

      check_in ->
        check_in
        |> CheckIn.visibility_changeset(rung)
        |> Repo.update()
        |> normalize_check_in_result()
    end
  end

  @impl true
  def move_check_ins(user_id, from, to) do
    {count, _rows} =
      CheckIn
      |> where([check_in], check_in.user_id == ^user_id and is_nil(check_in.deleted_at))
      |> where([check_in], not is_nil(check_in.organization_id))
      |> where([check_in], check_in.journal_visibility in ^from)
      |> Repo.update_all(set: [journal_visibility: to, updated_at: DateTime.utc_now()])

    count
  end

  @impl true
  def list_check_in_items(user_id, bound, limit) do
    CheckIn
    |> where([check_in], check_in.user_id == ^user_id and is_nil(check_in.deleted_at))
    |> FeedBound.apply(:recorded_at, bound)
    |> order_by([check_in], desc: check_in.recorded_at, desc: check_in.id)
    |> limit(^limit)
    |> preload(:answers)
    |> Repo.all()
    |> Enum.map(&normalize_check_in/1)
  end

  # The timeline of ADR-140 §2: every live submission in [from, to), oldest
  # first, so each question draws one line with a point per submission.
  @impl true
  def list_check_ins_between(user_id, %DateTime{} = from, %DateTime{} = to) do
    CheckIn
    |> where([check_in], check_in.user_id == ^user_id and is_nil(check_in.deleted_at))
    |> where([check_in], check_in.recorded_at >= ^from and check_in.recorded_at < ^to)
    |> order_by([check_in], asc: check_in.recorded_at, asc: check_in.id)
    |> preload(:answers)
    |> Repo.all()
    |> Enum.map(&normalize_check_in/1)
  end

  # Coach tenant session: RLS admits only this gym's check-ins whose rung
  # reaches the coach (and their answers, through the parent); the
  # predicates below make the intent explicit.
  @impl true
  def list_coach_visible_check_ins(user_id, organization_id) do
    CheckIn
    |> where([check_in], check_in.user_id == ^user_id)
    |> where([check_in], check_in.organization_id == ^organization_id)
    |> where([check_in], is_nil(check_in.deleted_at))
    |> where(
      [check_in],
      fragment("milos_journal_visibility_reaches_coach(?)", check_in.journal_visibility)
    )
    |> order_by([check_in], desc: check_in.recorded_at, desc: check_in.id)
    |> preload(:answers)
    |> Repo.all()
    |> Enum.map(&normalize_check_in/1)
  end

  defp live_check_in(id, user_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        CheckIn
        |> where([check_in], check_in.id == ^id and check_in.user_id == ^user_id)
        |> where([check_in], is_nil(check_in.deleted_at))
        |> preload(:answers)
        |> Repo.one()

      :error ->
        nil
    end
  end

  defp normalize_check_in_result({:ok, check_in}), do: {:ok, normalize_check_in(check_in)}
  defp normalize_check_in_result(error), do: error

  defp normalize_check_in(%CheckIn{} = check_in) do
    answers =
      check_in.answers
      |> Enum.map(&Map.take(&1, [:question_key, :value, :note]))
      |> Enum.sort_by(&CheckInQuestions.order(&1.question_key))

    check_in
    |> Map.from_struct()
    |> Map.drop([:__meta__, :deleted_at])
    |> Map.put(:answers, answers)
  end
end
