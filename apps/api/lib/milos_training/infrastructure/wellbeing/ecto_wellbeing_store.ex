defmodule MilosTraining.Infrastructure.Wellbeing.EctoWellbeingStore do
  @behaviour MilosTraining.Wellbeing.Ports.WellbeingStore

  import Ecto.Query

  alias Ecto.Multi
  alias MilosTraining.Repo
  alias MilosTraining.Wellbeing.{InjuryReport, InjuryStatusEvent}

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
    case Repo.get(InjuryReport, injury_report_id) do
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
  def get_injury_for_user(user_id, injury_report_id) do
    InjuryReport
    |> where([injury], injury.id == ^injury_report_id and injury.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      %InjuryReport{} = injury_report -> normalize_injury(injury_report)
    end
  end

  @impl true
  def list_injuries_for_user(user_id) do
    InjuryReport
    |> where([injury], injury.user_id == ^user_id)
    |> where([injury], injury.visibility == "user_and_admin")
    |> order_by([injury], desc: injury.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_injury/1)
  end

  @impl true
  def list_injuries(filters) do
    filters = string_key_map(filters || %{})

    InjuryReport
    |> maybe_filter(:status, filters["status"])
    |> maybe_filter(:severity, filters["severity"])
    |> maybe_filter(:body_area, filters["body_area"])
    |> order_by([injury], desc: injury.inserted_at)
    |> offset(^parse_offset(filters["offset"]))
    |> limit(^parse_limit(filters["limit"]))
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
      inserted_at: injury_report.inserted_at,
      updated_at: injury_report.updated_at
    }
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
    |> where([injury], injury.status == ^status)
    |> where([injury], injury.inserted_at >= ^since)
    |> Repo.aggregate(:count)
  end

  defp count_injuries_by(field, since) do
    InjuryReport
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
end
