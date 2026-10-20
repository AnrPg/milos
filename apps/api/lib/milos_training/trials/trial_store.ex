defmodule MilosTraining.Trials.TrialStore do
  @moduledoc "Facade over the trials adapter (ADR-144); every call runs in the caller's session."

  @behaviour MilosTraining.Trials.Ports.TrialStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :trial_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def get_policy(context), do: call(context, :get_policy, [])

  @impl true
  def put_policy(context, attrs), do: call(context, :put_policy, [attrs])

  @impl true
  def insert_request(context, attrs), do: call(context, :insert_request, [attrs])

  @impl true
  def get_request(context, id), do: call(context, :get_request, [id])

  @impl true
  def get_request_by_booking(context, booking_id),
    do: call(context, :get_request_by_booking, [booking_id])

  @impl true
  def get_request_by_operation(context, user_id, operation_id),
    do: call(context, :get_request_by_operation, [user_id, operation_id])

  @impl true
  def update_request(context, request, changes),
    do: call(context, :update_request, [request, changes])

  @impl true
  def list_requests(context, filters), do: call(context, :list_requests, [filters])

  @impl true
  def list_person_requests(context, user_id, opts),
    do: call(context, :list_person_requests, [user_id, opts])

  @impl true
  def person_statuses(context, user_id), do: call(context, :person_statuses, [user_id])

  @impl true
  def count_in_window(context, window, statuses),
    do: call(context, :count_in_window, [window, statuses])

  @impl true
  def open_per_class(context, slot_ids), do: call(context, :open_per_class, [slot_ids])

  @impl true
  def stats(context, since), do: call(context, :stats, [since])

  @impl true
  def referral_event_stats(context, event_ids),
    do: call(context, :referral_event_stats, [event_ids])

  @impl true
  def with_box_lock(context, fun), do: call(context, :with_box_lock, [fun])
end
