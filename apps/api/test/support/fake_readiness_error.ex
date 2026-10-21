defmodule Palee.TestSupport.FakeReadinessError do
  def status, do: {:error, %{database: :ok, redis: :error}}
end
