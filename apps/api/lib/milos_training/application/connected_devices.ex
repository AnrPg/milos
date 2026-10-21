defmodule MilosTraining.Application.ConnectedDevices do
  @moduledoc """
  Εγώ › Συνδεδεμένες συσκευές (ADR-155, decision 7; vision §8): the person's
  Wallet cards at every box (platform, when added, revoke), whether each
  Wallet platform can issue cards on this server, the calendar (ICS) feed
  links (reset with `POST /api/calendar/export-links/regenerate`), and the
  health integrations.

  Nothing here pretends: Garmin (ADR-161) is `unavailable` («Σύντομα») on a
  server without Garmin credentials, and otherwise shows its connection
  (status, last sync, what syncs, history import, error); Apple Health and
  Health Connect are `native_only` (they come with the native apps).
  """

  alias MilosTraining.Application.{GarminConnection, GetCalendarExportLinks, WalletPasses}

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
           GarminConnection.row(context),
           %{provider: "apple_health", status: "native_only"},
           %{provider: "health_connect", status: "native_only"}
         ]
       }}
    end
  end
end
