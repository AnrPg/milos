defmodule MilosTraining.Execution.ClassTimerStore do
  @moduledoc "Tenant-scoped persistence for coach-run class timers."
  @behaviour MilosTraining.Execution.Ports.ClassTimerStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :class_timer_store)

  @impl true
  def get_class_timer(context, scheduled_class_id),
    do: RepoContext.run(context, fn -> adapter().get_class_timer(context, scheduled_class_id) end)

  @impl true
  def save_class_timer(context, scheduled_class_id, attrs, expected_version),
    do:
      RepoContext.run(context, fn ->
        adapter().save_class_timer(context, scheduled_class_id, attrs, expected_version)
      end)
end
