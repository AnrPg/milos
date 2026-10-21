defmodule Palee.Workers.SuggestWorkoutIconJob do
  @moduledoc "Background icon suggestion for a published workout (ADR-136)."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args], keys: [:workout_id]]

  alias Palee.Application.SuggestWorkoutIcon
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id, "workout_id" => workout_id}
      }) do
    case Organizations.resolve_system_tenant_context(organization_id, :workout_icon_suggestion, %{
           service: __MODULE__
         }) do
      {:ok, context} ->
        {:ok, _outcome} = SuggestWorkoutIcon.call(context, workout_id)
        :ok

      {:error, reason} ->
        {:cancel, reason}
    end
  end
end
