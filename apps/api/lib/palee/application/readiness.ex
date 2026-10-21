defmodule Palee.Application.Readiness do
  def status, do: Application.fetch_env!(:palee, :readiness_checker).status()
end
