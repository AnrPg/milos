defmodule MilosTraining.Pantheon.Ports.PRStore do
  @callback list_user_prs(user_id :: Ecto.UUID.t()) :: [map()]
  @callback search_user_prs(user_id :: Ecto.UUID.t(), query :: String.t()) :: [map()]
  @callback get_pr(id :: Ecto.UUID.t()) :: map() | nil
  @callback get_pr_for_user(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t()) :: map() | nil
  @callback create_pr(params :: map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_pr(id :: Ecto.UUID.t(), params :: map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback edit_pr(id :: Ecto.UUID.t(), params :: map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_pr(id :: Ecto.UUID.t(), user_id :: Ecto.UUID.t()) ::
              :ok | {:error, :not_found}
  @callback list_pr_history(pr_record_id :: Ecto.UUID.t()) :: [map()]
  @callback count_user_prs(user_id :: Ecto.UUID.t()) :: non_neg_integer()
end
