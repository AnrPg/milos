defmodule MilosTraining.Workers.CoachingReplyOverdueJob do
  @moduledoc """
  Hourly (ADR-098): tells a gym's staff once about each client message whose
  promised reply time has passed.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 1_800]

  alias MilosTraining.Application.ListCoachingReplyQueue
  alias MilosTraining.{Coaching, Notifications, Organizations}
  alias MilosTraining.Organizations.OrganizationStore

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    OrganizationStore.list_organizations()
    |> Enum.filter(fn %{organization: organization} -> organization.status == :active end)
    |> Enum.each(fn %{organization: organization} -> alert(organization.id, now) end)

    :ok
  end

  @doc false
  def alert(organization_id, now) do
    {:ok, context} =
      Organizations.resolve_system_tenant_context(organization_id, :coaching_reply_overdue, %{
        service: __MODULE__
      })

    overdue = context |> ListCoachingReplyQueue.call(now) |> Enum.filter(& &1.overdue)
    alerted = Coaching.alerted_message_ids(context, Enum.map(overdue, & &1.message_id))
    staff_ids = Organizations.list_staff_user_ids(organization_id)

    overdue
    |> Enum.reject(&(&1.message_id in alerted))
    |> Enum.each(fn item ->
      Enum.each(staff_ids, fn staff_id ->
        Notifications.process_event("coaching_reply_overdue", %{
          user_id: staff_id,
          thread_id: item.thread_id,
          client_nickname: item.client_nickname,
          due_at: item.due_at
        })
      end)

      Coaching.record_reply_alert(context, %{
        message_id: item.message_id,
        thread_id: item.thread_id,
        notified_at: now
      })
    end)
  end
end
