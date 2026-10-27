defmodule Palee.Identity.LoginDeviceStore do
  @moduledoc "Facade over the login device storage adapter (ADR-208)."
  @behaviour Palee.Identity.Ports.LoginDeviceStore

  @impl true
  def remember(login_id, device_hash, description, source, now),
    do: impl().remember(login_id, device_hash, description, source, now)

  defp impl, do: Application.fetch_env!(:palee, :login_device_store)
end
