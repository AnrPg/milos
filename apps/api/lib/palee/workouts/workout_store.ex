defmodule Palee.Workouts.WorkoutStore do
  @moduledoc """
  Facade over the configured `Workouts.Ports.WorkoutStore` adapter.

  The adapter is session-scoped: it reads and writes in whatever RepoContext
  session is open. This facade is where that session is opened, so every read
  takes a tenant context (ADR-091, ADR-133). Context-free write arities remain
  for the legacy commands still being migrated; RLS limits them to the
  session's tenant.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  defp adapter do
    Application.fetch_env!(:palee, :workout_store)
  end

  # Tenant-scoped reads.

  def get_workout(context, id), do: within_tenant(context, fn -> adapter().get_workout(id) end)

  def get_workout_for_admin(context, id),
    do: within_tenant(context, fn -> adapter().get_workout_for_admin(id) end)

  def exercise_exists?(context, id),
    do: within_tenant(context, fn -> adapter().exercise_exists?(id) end)

  def list_workouts(context), do: within_tenant(context, &adapter().list_workouts/0)
  def list_folders(context), do: within_tenant(context, &adapter().list_folders/0)

  def search_workout_choices(context, opts),
    do: within_tenant(context, fn -> adapter().search_workout_choices(opts) end)

  def workout_choices_by_ids(context, ids),
    do: within_tenant(context, fn -> adapter().workout_choices_by_ids(ids) end)

  def get_assigned_workout(context, id),
    do: within_tenant(context, fn -> adapter().get_assigned_workout(id) end)

  def get_assignment(context, assignment_id),
    do: within_tenant(context, fn -> adapter().get_assignment(assignment_id) end)

  def list_assigned_workouts_for_admin(context, start_date, end_date),
    do:
      within_tenant(context, fn ->
        adapter().list_assigned_workouts_for_admin(start_date, end_date)
      end)

  def list_assigned_workouts_for_athlete(context, athlete_id, start_date, end_date),
    do:
      within_tenant(context, fn ->
        adapter().list_assigned_workouts_for_athlete(athlete_id, start_date, end_date)
      end)

  def list_workout_change_targets(context, workout_id),
    do: within_tenant(context, fn -> adapter().list_workout_change_targets(workout_id) end)

  def list_class_variants(context, slot_ids, assignee_id),
    do: within_tenant(context, fn -> adapter().list_class_variants(slot_ids, assignee_id) end)

  def get_assignment_execution_access(context, assignment_id, athlete_id),
    do:
      within_tenant(context, fn ->
        adapter().get_assignment_execution_access(assignment_id, athlete_id)
      end)

  # Deliberately un-scoped (F-03): derives which tenant owns a workout so an
  # execution can open that tenant's scope; every caller follows it with a
  # membership check.
  def workout_organization_id(id), do: adapter().workout_organization_id(id)

  # Tenant-scoped writes.

  def create_draft(context, admin_id),
    do: within_tenant(context, fn -> create_draft(admin_id) end)

  def create_workout(context, admin_id, params),
    do: within_tenant(context, fn -> create_workout(admin_id, params) end)

  def update_draft(context, id, params),
    do: within_tenant(context, fn -> update_draft(id, params) end)

  def delete_workout(context, id), do: within_tenant(context, fn -> delete_workout(id) end)

  def publish_workout(context, id, params),
    do: within_tenant(context, fn -> publish_workout(id, params) end)

  def create_folder(context, admin_id, params),
    do: within_tenant(context, fn -> create_folder(admin_id, params) end)

  def update_folder(context, id, params),
    do: within_tenant(context, fn -> update_folder(id, params) end)

  def set_workout_icon(context, id, icon, icon_source),
    do: within_tenant(context, fn -> set_workout_icon(id, icon, icon_source) end)

  def find_filed_copy(context, source_id, folder_id),
    do: within_tenant(context, fn -> find_filed_copy(source_id, folder_id) end)

  def ensure_system_folder(context, system_key, name, parent_id),
    do: within_tenant(context, fn -> ensure_system_folder(system_key, name, parent_id) end)

  def delete_folder(context, id), do: within_tenant(context, fn -> delete_folder(id) end)

  def update_library_metadata(context, id, params),
    do: within_tenant(context, fn -> update_library_metadata(id, params) end)

  def assign_workout(context, params),
    do: within_tenant(context, fn -> assign_workout(params) end)

  def update_assigned_workout(context, id, params),
    do: within_tenant(context, fn -> update_assigned_workout(id, params) end)

  def update_assignment_date(context, id, athlete_id, new_date),
    do: within_tenant(context, fn -> update_assignment_date(id, athlete_id, new_date) end)

  def delete_assigned_workout(context, id),
    do: within_tenant(context, fn -> delete_assigned_workout(id) end)

  def remove_season_athlete(context, season_offering_id, athlete_id, from_date),
    do:
      within_tenant(context, fn ->
        adapter().remove_season_athlete(season_offering_id, athlete_id, from_date)
      end)

  def reject_assignment_for_athlete(context, assignment_id, athlete_id),
    do: within_tenant(context, fn -> reject_assignment_for_athlete(assignment_id, athlete_id) end)

  def reopen_workout(context, id), do: within_tenant(context, fn -> reopen_workout(id) end)

  def duplicate_workout(context, id, title_suffix, attrs),
    do: within_tenant(context, fn -> duplicate_workout(id, title_suffix, attrs) end)

  def substitute_assignment_workout(context, assignment_id, new_workout_id),
    do:
      within_tenant(context, fn ->
        substitute_assignment_workout(assignment_id, new_workout_id)
      end)

  def delete_superseded_drafts(context, published_id, admin_id),
    do: within_tenant(context, fn -> delete_superseded_drafts(published_id, admin_id) end)

  def archive_active_assignments_for_athlete(context, athlete_id),
    do: adapter().archive_active_assignments_for_athlete(context, athlete_id)

  # ADR-128: scale levels are tenant-owned, so they are only reachable through
  # an organization-scoped session; anything else fails closed.
  def list_scale_levels(%{organization_id: organization_id} = context)
      when is_binary(organization_id),
      do: within_tenant(context, &adapter().list_scale_levels/0)

  def list_scale_levels(_context), do: {:error, :organization_context_required}

  def replace_scale_levels(%{organization_id: organization_id} = context, levels)
      when is_binary(organization_id),
      do: within_tenant(context, fn -> adapter().replace_scale_levels(levels) end)

  def replace_scale_levels(_context, _levels), do: {:error, :organization_context_required}

  def ensure_default_scale_levels(%{organization_id: organization_id} = context, levels)
      when is_binary(organization_id),
      do: within_tenant(context, fn -> adapter().ensure_default_scale_levels(levels) end)

  def ensure_default_scale_levels(_context, _levels),
    do: {:error, :organization_context_required}

  # Legacy context-free writes, run in the caller's session.

  def create_workout(admin_id, params), do: adapter().create_workout(admin_id, params)
  def create_draft(admin_id), do: adapter().create_draft(admin_id)
  def update_draft(id, params), do: adapter().update_draft(id, params)
  def delete_workout(id), do: adapter().delete_workout(id)
  def publish_workout(id, params), do: adapter().publish_workout(id, params)
  def assign_workout(params), do: adapter().assign_workout(params)
  def update_assigned_workout(id, params), do: adapter().update_assigned_workout(id, params)
  def delete_assigned_workout(id), do: adapter().delete_assigned_workout(id)
  def create_folder(admin_id, params), do: adapter().create_folder(admin_id, params)
  def update_folder(id, params), do: adapter().update_folder(id, params)
  def delete_folder(id), do: adapter().delete_folder(id)
  def update_library_metadata(id, params), do: adapter().update_library_metadata(id, params)

  def set_workout_icon(id, icon, icon_source),
    do: adapter().set_workout_icon(id, icon, icon_source)

  def find_filed_copy(source_id, folder_id), do: adapter().find_filed_copy(source_id, folder_id)

  def ensure_system_folder(system_key, name, parent_id),
    do: adapter().ensure_system_folder(system_key, name, parent_id)

  def reject_assignment_for_athlete(assignment_id, athlete_id),
    do: adapter().reject_assignment_for_athlete(assignment_id, athlete_id)

  def archive_active_assignments_for_athlete(athlete_id),
    do: adapter().archive_active_assignments_for_athlete(athlete_id)

  def reopen_workout(id), do: adapter().reopen_workout(id)

  def duplicate_workout(id, title_suffix, attrs \\ %{}),
    do: adapter().duplicate_workout(id, title_suffix, attrs)

  def substitute_assignment_workout(assignment_id, new_workout_id),
    do: adapter().substitute_assignment_workout(assignment_id, new_workout_id)

  def update_assignment_date(id, athlete_id, new_date),
    do: adapter().update_assignment_date(id, athlete_id, new_date)

  def delete_superseded_drafts(published_id, admin_id),
    do: adapter().delete_superseded_drafts(published_id, admin_id)

  defp within_tenant(context, fun), do: RepoContext.run(context, fun)
end
