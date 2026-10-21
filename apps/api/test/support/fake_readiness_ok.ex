defmodule Palee.TestSupport.FakeReadinessOk do
  def status, do: {:ok, %{database: :ok, redis: :ok}}
end
