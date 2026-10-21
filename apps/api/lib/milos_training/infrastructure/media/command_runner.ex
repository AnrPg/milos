defmodule MilosTraining.Infrastructure.Media.CommandRunner do
  @moduledoc """
  Runs an external media tool (ImageMagick, ffmpeg) with a wall-clock limit
  (ADR-157). A tool still running when the limit passes is killed by its OS
  pid, so a hostile or broken upload cannot hold a worker forever.
  """

  @max_output 64 * 1_024

  @doc "`{:ok, output}` on exit status 0, `{:error, {:exit, status, output}}` or `{:error, :timeout}`."
  def run(executable, args, timeout_ms) when is_binary(executable) and is_list(args) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: args
      ])

    # A tool that exits at once can close its port before we ask, and then
    # there is no pid left to kill.
    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        nil -> nil
      end

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    collect(port, os_pid, deadline, [])
  end

  defp collect(port, os_pid, deadline, acc) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, os_pid, deadline, keep(acc, data))

      {^port, {:exit_status, 0}} ->
        {:ok, output(acc)}

      {^port, {:exit_status, status}} ->
        {:error, {:exit, status, output(acc)}}
    after
      remaining ->
        kill(os_pid)
        close(port)
        {:error, :timeout}
    end
  end

  defp keep(acc, data) do
    if IO.iodata_length(acc) > @max_output, do: acc, else: [acc, data]
  end

  defp output(acc), do: IO.iodata_to_binary(acc)

  defp kill(os_pid) when is_integer(os_pid) do
    System.cmd("kill", ["-9", Integer.to_string(os_pid)], stderr_to_stdout: true)
  rescue
    _error -> :ok
  end

  defp kill(_os_pid), do: :ok

  defp close(port) do
    Port.close(port)
  rescue
    _error -> :ok
  end
end
