defmodule Palee.Workers.ClassSeriesExtensionJob do
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [period: 86_400]

  alias Palee.Application.{DayWorkouts, ResolveJobTenantContext}
  alias Palee.Scheduling

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "series_id" => series_id,
          "horizon" => horizon
        }
      }) do
    with {:ok, context} <-
           ResolveJobTenantContext.call(organization_id, __MODULE__ |> Atom.to_string()),
         {:ok, horizon} <- Date.from_iso8601(horizon),
         {:ok, series} <- Scheduling.extend_class_series(context, series_id, horizon),
         # ADR-230: new occurrences on days with a day WOD inherit it.
         {:ok, _changed} <-
           DayWorkouts.reconcile_range(context, series.starts_on, series.materialized_through) do
      :ok
    end
  end

  def perform(%Oban.Job{}), do: {:error, :missing_organization_scope}
end
