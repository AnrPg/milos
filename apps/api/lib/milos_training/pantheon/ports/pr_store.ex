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
  @callback list_user_pr_history(user_id :: Ecto.UUID.t()) :: [map()]
  @callback count_user_prs(user_id :: Ecto.UUID.t()) :: non_neg_integer()
  @callback list_organization_prs(user_id :: Ecto.UUID.t(), organization_id :: Ecto.UUID.t()) ::
              [map()]
  @callback get_sharing_preference(user_id :: Ecto.UUID.t()) :: %{coach_visibility: boolean()}
  @callback put_coach_visibility(user_id :: Ecto.UUID.t(), enabled :: boolean()) ::
              {:ok, %{coach_visibility: boolean()}} | {:error, Ecto.Changeset.t()}
  @callback list_owned_grants(user_id :: Ecto.UUID.t()) :: [map()]
  @callback list_received_grants(grantee_user_id :: Ecto.UUID.t()) :: [map()]
  @callback get_active_grant(user_id :: Ecto.UUID.t(), grantee_user_id :: Ecto.UUID.t()) ::
              map() | nil
  @callback create_grant(user_id :: Ecto.UUID.t(), grantee_user_id :: Ecto.UUID.t()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback revoke_grant(
              user_id :: Ecto.UUID.t(),
              grant_id :: Ecto.UUID.t(),
              revoked_at :: DateTime.t()
            ) :: {:ok, map()} | {:error, :not_found | Ecto.Changeset.t()}
end
