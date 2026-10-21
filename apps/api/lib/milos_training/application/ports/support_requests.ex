defmodule MilosTraining.Application.Ports.SupportRequests do
  @moduledoc """
  «Χρειάζομαι στήριξη» (vision §7.8): a member asks their buddy for support
  from a Λιγούρα (ADR-159 §5). Wellness only says that the member asked and
  when; who receives it, the quick replies and any summary belong to the
  Buddy milestone (M12), which implements this port. No craving details
  (intensity, causes, notes) are ever passed.
  """

  @type request :: %{user_id: binary(), craving_id: binary(), at: DateTime.t()}

  @callback request(context :: map(), request()) :: :ok | {:error, term()}
end
