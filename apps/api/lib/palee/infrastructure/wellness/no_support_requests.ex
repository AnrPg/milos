defmodule Palee.Infrastructure.Wellness.NoSupportRequests do
  @moduledoc "Until the buddy exists (M12), a support request is only recorded on the craving."

  @behaviour Palee.Application.Ports.SupportRequests

  @impl true
  def request(_context, _request), do: :ok
end
