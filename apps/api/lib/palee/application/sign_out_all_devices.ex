defmodule Palee.Application.SignOutAllDevices do
  alias Palee.Application.SecurityNotices
  alias Palee.Identity

  def call(%{id: user_id}) do
    # Every profile of the login: the email says every device is signed out.
    with {:ok, account} <- Identity.bump_security_version(user_id),
         :ok <- Identity.bump_login_security_version(account.login_id) do
      # ADR-208: told by email, so a session that wasn't theirs is noticed.
      SecurityNotices.notify(:signed_out_everywhere, account)
    end
  end
end
