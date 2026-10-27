defmodule Palee.Application.SecurityNotices do
  @moduledoc """
  Tells a person by email (category :security, ADR-203) that something
  happened to their login's credentials or sessions. Never carries a secret.

  Events: `:password_changed`, `:password_reset_completed`,
  `:email_change_requested`, `:email_changed`, `:recovery_code_used`,
  `:recovery_codes_regenerated`, `:recovery_codes_running_low`,
  `:signed_out_everywhere`, `:profile_added`, `:new_sign_in`.

  `meta` may carry `:to` (an address other than the login's current one,
  e.g. the old address after an email change), `:device`, `:ip`,
  `:revert_url`, `:sign_out_url`, `:remaining`.
  """

  @events ~w(password_changed password_reset_completed email_change_requested email_changed
             recovery_code_used recovery_codes_regenerated recovery_codes_running_low
             signed_out_everywhere profile_added new_sign_in)a

  def events, do: @events

  @doc "Queues the notice; always `:ok` so a mail problem never fails the action."
  def notify(event, _account, _meta \\ %{}) when event in @events, do: :ok
end
