defmodule MilosTraining.Application.ResolveJobPlatformContext do
  @moduledoc """
  Re-resolves a vendor's platform context inside a background job. Fails closed
  with `:vendor_required` when the account is gone or no longer a vendor.
  """

  alias MilosTraining.{Identity, Organizations}

  def call(user_id, worker) when is_binary(user_id) and is_binary(worker) do
    case Identity.find_by_id(user_id) do
      nil -> {:error, :vendor_required}
      account -> Organizations.resolve_platform_context(account, %{worker: worker})
    end
  end

  def call(_user_id, _worker), do: {:error, :vendor_required}
end
