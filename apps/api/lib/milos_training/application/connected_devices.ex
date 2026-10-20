defmodule MilosTraining.Application.ConnectedDevices do
  @moduledoc """
  Εγώ › Συνδεδεμένες συσκευές (ADR-155, decision 7; vision §8): the person's
  Wallet cards at every box (platform, when added, revoke), whether each
  Wallet platform can issue cards on this server, the calendar (ICS) feed
  links (reset with `POST /api/calendar/export-links/regenerate`), and the
  health integrations.

  Nothing here pretends: Garmin (P2-M13) is reported `unavailable` until its
  integration exists; Apple Health and Health Connect are `native_only`
  (they come with the native apps).
  """

  alias MilosTraining.Application.{GetCalendarExportLinks, WalletPasses}

  def call(%{user_id: _} = context, account) do
    with {:ok, calendar} <- GetCalendarExportLinks.call(account) do
      {:ok,
       %{
         wallet: %{
           platforms: WalletPasses.availability(),
           passes: WalletPasses.mine(context)
         },
         calendar: Map.take(calendar, [:https_url, :webcal_url, :download_url, :help]),
         integrations: [
           %{provider: "garmin", status: "unavailable"},
           %{provider: "apple_health", status: "native_only"},
           %{provider: "health_connect", status: "native_only"}
         ]
       }}
    end
  end
end
