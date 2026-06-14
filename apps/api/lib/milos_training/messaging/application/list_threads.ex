defmodule MilosTraining.Messaging.Application.ListThreads do
  alias MilosTraining.Messaging.ThreadStore

  def call(user_id, context_type \\ nil) do
    ThreadStore.list_threads_for_user(user_id, context_type)
  end
end
