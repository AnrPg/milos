defmodule MilosTraining.Devices.Ports.DeviceStore do
  @moduledoc """
  Persistence port of the Devices context (ADR-161). Calls run inside the
  caller's RepoContext (the person's own session; a coach's tenant session
  for feed reads), so row security decides what is visible. The three
  `*_lookup` calls run without a session and answer ids only.
  """

  alias MilosTraining.Devices.{Connection, DailyStat, DeviceActivity, DeviceImport}

  @type id :: Ecto.UUID.t()
  @type result(t) :: {:ok, t} | {:error, term()}

  @callback get_connection(id(), String.t()) :: Connection.t() | nil
  @callback insert_connection(map()) :: result(Connection.t())
  @callback update_connection(Connection.t(), map()) :: result(Connection.t())

  @callback oauth_state_lookup(String.t()) :: {id(), id()} | nil
  @callback provider_users_lookup(String.t(), [String.t()]) :: [map()]
  @callback refresh_due_lookup(DateTime.t(), pos_integer()) :: [{id(), id()}]

  @callback get_import(id(), String.t(), String.t(), String.t()) :: DeviceImport.t() | nil
  @callback get_import_by_id(id(), id()) :: DeviceImport.t() | nil
  @callback insert_import(map()) :: result(DeviceImport.t())
  @callback update_import(DeviceImport.t(), map()) :: result(DeviceImport.t())
  @callback list_imports_since(id(), DateTime.t() | nil) :: [DeviceImport.t()]
  @callback list_imports(id(), String.t()) :: [DeviceImport.t()]
  @callback delete_imports(id(), String.t()) :: non_neg_integer()

  @callback insert_activity(map()) :: result(DeviceActivity.t())
  @callback update_activity(DeviceActivity.t(), map()) :: result(DeviceActivity.t())
  @callback get_activity(id(), id()) :: DeviceActivity.t() | nil
  @callback list_pending_activities(id()) :: [DeviceActivity.t()]
  @callback list_activity_items(id(), term(), pos_integer(), term()) :: [DeviceActivity.t()]
  @callback list_merged(String.t(), [id()]) :: [DeviceActivity.t()]
  @callback match_candidates(DateTime.t(), DateTime.t()) :: [map()]
  @callback delete_activities(id(), String.t()) :: non_neg_integer()

  @callback upsert_daily_stat(map()) :: result(DailyStat.t())
  @callback list_daily_stats(id(), Date.t(), Date.t()) :: [DailyStat.t()]
  @callback delete_daily_stats(id(), String.t()) :: non_neg_integer()

  @callback transaction((-> term())) :: {:ok, term()} | {:error, term()}
end
