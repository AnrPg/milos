defmodule Palee.Application.SignOutEverywhereLink do
  @moduledoc """
  ADR-208: the "sign out everywhere" link of a security notice. Opening it
  (the web page posts its token) ends every session of every profile of
  the login: the login's `security_version` goes up, which every access and
  refresh token carries. The link works once, for 7 days, and needs no
  session: whoever reads the person's mailbox may sign them out, nothing
  more. Opening it also proves the address it was sent to (ADR-203).
  """

  alias Palee.Application.SecurityNotices
  alias Palee.Email.LinkTokens
  alias Palee.Identity

  @spec call(String.t(), DateTime.t()) :: :ok | {:error, :invalid | :expired | :used}
  def call(raw_token, now \\ DateTime.utc_now())

  def call(raw_token, now) when is_binary(raw_token) do
    with {:ok, token} <- LinkTokens.consume(:sign_out_everywhere, raw_token, now),
         :ok <- Identity.bump_login_security_version(token.login_id) do
      if is_binary(token.target_email),
        do: Identity.mark_email_verified(token.login_id, token.target_email, now)

      case account(token) do
        nil -> :ok
        account -> SecurityNotices.notify(:signed_out_everywhere, account, %{at: now})
      end
    else
      {:error, :not_found} -> {:error, :invalid}
      {:error, _reason} = error -> error
    end
  end

  def call(_raw_token, _now), do: {:error, :invalid}

  defp account(%{user_id: user_id, login_id: login_id}) do
    (is_binary(user_id) && Identity.find_by_id(user_id)) ||
      login_id |> Identity.list_profiles() |> List.first()
  end
end
