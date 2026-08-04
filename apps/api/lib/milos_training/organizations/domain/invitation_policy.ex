defmodule MilosTraining.Organizations.Domain.InvitationPolicy do
  @moduledoc false

  @minimum_lifetime_seconds 300
  @maximum_lifetime_seconds 604_800

  def valid_lifetime?(seconds) when is_integer(seconds) do
    seconds >= @minimum_lifetime_seconds and seconds <= @maximum_lifetime_seconds
  end

  def valid_lifetime?(_seconds), do: false

  def valid_expiry?(%DateTime{} = expires_at, %DateTime{} = issued_at) do
    expires_at
    |> DateTime.diff(issued_at, :second)
    |> valid_lifetime?()
  end

  def valid_expiry?(_expires_at, _issued_at), do: false

  def state(invitation, now) when is_map(invitation) do
    cond do
      present?(Map.get(invitation, :revoked_at)) -> :revoked
      present?(Map.get(invitation, :redeemed_at)) -> :redeemed
      expired?(Map.get(invitation, :expires_at), now) -> :expired
      true -> :active
    end
  end

  def redeemable?(invitation, now), do: state(invitation, now) == :active

  defp expired?(%DateTime{} = expires_at, %DateTime{} = now) do
    DateTime.compare(expires_at, now) in [:lt, :eq]
  end

  defp expired?(_expires_at, _now), do: true

  defp present?(nil), do: false
  defp present?(_value), do: true
end
