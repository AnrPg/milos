defmodule MilosTraining.Body do
  @moduledoc """
  Body bounded context (ADR-158, Ημερολόγιο › Σώμα): measurement snapshots
  in SI units, their private photos, health consents, body settings and the
  audit of coach reads. Body data is the person's own (account-scoped): it
  follows them across gyms and goes with the account. Display rules
  (weight as trend or hidden), consent and privacy live in this context's
  domain; use cases orchestrate them in `MilosTraining.Application`.
  """

  alias MilosTraining.Body.BodyStore

  alias MilosTraining.Body.Domain.{
    ConsentPolicy,
    DisplayPolicy,
    MetricCatalog,
    SettingsPolicy,
    SnapshotCursor,
    SnapshotPolicy,
    TenantDataPolicy,
    TrendPolicy
  }

  def with_context(context, fun) when is_function(fun, 0),
    do: BodyStore.with_context(context, fun)

  # Metrics.
  defdelegate metric_keys(), to: MetricCatalog, as: :keys
  defdelegate unit_systems(), to: MetricCatalog
  defdelegate metric_catalog(units), to: MetricCatalog, as: :catalog
  defdelegate metric_unit(key, units), to: MetricCatalog, as: :unit
  defdelegate known_metric?(key), to: MetricCatalog, as: :known?
  defdelegate validate_metrics(metrics, units), to: MetricCatalog, as: :validate
  defdelegate merge_metrics(stored, changes), to: MetricCatalog, as: :merge
  defdelegate clean_metrics(metrics), to: MetricCatalog, as: :clean

  # Snapshots.
  defdelegate visibilities(), to: SnapshotPolicy
  defdelegate poses(), to: SnapshotPolicy
  defdelegate max_photos(), to: SnapshotPolicy
  defdelegate photo_statuses(), to: SnapshotPolicy
  defdelegate sources(), to: SnapshotPolicy
  defdelegate validate_visibility(visibility), to: SnapshotPolicy
  defdelegate validate_content(metrics, photo_count), to: SnapshotPolicy
  defdelegate validate_photos(existing_poses, new_poses), to: SnapshotPolicy
  defdelegate normalize_notes(notes), to: SnapshotPolicy
  defdelegate shared?(visibility), to: SnapshotPolicy
  defdelegate photo_status(media_status), to: SnapshotPolicy
  defdelegate decode_cursor(cursor), to: SnapshotCursor, as: :decode
  defdelegate page_limit(limit), to: SnapshotCursor, as: :limit
  defdelegate page(rows, limit), to: SnapshotCursor

  # Display and trends.
  defdelegate display_modes(), to: DisplayPolicy, as: :modes
  defdelegate shown_metrics(metrics, settings), to: DisplayPolicy, as: :metrics
  defdelegate shown_series(key, points, settings), to: DisplayPolicy, as: :series
  defdelegate shown_deltas(from, to, settings), to: DisplayPolicy, as: :deltas
  defdelegate trend_words(), to: TrendPolicy, as: :words
  defdelegate ranges(), to: TrendPolicy
  defdelegate range_since(range, now), to: TrendPolicy, as: :since

  # Consents.
  defdelegate consent_scopes(), to: ConsentPolicy, as: :scopes
  defdelegate validate_consent_scope(scope), to: ConsentPolicy, as: :validate_scope
  defdelegate require_photo_consent(consents), to: ConsentPolicy, as: :require_photos
  defdelegate consent_summary(consents), to: ConsentPolicy, as: :summary
  defdelegate photos_visible_to_coach?(visibility, consent?), to: ConsentPolicy

  # Settings.
  defdelegate journal_sections(), to: SettingsPolicy, as: :sections
  defdelegate compare_modes(), to: SettingsPolicy
  defdelegate max_reminder_weeks(), to: SettingsPolicy
  defdelegate section_on?(settings, section), to: SettingsPolicy
  defdelegate settings_changes(current, params, now), to: SettingsPolicy, as: :changes
  defdelegate reminder_due?(settings, last_taken_at, now), to: SettingsPolicy
  defdelegate reminder_dedupe_key(user_id, day), to: SettingsPolicy

  @doc "The person's settings with every default filled."
  def settings(context, user_id),
    do: context |> BodyStore.get_settings(user_id) |> SettingsPolicy.effective()

  def put_settings(context, user_id, changes),
    do: BodyStore.put_settings(context, user_id, changes)

  # Store.
  defdelegate list_snapshots(context, user_id, opts), to: BodyStore
  defdelegate get_snapshot(context, user_id, id, opts \\ []), to: BodyStore
  defdelegate create_snapshot(context, attrs), to: BodyStore
  defdelegate update_snapshot(context, user_id, id, attrs), to: BodyStore
  defdelegate delete_snapshot(context, user_id, id), to: BodyStore
  defdelegate delete_empty_snapshots(context, user_id), to: BodyStore
  defdelegate list_metric_points(context, user_id, key, since), to: BodyStore
  defdelegate latest_taken_at(context, user_id), to: BodyStore
  defdelegate list_photos(context, snapshot_ids), to: BodyStore
  defdelegate insert_photo(context, attrs), to: BodyStore
  defdelegate get_photo(context, user_id, photo_id), to: BodyStore
  defdelegate delete_photo(context, user_id, photo_id), to: BodyStore
  defdelegate refresh_photo(context, media_id, attrs), to: BodyStore
  defdelegate latest_photos(context, user_id), to: BodyStore
  defdelegate list_consents(context, user_id), to: BodyStore
  defdelegate grant_consent(context, user_id, scope, now), to: BodyStore
  defdelegate withdraw_consent(context, user_id, scope, now), to: BodyStore
  defdelegate photos_consented?(context, user_id), to: BodyStore
  defdelegate record_access(context, attrs), to: BodyStore
  defdelegate list_access_log(context, user_id, limit), to: BodyStore
  defdelegate reminders_due(now, limit), to: BodyStore
  defdelegate mark_reminded(context, user_id, now), to: BodyStore

  # Tenant data lifecycle (ADR-117): only the coach-read audit is a gym's.
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
