defmodule MilosTraining.Workers.PropagateNicknameJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias MilosTraining.Application.{AdminMemberSearchDocuments, AdminMemberSearchIndex}
  alias MilosTraining.{Gamification, Notifications}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"old_nickname" => old_nickname, "new_nickname" => new_nickname}}) do
    case Gamification.refresh_leaderboard() do
      :ok -> :ok
      {:error, _} -> :ok
    end

    documents = AdminMemberSearchDocuments.build_all()
    AdminMemberSearchIndex.replace_documents(documents)

    Notifications.propagate_nickname_change(old_nickname, new_nickname)

    :ok
  end
end
