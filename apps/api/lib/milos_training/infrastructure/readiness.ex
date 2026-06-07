defmodule MilosTraining.Infrastructure.Readiness do
  def status do
    impl().status()
  end

  defp impl do
    Application.get_env(
      :milos_training,
      :readiness_checker,
      MilosTraining.Infrastructure.Readiness.Live
    )
  end
end
