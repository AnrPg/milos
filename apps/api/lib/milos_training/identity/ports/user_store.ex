defmodule MilosTraining.Identity.Ports.UserStore do
  alias MilosTraining.Identity.Account

  @callback create_user(map()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_user(Account.t()) :: :ok | {:error, term()}
  @callback update_user_role(Account.t() | Ecto.UUID.t(), atom() | String.t()) ::
              {:ok, Account.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback regenerate_calendar_feed_token(Account.t() | Ecto.UUID.t()) ::
              {:ok, Account.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback get_by_nickname(String.t() | nil) :: Account.t() | nil
  @callback get_by_id(Ecto.UUID.t() | nil) :: Account.t() | nil
  @callback list_by_ids([Ecto.UUID.t()]) :: [Account.t()]
  @callback list_by_role(atom() | String.t()) :: [Account.t()]
  @callback list_all_users() :: [Account.t()]
  @callback search_athletes(String.t() | nil) :: [Account.t()]
  @callback update_profile(Ecto.UUID.t(), map()) ::
              {:ok, Account.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback update_avatar(Ecto.UUID.t(), String.t()) ::
              {:ok, Account.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback search_users(String.t() | nil) :: [Account.t()]
  @callback count_by_role(atom() | String.t()) :: non_neg_integer()
  @callback bump_security_version(Ecto.UUID.t()) ::
              {:ok, Account.t()} | {:error, :not_found | Ecto.Changeset.t()}
end
