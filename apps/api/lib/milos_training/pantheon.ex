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
end
