defmodule MilosTraining.Application.Ports.SupportRequests do
  @moduledoc """
  «Χρειάζομαι στήριξη» from Λιγούρα (ADR-159 §3, ADR-160). Wellness stamps
  the craving and asks this port to tell the member's buddies; the buddy
  side decides who receives it. Only the craving's id crosses, as an opaque
  reference: intensity, causes, outcome and notes never leave Wellness.

  Configured under `:support_requests`; the adapter is
  `MilosTraining.Application.SupportRequests` (M12).
  """

  @type context :: map()
  @type request :: %{
          required(:user_id) => binary(),
          optional(:craving_id) => binary() | nil,
          optional(:at) => DateTime.t()
        }

  @callback request(context(), request()) :: :ok | {:error, term()}
end
