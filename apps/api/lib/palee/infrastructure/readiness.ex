defmodule Palee.Infrastructure.Readiness do
  def status do
    impl().status()
  end

  defp impl do
    Application.get_env(
      :palee,
      :readiness_checker,
      Palee.Infrastructure.Readiness.Live
    )
  end
end
