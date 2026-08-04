defmodule MilosTraining.Application.ResolvePlatformContext do
  alias MilosTraining.Organizations

  def call(account, request_metadata \\ %{}),
    do: Organizations.resolve_platform_context(account, request_metadata)
end
