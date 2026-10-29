defmodule Palee.Payments.Domain.PackageSale do
  @moduledoc """
  Whether members can see and buy a package online (ADR-248/260/271). The
  one place of the rules: the public package page, the staff package list
  (`online_visibility`) and the automatic «Πωλείται online» all ask here.

  `offer` describes the business's online payments:
  `%{available: boolean, options: map}` (`options`: the account's
  «Τι πληρώνεται online», `AccountOptions`).

  `visibility/2` answers, in order:

    * `inactive` – the package is retired;
    * `free` – a price of 0 is never sold online;
    * `off` – the box sells it only at the front desk;
    * `purpose_off` – the provider is connected but «Τι πληρώνεται online»
      leaves its purpose off;
    * `no_provider` – listed on the package page, bought once the box
      connects online payments;
    * `visible` – listed and bought online.
  """

  alias Palee.Payments.Domain.AccountOptions

  @visibilities ~w(visible free off purpose_off no_provider inactive)

  def visibilities, do: @visibilities

  @doc "ADR-260: which «Τι πληρώνεται online» switch covers a package."
  def purpose(%{package_type: "pt_pack"}), do: "personal_training"
  def purpose(%{package_type: type}) when type in ["drop_in", "trial"], do: "drop_in"
  def purpose(_package), do: "packages"

  def visibility(package, offer) do
    cond do
      package[:active] != true -> "inactive"
      not paid?(package) -> "free"
      package[:sold_online] != true -> "off"
      offer.available and not allowed?(package, offer) -> "purpose_off"
      not offer.available -> "no_provider"
      true -> "visible"
    end
  end

  @doc "Whether the public package page lists it (bought or not yet)."
  def listed?(package, offer), do: visibility(package, offer) in ["visible", "no_provider"]

  @doc """
  ADR-271: whether connecting online payments switches the package on: active,
  paid, its purpose allowed, and its owner never chose for it.
  """
  def opens?(package, offer) do
    package[:active] == true and paid?(package) and package[:sold_online_chosen_at] == nil and
      allowed?(package, offer)
  end

  @doc "ADR-271: a package created while online payments work starts sold online."
  def default_on?(package, offer), do: offer.available and opens?(package, offer)

  defp paid?(package), do: is_integer(package[:base_price_cents]) and package.base_price_cents > 0

  defp allowed?(package, offer),
    do: AccountOptions.allows?(offer[:options] || %{}, purpose(package))
end
