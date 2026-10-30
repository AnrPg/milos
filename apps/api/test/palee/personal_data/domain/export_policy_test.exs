defmodule Palee.PersonalData.Domain.ExportPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.PersonalData.Domain.ExportPolicy

  @now ~U[2027-03-10 12:00:00.000000Z]

  defp export(status, hours_ago, extra \\ %{}) do
    Map.merge(
      %{status: status, requested_at: DateTime.add(@now, -hours_ago * 3_600, :second)},
      extra
    )
  end

  test "the first request may start" do
    assert ExportPolicy.can_request?([], @now) == :ok
  end

  test "one request in progress at a time" do
    assert ExportPolicy.can_request?([export("pending", 30)], @now) ==
             {:error, :export_in_progress}
  end

  test "one file a day, saying when the next may start" do
    assert {:error, {:export_rate_limited, retry_at}} =
             ExportPolicy.can_request?([export("ready", 5), export("ready", 50)], @now)

    assert retry_at == DateTime.add(@now, 19 * 3_600, :second)
    assert ExportPolicy.can_request?([export("ready", 24)], @now) == :ok
  end

  test "a failed build does not count" do
    assert ExportPolicy.can_request?([export("failed", 1)], @now) == :ok
  end

  test "a ready file is kept seven days, then shows as expired" do
    expires_at = ExportPolicy.expires_at(@now)
    assert DateTime.diff(expires_at, @now) == 7 * 86_400

    ready = %{status: "ready", expires_at: expires_at}
    assert ExportPolicy.visible_status(ready, @now) == "ready"
    assert ExportPolicy.downloadable?(ready, @now)

    later = DateTime.add(expires_at, 1, :second)
    assert ExportPolicy.visible_status(ready, later) == "expired"
    refute ExportPolicy.downloadable?(ready, later)

    assert ExportPolicy.visible_status(%{status: "pending"}, @now) == "pending"
    refute ExportPolicy.downloadable?(%{status: "failed"}, @now)
  end
end
