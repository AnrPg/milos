defmodule MilosTraining.Application.CheckInKeys do
  @moduledoc """
  The HMAC keys of QR check-in and Wallet (ADR-155), derived from the
  application secret through `Ports.KeyDerivation`:

    * a door key per location, from its seed (rotating the seed changes it);
    * a member-code key per box;
    * one Wallet barcode key.
  """

  alias MilosTraining.Application.KeyDerivation
  alias MilosTraining.Facility

  def door_key(context, location_id) do
    case Facility.get_door_secret(context, location_id) do
      secret when is_binary(secret) ->
        {:ok, KeyDerivation.derive("door-code", location_id <> "|" <> secret)}

      nil ->
        {:error, :location_not_found}
    end
  end

  def member_key(organization_id) when is_binary(organization_id),
    do: KeyDerivation.derive("member-code", organization_id)

  def wallet_key, do: KeyDerivation.derive("wallet-pass", "v1")
end
