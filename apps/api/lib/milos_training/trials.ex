defmodule MilosTraining.Trials do
  @moduledoc """
  The Trials bounded context (ADR-144, P2-M3): the owner's trial policy and
  the funnel of a person who is not a member trying a class, from the ask to
  the membership. Scheduling owns the seat (a booking of kind `trial`); this
  context owns why the seat exists and what became of it.

  Every function runs in the caller's scope: the box's for its policy and
  queue, the person's (`%{user_id: ...}`) for their own trials at any box.
  """

  alias MilosTraining.Trials.{TrialPolicy, TrialRequest, TrialStore}
  alias MilosTraining.Trials.Domain.{TrialLifecycle, TrialRules}

  @doc "The box's policy, or the default (trials off) when the owner never saved one."
  def policy(%{organization_id: organization_id} = context),
    do: TrialStore.get_policy(context) || TrialPolicy.default(organization_id)

  def update_policy(context, attrs) do
    attrs = Map.take(stringify(attrs), Enum.map(TrialPolicy.editable_fields(), &to_string/1))
    TrialStore.put_policy(context, attrs)
  end

  defdelegate insert_request(context, attrs), to: TrialStore
  defdelegate get_request(context, id), to: TrialStore
  defdelegate get_request_by_booking(context, booking_id), to: TrialStore
  defdelegate get_request_by_operation(context, user_id, operation_id), to: TrialStore
  defdelegate list_requests(context, filters), to: TrialStore
  defdelegate list_person_requests(context, user_id, opts), to: TrialStore
  defdelegate person_statuses(context, user_id), to: TrialStore
  defdelegate count_in_window(context, window, statuses), to: TrialStore
  defdelegate open_per_class(context, slot_ids), to: TrialStore
  defdelegate stats(context, since), to: TrialStore
  defdelegate with_box_lock(context, fun), to: TrialStore

  @doc """
  Moves a trial one lifecycle step and writes it, with any `extra` changes
  (such as the booking an accept created).
  """
  def transition(context, %TrialRequest{} = request, step, now, opts \\ [], extra \\ %{}) do
    with {:ok, changes} <- TrialLifecycle.transition(request, step, now, opts) do
      TrialStore.update_request(context, request, Map.merge(changes, extra))
    end
  end

  @doc "Records «Θέλω να γραφτώ» or «Όχι τώρα» on a trial (board 6 Q6)."
  def follow_up(context, %TrialRequest{} = request, field, now)
      when field in [:join_interest_at, :follow_up_dismissed_at],
      do: TrialStore.update_request(context, request, %{field => now})

  defdelegate check(policy, facts), to: TrialRules
  defdelegate class_check(policy, facts), to: TrialRules
  defdelegate person_check(policy, person), to: TrialRules
  defdelegate seats_left(policy, slot, trial_seats_taken), to: TrialRules
  defdelegate open_type?(policy, slot), to: TrialRules
  defdelegate initial_status(policy), to: TrialRules
  defdelegate week_of(at, time_zone), to: TrialRules
  defdelegate open?(status), to: TrialLifecycle
  defdelegate open_statuses(), to: TrialLifecycle
  defdelegate statuses(), to: TrialLifecycle
  defdelegate consumes?(status, no_show_consumes?), to: TrialLifecycle

  @doc "Statuses that hold one of the box's weekly trial places."
  def weekly_statuses, do: ~w(requested booked attended no_show converted)

  def approvals, do: TrialPolicy.approvals()
  def sources, do: TrialRequest.sources()

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  def tenant_data_policy, do: MilosTraining.Trials.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
