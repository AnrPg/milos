defmodule MilosTraining.Infrastructure.Execution.EctoClassTimerStore do
  @behaviour MilosTraining.Execution.Ports.ClassTimerStore

  import Ecto.Query

  alias MilosTraining.Execution.ClassTimer
  alias MilosTraining.Repo

  @impl true
  def get_class_timer(%{organization_id: organization_id}, scheduled_class_id) do
    ClassTimer
    |> where(
      [timer],
      timer.scheduled_class_id == ^scheduled_class_id and
        timer.organization_id == ^organization_id
    )
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def save_class_timer(
        %{organization_id: organization_id} = context,
        scheduled_class_id,
        attrs,
        expected_version
      ) do
    existing =
      ClassTimer
      |> where(
        [timer],
        timer.scheduled_class_id == ^scheduled_class_id and
          timer.organization_id == ^organization_id
      )
      |> Repo.one()

    attrs =
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:scheduled_class_id, scheduled_class_id)

    cond do
      existing && expected_version && existing.lock_version != expected_version ->
        {:error, :stale_class_timer}

      existing ->
        existing
        |> ClassTimer.changeset(attrs)
        |> Repo.update(stale_error_field: :lock_version)
        |> result(context, scheduled_class_id)

      expected_version not in [nil, 1] ->
        {:error, :stale_class_timer}

      true ->
        %ClassTimer{}
        |> ClassTimer.changeset(attrs)
        |> Repo.insert()
        |> result(context, scheduled_class_id)
    end
  end

  defp result({:ok, timer}, _context, _id), do: {:ok, normalize(timer)}

  defp result({:error, %Ecto.Changeset{errors: errors} = changeset}, _context, _id) do
    if Keyword.has_key?(errors, :lock_version) or Keyword.has_key?(errors, :scheduled_class_id),
      do: {:error, :stale_class_timer},
      else: {:error, changeset}
  end

  defp normalize(nil), do: nil

  defp normalize(%ClassTimer{} = timer) do
    %{
      id: timer.id,
      organization_id: timer.organization_id,
      scheduled_class_id: timer.scheduled_class_id,
      status: timer.status,
      current_segment_index: timer.current_segment_index,
      segment_started_at_utc: timer.segment_started_at_utc,
      paused_elapsed_ms: timer.paused_elapsed_ms,
      duration_adjustments: timer.duration_adjustments || %{},
      timer_preset: timer.timer_preset,
      controlled_by_id: timer.controlled_by_id,
      lock_version: timer.lock_version,
      updated_at: timer.updated_at
    }
  end
end
