defmodule Palee.Infrastructure.Imports.SystemClock do
  @moduledoc "The system clock for imports (ADR-254)."

  @behaviour Palee.Imports.Ports.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
