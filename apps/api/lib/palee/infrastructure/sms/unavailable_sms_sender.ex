defmodule Palee.Infrastructure.Sms.UnavailableSmsSender do
  @moduledoc """
  The production SMS adapter while no provider key is set (ADR-280 §3): the
  phone step answers `sms_unavailable` instead of crashing.
  """

  @behaviour Palee.Application.Ports.SmsSender

  @impl true
  def deliver(_message), do: {:error, :sms_unavailable}
end
