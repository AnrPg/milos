defmodule MilosTraining.Seasons do
  @moduledoc """
  The Seasons bounded context (ADR-167, P3-M5): fixed-length programmes a gym
  sells («Πουλάς προγράμματα, όχι μόνο συνδρομές»). It owns the offering and
  each member's enrollment. What a confirmed place grants lives elsewhere and
  is wired by the application layer: entitlements through a Finance package,
  the programme as Workouts assignments, the crew as a Community channel.

  Every function runs in the gym's scope.
  """

  alias MilosTraining.Seasons.{SeasonEnrollment, SeasonOffering, SeasonStore}
  alias MilosTraining.Seasons.Domain.{EnrollmentLifecycle, SeasonRules, TenantDataPolicy}

  defdelegate create_offering(context, attrs), to: SeasonStore
  defdelegate update_offering(context, offering, attrs), to: SeasonStore
  defdelegate get_offering(context, id), to: SeasonStore
  defdelegate list_offerings(context, filters \\ %{}), to: SeasonStore
  defdelegate enrollment_counts(context, ids), to: SeasonStore
  defdelegate titles(context, ids), to: SeasonStore
  defdelegate get_enrollment(context, id), to: SeasonStore
  defdelegate get_member_enrollment(context, offering_id, user_id), to: SeasonStore
  defdelegate list_enrollments(context, offering_id), to: SeasonStore
  defdelegate list_member_enrollments(context, user_id), to: SeasonStore
  defdelegate first_waitlisted(context, offering_id), to: SeasonStore
  defdelegate with_offering_lock(context, offering_id, fun), to: SeasonStore

  @doc "Inserts a first request, or re-opens a declined or cancelled one."
  def request(context, offering, user_id, existing, status, now) do
    changes = EnrollmentLifecycle.request(status, now)

    case existing do
      nil ->
        SeasonStore.insert_enrollment(context, %{
          season_offering_id: offering.id,
          user_id: user_id,
          status: status,
          requested_at: now
        })

      %SeasonEnrollment{} = enrollment ->
        SeasonStore.update_enrollment(context, enrollment, changes)
    end
  end

  @doc "Moves an enrollment one lifecycle step and writes it, with any `extra` changes."
  def transition(context, %SeasonEnrollment{} = enrollment, step, now, opts \\ [], extra \\ %{}) do
    with {:ok, changes} <- EnrollmentLifecycle.transition(enrollment, step, now, opts) do
      SeasonStore.update_enrollment(context, enrollment, Map.merge(changes, extra))
    end
  end

  defdelegate ends_on(offering), to: SeasonRules
  defdelegate effective_status(offering, today), to: SeasonRules
  defdelegate open?(offering, today), to: SeasonRules
  defdelegate request_status(capacity, held), to: SeasonRules
  defdelegate can_confirm?(capacity, active), to: SeasonRules
  defdelegate request_check(offering, today), to: SeasonRules
  defdelegate schedule_locked?(active_count), to: SeasonRules
  defdelegate schedule(programme, starts_on, from), to: SeasonRules
  defdelegate programme_workout_ids(programme), to: SeasonRules
  defdelegate can_request?(status), to: EnrollmentLifecycle
  defdelegate check_step(enrollment, step, now), to: EnrollmentLifecycle, as: :transition
  def schedule_fields, do: SeasonRules.schedule_fields()
  def statuses, do: SeasonRules.statuses()
  def enrollment_statuses, do: EnrollmentLifecycle.statuses()
  def holding_statuses, do: EnrollmentLifecycle.holding_statuses()
  def open_enrollment_statuses, do: EnrollmentLifecycle.open_statuses()
  def editable_fields, do: SeasonOffering.editable_fields()

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
