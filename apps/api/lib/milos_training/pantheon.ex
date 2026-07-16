defmodule MilosTraining.Pantheon do
  alias MilosTraining.Application.{
    CreatePR,
    DeletePR,
    GetPRHistory,
    ListUserPRs,
    SharePR,
    UpdatePR
  }

  defdelegate list_user_prs(user_id, opts \\ []), to: ListUserPRs, as: :call
  defdelegate create_pr(user_id, params), to: CreatePR, as: :call
  defdelegate update_pr(id, user_id, params), to: UpdatePR, as: :call
  defdelegate delete_pr(id, user_id), to: DeletePR, as: :call
  defdelegate get_pr_history(id, user_id), to: GetPRHistory, as: :call
  defdelegate share_pr(id, user_id), to: SharePR, as: :call

  # Bounded-context API used by cross-context application orchestration. These
  # operations expose Pantheon capabilities without leaking its store port.
  defdelegate list_records(user_id), to: MilosTraining.Pantheon.PRStore, as: :list_user_prs

  defdelegate search_records(user_id, query),
    to: MilosTraining.Pantheon.PRStore,
    as: :search_user_prs

  defdelegate get_record_for_user(id, user_id),
    to: MilosTraining.Pantheon.PRStore,
    as: :get_pr_for_user

  defdelegate create_record(params), to: MilosTraining.Pantheon.PRStore, as: :create_pr
  defdelegate update_record(id, params), to: MilosTraining.Pantheon.PRStore, as: :update_pr
  defdelegate delete_record(id, user_id), to: MilosTraining.Pantheon.PRStore, as: :delete_pr
end
