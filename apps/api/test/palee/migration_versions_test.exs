defmodule Palee.MigrationVersionsTest do
  use ExUnit.Case, async: true

  # Ecto records migrations by version only: two files sharing a timestamp
  # means every one after the first is silently skipped on deploy.
  test "every migration has a unique version" do
    duplicates =
      "priv/repo/migrations/*.exs"
      |> Path.wildcard()
      |> Enum.map(&(&1 |> Path.basename() |> String.split("_", parts: 2) |> hd()))
      |> Enum.frequencies()
      |> Enum.filter(fn {_version, count} -> count > 1 end)

    assert duplicates == []
  end
end
