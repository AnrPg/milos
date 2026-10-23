defmodule Palee.Identity.Ports.PasswordResetStore do
  @moduledoc "ADR-187: storage of password reset requests, their log and recovery codes."

  alias Palee.Identity.PasswordResetRequest

  @type handler :: %{
          user_id: Ecto.UUID.t(),
          source: String.t(),
          organization_id: Ecto.UUID.t() | nil,
          organization_name: String.t() | nil
        }

  @type inbox_entry :: %{
          request: PasswordResetRequest.t(),
          person: map(),
          claimer: map() | nil,
          sources: [String.t()],
          organizations: [String.t()]
        }

  @callback handlers(Ecto.UUID.t()) :: [handler()]
  @callback get_request(Ecto.UUID.t()) :: PasswordResetRequest.t() | nil
  @callback get_request_for_login(Ecto.UUID.t()) :: PasswordResetRequest.t() | nil
  @callback get_request_by_token_hash(binary()) :: PasswordResetRequest.t() | nil
  @callback create_request(map()) :: {:ok, PasswordResetRequest.t()} | {:error, term()}
  @callback update_request_locked(
              Ecto.UUID.t(),
              (PasswordResetRequest.t() -> {:ok, map()} | {:error, term()})
            ) :: {:ok, PasswordResetRequest.t()} | {:error, term()}
  @callback delete_request(Ecto.UUID.t()) :: :ok
  @callback inbox(Ecto.UUID.t()) :: [inbox_entry()]
  @callback inbox_entry(Ecto.UUID.t(), Ecto.UUID.t()) :: inbox_entry() | nil
  @callback hide(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  @callback log(map()) :: :ok
  @callback list_log(pos_integer()) :: [map()]
  @callback replace_recovery_codes(Ecto.UUID.t(), [binary()]) :: :ok
  @callback count_recovery_codes(Ecto.UUID.t()) :: %{
              total: non_neg_integer(),
              unused: non_neg_integer()
            }
  @callback use_recovery_code(Ecto.UUID.t(), binary(), DateTime.t()) :: :ok | {:error, :invalid}
end
