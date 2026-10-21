defmodule MilosTraining.Body.Ports.BodyStore do
  @moduledoc """
  Persistence port of the Body context (ADR-158). Every call runs in a
  session (`RepoContext`): the person's own for their data, a coach's
  tenant session for shared reads, where row security admits only what
  reaches that coach.
  """

  @type context :: map()
  @type snapshot :: map()
  @type photo :: map()

  @callback list_snapshots(context(), user_id :: binary(), opts :: keyword()) :: [snapshot()]
  @callback get_snapshot(context(), user_id :: binary(), id :: binary(), opts :: keyword()) ::
              snapshot() | nil
  @callback create_snapshot(context(), attrs :: map()) ::
              {:ok, snapshot()} | {:error, Ecto.Changeset.t()}
  @callback update_snapshot(context(), user_id :: binary(), id :: binary(), attrs :: map()) ::
              {:ok, snapshot()} | {:error, :not_found | Ecto.Changeset.t()}
  @callback delete_snapshot(context(), user_id :: binary(), id :: binary()) ::
              {:ok, snapshot()} | {:error, :not_found}
  @callback delete_empty_snapshots(context(), user_id :: binary()) :: non_neg_integer()
  @callback list_metric_points(
              context(),
              binary(),
              key :: String.t(),
              since :: DateTime.t() | nil,
              opts :: keyword()
            ) ::
              [%{at: DateTime.t(), value: number(), snapshot_id: binary()}]
  @callback latest_taken_at(context(), user_id :: binary()) :: DateTime.t() | nil

  @callback list_photos(context(), snapshot_ids :: [binary()]) :: [photo()]
  @callback insert_photo(context(), attrs :: map()) :: {:ok, photo()} | {:error, term()}
  @callback get_photo(context(), user_id :: binary(), photo_id :: binary()) :: photo() | nil
  @callback delete_photo(context(), user_id :: binary(), photo_id :: binary()) ::
              {:ok, photo()} | {:error, :not_found}
  @callback refresh_photo(context(), media_id :: binary(), attrs :: map()) :: :ok
  @callback latest_photos(context(), user_id :: binary()) :: [photo()]

  @callback get_settings(context(), user_id :: binary()) :: map() | nil
  @callback put_settings(context(), user_id :: binary(), changes :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback list_consents(context(), user_id :: binary()) :: [map()]
  @callback grant_consent(context(), user_id :: binary(), scope :: String.t(), DateTime.t()) ::
              {:ok, map()}
  @callback withdraw_consent(context(), user_id :: binary(), scope :: String.t(), DateTime.t()) ::
              non_neg_integer()
  @callback photos_consented?(context(), user_id :: binary()) :: boolean()

  @callback record_access(context(), attrs :: map()) :: :ok
  @callback list_access_log(context(), user_id :: binary(), limit :: pos_integer()) :: [map()]

  @callback reminders_due(DateTime.t(), limit :: pos_integer()) :: [binary()]
  @callback mark_reminded(context(), user_id :: binary(), DateTime.t()) :: :ok
end
