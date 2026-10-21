defmodule Palee.Devices do
  @moduledoc """
  Devices bounded context (ADR-161, ADR-149, ADR-172; vision §7 «Συνδεδεμένες
  συσκευές»): a person's links to health device providers (Garmin, and the
  phone's Apple Health or Health Connect through the store apps),
  what each sent, and the watch workouts kept for the journal. Everything is
  the person's own data; the rules live in this context's domain and use
  cases orchestrate them in `Palee.Application`.
  """

  alias Palee.Devices.{DeviceStore, GarminClient, SyncQueue}

  alias Palee.Devices.Domain.{
    ActivityMatch,
    Catalog,
    ConnectionPolicy,
    GarminSummary,
    ImportPolicy,
    PhoneHealthSample,
    Pkce,
    SummaryReader,
    TenantDataPolicy
  }

  defdelegate with_context(context, fun), to: DeviceStore

  # Vocabulary.
  defdelegate providers(), to: Catalog
  defdelegate phone_providers(), to: Catalog
  defdelegate phone_provider?(provider), to: Catalog
  defdelegate replaceable_kind?(kind), to: Catalog
  defdelegate pref_keys(), to: Catalog
  defdelegate pref_keys(provider), to: Catalog
  defdelegate default_prefs(), to: Catalog
  defdelegate default_prefs(provider), to: Catalog
  defdelegate backfill_day_options(), to: Catalog, as: :backfill_days
  defdelegate merge_prefs(current, changes), to: Catalog
  defdelegate merge_prefs(provider, current, changes), to: Catalog
  defdelegate validate_backfill_days(days), to: Catalog
  defdelegate wanted?(prefs, kind), to: Catalog
  defdelegate health_data?(prefs), to: Catalog
  defdelegate health_data?(provider, prefs), to: Catalog

  # Connection life.
  defdelegate sign_in_expired?(started_at, now), to: ConnectionPolicy
  defdelegate refresh_due?(expires_at, now), to: ConnectionPolicy
  defdelegate refresh_horizon(now), to: ConnectionPolicy
  defdelegate validate_sync_request(last, now), to: ConnectionPolicy
  defdelegate failure_changes(connection, message), to: ConnectionPolicy, as: :failure
  defdelegate success_changes(connection, now), to: ConnectionPolicy, as: :success
  defdelegate backfill_windows(days, now), to: ConnectionPolicy
  defdelegate backfill_progress(connection), to: ConnectionPolicy
  defdelegate row_status(connection, configured?), to: ConnectionPolicy
  defdelegate phone_read_from(connection), to: ConnectionPolicy
  defdelegate phone_history_days(), to: ConnectionPolicy

  # PKCE.
  defdelegate pkce_verifier(random), to: Pkce, as: :verifier
  defdelegate pkce_challenge(verifier), to: Pkce, as: :challenge
  defdelegate oauth_state(random), to: Pkce, as: :state
  defdelegate oauth_state_hash(state), to: Pkce, as: :state_hash

  # Garmin summaries.
  defdelegate garmin_kind(type), to: GarminSummary, as: :kind
  defdelegate garmin_summary_types(), to: GarminSummary, as: :summary_types
  defdelegate garmin_backfill_types(kinds), to: GarminSummary, as: :backfill_types
  defdelegate garmin_user_id(summary), to: GarminSummary, as: :user_id
  defdelegate garmin_provider_id(summary), to: GarminSummary, as: :provider_id
  defdelegate garmin_trim(kind, summary), to: GarminSummary, as: :trim
  defdelegate garmin_activity(summary), to: GarminSummary, as: :activity
  defdelegate garmin_sleep(summary), to: GarminSummary, as: :sleep
  defdelegate garmin_weight(summary), to: GarminSummary, as: :weight
  defdelegate garmin_daily(summary), to: GarminSummary, as: :daily

  # Any provider's records (ADR-172): one reading per kind.
  defdelegate read_summary(provider, kind, record), to: SummaryReader, as: :read
  defdelegate summary_provider_id(provider, kind, record), to: SummaryReader, as: :provider_id
  defdelegate trim_summary(provider, kind, record), to: SummaryReader, as: :trim
  defdelegate phone_health_batches(body), to: PhoneHealthSample, as: :batches

  # Import rules.
  defdelegate match_activity(activity, candidates, taken), to: ActivityMatch, as: :decide
  defdelegate match_window(activity), to: ActivityMatch, as: :search_window
  defdelegate import_visibility(), to: ImportPolicy, as: :visibility
  defdelegate sleep_decision(entries, provider), to: ImportPolicy
  defdelegate weight_decision(snapshots, provider), to: ImportPolicy
  defdelegate other_device_activity(activity, device_activities, provider), to: ImportPolicy
  defdelegate device_card(imports, pending_count, seen_at), to: ImportPolicy, as: :card

  # Store.
  defdelegate get_connection(user_id, provider), to: DeviceStore
  defdelegate insert_connection(attrs), to: DeviceStore
  defdelegate update_connection(connection, attrs), to: DeviceStore
  defdelegate list_connections(user_id), to: DeviceStore
  defdelegate connection_by_oauth_state(state_hash), to: DeviceStore, as: :oauth_state_lookup

  defdelegate connections_for_provider_users(provider, ids),
    to: DeviceStore,
    as: :provider_users_lookup

  defdelegate connections_due_refresh(before, limit), to: DeviceStore, as: :refresh_due_lookup
  defdelegate get_import(user_id, provider, kind, provider_id), to: DeviceStore
  defdelegate get_import_by_id(id, user_id), to: DeviceStore
  defdelegate insert_import(attrs), to: DeviceStore
  defdelegate update_import(import, attrs), to: DeviceStore
  defdelegate list_imports_since(user_id, since), to: DeviceStore
  defdelegate list_imports(user_id, provider), to: DeviceStore
  defdelegate delete_imports(user_id, provider), to: DeviceStore
  defdelegate insert_activity(attrs), to: DeviceStore
  defdelegate update_activity(activity, attrs), to: DeviceStore
  defdelegate get_activity(id, user_id), to: DeviceStore
  defdelegate list_pending_activities(user_id), to: DeviceStore
  defdelegate list_activity_items(user_id, bound, limit, scope), to: DeviceStore
  defdelegate list_merged(kind, ids), to: DeviceStore
  defdelegate match_candidates(from, to), to: DeviceStore
  defdelegate list_activities_between(user_id, from, to), to: DeviceStore
  defdelegate list_activities(user_id), to: DeviceStore
  defdelegate delete_activities(user_id, provider), to: DeviceStore
  defdelegate upsert_daily_stat(attrs), to: DeviceStore
  defdelegate list_daily_stats(user_id, from, to), to: DeviceStore
  defdelegate list_all_daily_stats(user_id), to: DeviceStore
  defdelegate delete_daily_stats(user_id, source), to: DeviceStore
  defdelegate transaction(fun), to: DeviceStore

  # Ports.
  def garmin, do: GarminClient
  def sync_queue, do: SyncQueue

  # Tenant data lifecycle (ADR-117): watch activities tied to a gym's class.
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
