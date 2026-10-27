defmodule Palee.Identity.Ports.UserStore do
  alias Palee.Identity.Account

  # ADR-187: logins (one per email) hold up to three profiles.
  @callback create_login_with_profile(map()) ::
              {:ok, Account.t()} | {:error, :email_taken | Ecto.Changeset.t()}
  @callback create_demo_person(Ecto.UUID.t(), map()) ::
              {:ok, Account.t()} | {:error, :email_taken | Ecto.Changeset.t()}
  @callback demo_user_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback visible_user_ids([Ecto.UUID.t()], Ecto.UUID.t() | nil) :: [Ecto.UUID.t()]
  @callback add_profile(Ecto.UUID.t(), map()) ::
              {:ok, Account.t()} | {:error, :not_found | :profile_limit | Ecto.Changeset.t()}
  @callback get_login_by_email(String.t() | nil) ::
              %{
                id: Ecto.UUID.t(),
                email: String.t(),
                password_hash: String.t(),
                last_used_user_id: Ecto.UUID.t() | nil,
                profile_count: non_neg_integer()
              }
              | nil
  @callback get_by_email(String.t() | nil) :: Account.t() | nil
  @callback list_profiles(Ecto.UUID.t()) :: [Account.t()]
  @callback touch_last_used(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  @callback handle_available?(String.t(), Ecto.UUID.t() | nil) :: boolean()
  @callback update_credentials(Ecto.UUID.t(), map()) ::
              {:ok, Account.t()} | {:error, :not_found | Ecto.Changeset.t()}
  @callback mark_email_verified(Ecto.UUID.t(), String.t(), DateTime.t()) ::
              :ok | {:error, :email_mismatch}
  @callback reset_login_password(Ecto.UUID.t(), String.t()) ::
              :ok | {:error, :not_found | Ecto.Changeset.t()}
  @callback delete_user(Account.t()) :: :ok | {:error, term()}
  @callback delete_tenant_scoped_user(Account.t()) :: :ok | {:error, term()}
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
  @callback mark_tour_completed(Ecto.UUID.t(), String.t()) ::
              {:ok, map()} | {:error, :not_found | :invalid_tour | Ecto.Changeset.t()}
  @callback update_avatar(Ecto.UUID.t(), String.t()) ::
              {:ok, Account.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback update_time_zone(Ecto.UUID.t(), String.t()) ::
              {:ok, Account.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback search_users(String.t() | nil) :: [Account.t()]
  @callback count_by_role(atom() | String.t()) :: non_neg_integer()
  @callback bump_security_version(Ecto.UUID.t()) ::
              {:ok, Account.t()} | {:error, :not_found | Ecto.Changeset.t()}
end
