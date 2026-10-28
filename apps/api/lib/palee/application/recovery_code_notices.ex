defmodule Palee.Application.RecoveryCodeNotices do
  @moduledoc """
  ADR-208: the security notices around recovery codes (ADR-187). Using a
  code says so by email, and when two or fewer unused codes remain a second
  email says to create new ones in Settings. Creating new codes says so
  too. Never carries a code.
  """

  alias Palee.Application.SecurityNotices
  alias Palee.Identity.PasswordResetStore

  # At or below this many unused codes, the person is reminded.
  @running_low_at 2

  @doc "A code of `account`'s login was just used. Always `:ok`."
  def code_used(account, now \\ DateTime.utc_now()) do
    occurrence = Ecto.UUID.generate()
    SecurityNotices.notify(:recovery_code_used, account, %{at: now, occurrence: occurrence})

    case PasswordResetStore.count_recovery_codes(account.login_id) do
      %{unused: unused} when unused <= @running_low_at ->
        SecurityNotices.notify(:recovery_codes_running_low, account, %{
          at: now,
          remaining: unused,
          occurrence: occurrence
        })

      _plenty ->
        :ok
    end
  end

  @doc "New codes replaced the old ones. Always `:ok`."
  def regenerated(account), do: SecurityNotices.notify(:recovery_codes_regenerated, account)

  @doc "The number of unused codes at which the reminder is sent."
  def running_low_at, do: @running_low_at
end
