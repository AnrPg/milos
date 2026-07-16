defmodule MilosTraining.Application.Readiness do
  def status, do: Application.fetch_env!(:milos_training, :readiness_checker).status()
end
