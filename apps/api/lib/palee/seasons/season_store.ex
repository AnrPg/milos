defmodule Palee.Seasons.SeasonStore do
  @moduledoc "Facade over the seasons adapter (ADR-167); every call runs in the caller's session."

  @behaviour Palee.Seasons.Ports.SeasonStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :season_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def create_offering(context, attrs), do: call(context, :create_offering, [attrs])

  @impl true
  def update_offering(context, offering, attrs),
    do: call(context, :update_offering, [offering, attrs])

  @impl true
  def get_offering(context, id), do: call(context, :get_offering, [id])

  @impl true
  def list_offerings(context, filters), do: call(context, :list_offerings, [filters])

  @impl true
  def enrollment_counts(context, ids), do: call(context, :enrollment_counts, [ids])

  @impl true
  def titles(context, ids), do: call(context, :titles, [ids])

  @impl true
  def assignment_seasons(context, ids), do: call(context, :assignment_seasons, [ids])

  @impl true
  def get_enrollment(context, id), do: call(context, :get_enrollment, [id])

  @impl true
  def get_member_enrollment(context, offering_id, user_id),
    do: call(context, :get_member_enrollment, [offering_id, user_id])

  @impl true
  def list_enrollments(context, offering_id), do: call(context, :list_enrollments, [offering_id])

  @impl true
  def list_member_enrollments(context, user_id),
    do: call(context, :list_member_enrollments, [user_id])

  @impl true
  def insert_enrollment(context, attrs), do: call(context, :insert_enrollment, [attrs])

  @impl true
  def update_enrollment(context, enrollment, changes),
    do: call(context, :update_enrollment, [enrollment, changes])

  @impl true
  def first_waitlisted(context, offering_id), do: call(context, :first_waitlisted, [offering_id])

  @impl true
  def with_offering_lock(context, offering_id, fun),
    do: call(context, :with_offering_lock, [offering_id, fun])
end
