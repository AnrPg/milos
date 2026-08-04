defmodule MilosTraining.Workers.ClassSeriesExtensionJob do
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [period: 86_400]

  alias MilosTraining.Application.ResolveJobTenantContext
  alias MilosTraining.Scheduling

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
         {:ok, _series} <- Scheduling.extend_class_series(context, series_id, horizon) do
      :ok
    end
  end

  def perform(%Oban.Job{}), do: {:error, :missing_organization_scope}
end
