defmodule MilosTraining.Organizations.Domain.TenantTopics do
  @moduledoc false

  def organization(organization_id, suffix)
      when is_binary(organization_id) and is_binary(suffix),
      do: "org:#{organization_id}:#{suffix}"

  def user(user_id, suffix) when is_binary(user_id) and is_binary(suffix),
    do: "user:#{user_id}:#{suffix}"
end
