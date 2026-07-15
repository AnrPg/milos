defmodule MilosTraining.Messaging.Ports.ThreadStore do
  alias MilosTraining.Messaging.Thread

  @callback get_thread(Ecto.UUID.t()) :: Thread.t() | nil
  @callback get_thread_with_participants(Ecto.UUID.t()) :: Thread.t() | nil
  @callback find_direct_thread(Ecto.UUID.t(), Ecto.UUID.t()) :: Thread.t() | nil
  @callback find_context_thread(atom(), Ecto.UUID.t()) :: Thread.t() | nil
  @callback list_threads_for_user(Ecto.UUID.t(), atom() | nil) :: [Thread.t()]
  @callback create_thread(map()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  @callback add_participant(Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, MilosTraining.Messaging.Participant.t()} | {:error, Ecto.Changeset.t()}
  @callback mark_read(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  @callback count_unread_threads(Ecto.UUID.t()) :: non_neg_integer()
end
