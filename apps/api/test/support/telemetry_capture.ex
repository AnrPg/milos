defmodule MilosTraining.TestSupport.TelemetryCapture do
  @moduledoc """
  Forwards telemetry events emitted by the calling test process (and only that
  process, so async tests do not observe each other) as
  `{:telemetry_event, event, measurements, metadata}` messages.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  def capture(events) do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_event/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  @doc false
  def handle_event(event, measurements, metadata, test_pid) do
    if self() == test_pid, do: send(test_pid, {:telemetry_event, event, measurements, metadata})
  end
end
