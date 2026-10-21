defmodule MilosTraining.Application.CheckInKeys do
  @moduledoc """
  The HMAC keys of QR check-in and Wallet (ADR-155), derived from the
  application secret through `Ports.KeyDerivation`:

    * a door key per location, from its seed (rotating the seed changes it);
    * a poster key per location, from its poster seed;
    * an NFC tag key per location, from its tag seed (ADR-173);
    * a member-code key per box (rotating and static personal codes);
    * one Wallet key (the PassKit authentication tokens).
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

  def poster_key(context, location_id) do
    case Facility.get_poster(context, location_id) do
      %{secret: secret} = poster when is_binary(secret) ->
        {:ok, KeyDerivation.derive("door-poster", location_id <> "|" <> secret), poster}

      nil ->
        {:error, :location_not_found}
    end
  end

  def nfc_key(context, location_id) do
    case Facility.get_nfc_tag(context, location_id) do
      %{secret: secret} = tag when is_binary(secret) ->
        {:ok, KeyDerivation.derive("door-nfc", location_id <> "|" <> secret), tag}

      nil ->
        {:error, :location_not_found}
    end
  end

  def member_key(organization_id) when is_binary(organization_id),
    do: KeyDerivation.derive("member-code", organization_id)

  def wallet_key, do: KeyDerivation.derive("wallet-pass", "v1")
end
