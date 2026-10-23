defmodule Palee.Application.NicknameAvailability do
  @moduledoc "Kept for the original endpoint; the @handle is the unique name (ADR-187)."
  alias Palee.Application.AccountProfiles

  def call(nickname) when is_binary(nickname) do
    with {:ok, %{available: available}} <- AccountProfiles.handle_availability(nickname) do
      {:ok, available}
    end
  end

  def call(_nickname), do: {:error, :bad_request}
end
