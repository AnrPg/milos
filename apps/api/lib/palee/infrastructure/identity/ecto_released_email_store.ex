defmodule Palee.Infrastructure.Identity.EctoReleasedEmailStore do
  @moduledoc "Ecto adapter of `Palee.Identity.Ports.ReleasedEmailStore` (ADR-211)."
  @behaviour Palee.Identity.Ports.ReleasedEmailStore

  import Ecto.Query

  alias Palee.Organizations.Domain.InvitationEmail
  alias Palee.Repo

  @table "released_email_reservations"

  @impl true
  def reserve(email, login_id, %DateTime{} = until, %DateTime{} = now) do
    case InvitationEmail.digest(email) do
      nil ->
        :ok

      digest ->
        # Lapsed holds go as new ones are made; there is never more than one
        # row per address.
        @table |> where([r], r.reserved_until <= ^now) |> Repo.delete_all()

        Repo.insert_all(
          @table,
          [
            %{
              address_digest: digest,
              login_id: Ecto.UUID.dump!(login_id),
              reserved_until: until,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: {:replace, [:login_id, :reserved_until, :updated_at]},
          conflict_target: [:address_digest]
        )

        :ok
    end
  end

  @impl true
  def reserved_for_other?(email, login_id, %DateTime{} = now) do
    case InvitationEmail.digest(email) do
      nil ->
        false

      digest ->
        @table
        |> where([r], r.address_digest == ^digest and r.reserved_until > ^now)
        |> then(fn query ->
          if login_id,
            do: where(query, [r], r.login_id != ^Ecto.UUID.dump!(login_id)),
            else: query
        end)
        |> Repo.exists?()
    end
  end

  @impl true
  def release(email, login_id) do
    case InvitationEmail.digest(email) do
      nil ->
        :ok

      digest ->
        @table
        |> where([r], r.address_digest == ^digest and r.login_id == ^Ecto.UUID.dump!(login_id))
        |> Repo.delete_all()

        :ok
    end
  end
end
