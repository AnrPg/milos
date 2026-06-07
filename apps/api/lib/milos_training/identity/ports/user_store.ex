defmodule MilosTraining.Identity.Ports.UserStore do
  alias MilosTraining.Identity.Account

  @callback create_user(map()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_user(Account.t()) :: :ok | {:error, term()}
  @callback update_user_role(Account.t() | Ecto.UUID.t(), atom() | String.t()) ::
              {:ok, Account.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback get_by_nickname(String.t() | nil) :: Account.t() | nil
  @callback get_by_id(Ecto.UUID.t() | nil) :: Account.t() | nil
end
