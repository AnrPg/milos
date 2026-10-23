defmodule Palee.Perks.Domain.Methods.SharedCode do
  @moduledoc "One code the partner gave, the same for everyone (ADR-191 §2)."
  @behaviour Palee.Perks.Domain.RedemptionMethod

  @impl true
  def key, do: "shared_code"

  @impl true
  def validate(settings) do
    case Map.get(settings, :shared_code) do
      code when is_binary(code) and code != "" -> []
      _missing -> [shared_code: "can't be blank"]
    end
  end

  @impl true
  def issue, do: :shared
  @impl true
  def verifiable?, do: false
  @impl true
  def ready(_facts), do: :ok
  @impl true
  def reveal(_settings, code), do: %{code: code, url: nil, show_membership: false}
end
