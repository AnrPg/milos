defmodule Palee.Buddies.Ports.SupportScheduler do
  @moduledoc """
  Schedules the timed steps of a support request (ADR-160 §2): telling the
  buddies once the 5-second undo has passed (`:deliver`) and the no-reply
  card after ten minutes (`:nudge`). Each step is idempotent, so a retried
  or duplicated job changes nothing.
  """

  @callback schedule(user_id :: binary(), request_id :: binary(), [{atom(), DateTime.t()}]) :: :ok
end
