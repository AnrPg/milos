defmodule Palee.Application.SignOutAllDevices do
  alias Palee.Application.SecurityNotices
  alias Palee.Identity

  def call(%{id: user_id}) do
    with {:ok, account} <- Identity.bump_security_version(user_id) do
      # ADR-208: told by email, so a session that wasn't theirs is noticed.
      SecurityNotices.notify(:signed_out_everywhere, account)
    end
  end
end
