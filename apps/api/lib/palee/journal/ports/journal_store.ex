defmodule Palee.Journal.Ports.JournalStore do
  @moduledoc "Persistence port of the Journal context (ADR-139)."

  @type note :: map()

  @callback list_defaults(user_id :: Ecto.UUID.t()) :: %{String.t() => String.t()}
  @callback put_default(user_id :: Ecto.UUID.t(), kind :: String.t(), rung :: String.t()) ::
              :ok | {:error, Ecto.Changeset.t()}

  @callback create_note(map()) :: {:ok, note()} | {:error, Ecto.Changeset.t()}
  @callback update_note(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t(), map(), integer()) ::
              {:ok, note()} | {:error, :not_found | :stale | Ecto.Changeset.t()}
  @callback delete_note(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t(), DateTime.t()) ::
              {:ok, note()} | {:error, :not_found}
  @callback get_note_for_user(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t()) :: note() | nil
  @callback set_note_visibility(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t(), String.t()) ::
              {:ok, note()} | {:error, :not_found | Ecto.Changeset.t()}
  @callback move_notes(user_id :: Ecto.UUID.t(), from :: [String.t()], to :: String.t()) ::
              non_neg_integer()
  @callback list_note_items(
              user_id :: Ecto.UUID.t(),
              bound :: term(),
              limit :: pos_integer(),
              scope :: term()
            ) ::
              [map()]
  @callback list_coach_visible_notes(user_id :: Ecto.UUID.t(), organization_id :: Ecto.UUID.t()) ::
              [map()]
  @callback record_coach_reads([map()]) :: :ok

  @callback save_comment(map()) :: {:ok, map()} | {:error, :comment_conflict | Ecto.Changeset.t()}
  @callback delete_comment(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, map()} | {:error, :not_found}
  @callback list_comments(String.t(), [Ecto.UUID.t()]) :: [map()]
  @callback entry_owner(String.t(), Ecto.UUID.t()) ::
              %{user_id: Ecto.UUID.t(), organization_id: Ecto.UUID.t() | nil} | nil
  @callback transaction((-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}
  @callback list_changes_since(Ecto.UUID.t(), DateTime.t()) :: [map()]

  # ADR-162: «Οι coach μου» across providers and the whole-journal export.
  # A coach is `{organization_id, coach_user_id}`.
  @type coach :: {Ecto.UUID.t(), Ecto.UUID.t()}
  @callback list_audience_exclusions(Ecto.UUID.t()) :: [coach()]
  @callback replace_audience_exclusions(Ecto.UUID.t(), [coach()]) :: :ok
  @callback entry_audiences(Ecto.UUID.t(), String.t(), [Ecto.UUID.t()]) ::
              %{Ecto.UUID.t() => [coach()]}
  @callback put_entry_audience(Ecto.UUID.t(), String.t(), Ecto.UUID.t(), [coach()] | nil) ::
              :ok
  @callback insert_export(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_export(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback list_exports(Ecto.UUID.t()) :: [map()]
  @callback finish_export(map(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
end
