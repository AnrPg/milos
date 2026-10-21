defmodule Palee.Infrastructure.Referrals.EctoReferralStore do
  @moduledoc "Ecto adapter of invite codes and invites (ADR-156)."

  @behaviour Palee.Referrals.Ports.ReferralStore

  import Ecto.Query

  alias Palee.Referrals.{ReferralAttribution, ReferralCode}
  alias Palee.Repo

  @impl true
  def get_active_code(%{organization_id: organization_id}, user_id) do
    ReferralCode
    |> where([c], c.organization_id == ^organization_id and c.user_id == ^user_id)
    |> where([c], is_nil(c.revoked_at))
    |> Repo.one()
  end

  @impl true
  def insert_code(_context, attrs), do: attrs |> ReferralCode.create_changeset() |> Repo.insert()

  @impl true
  def revoke_code(_context, code, at),
    do: code |> ReferralCode.revoke_changeset(at) |> Repo.update()

  @impl true
  def resolve_code(code) when is_binary(code) do
    case Repo.query!(
           """
           SELECT code_id, organization_id, user_id, slug, name, logo_url, primary_color, published
           FROM palee_referral_invite($1)
           """,
           [code]
         ) do
      %{rows: [[code_id, organization_id, user_id, slug, name, logo_url, color, published]]} ->
        %{
          code_id: Ecto.UUID.load!(code_id),
          organization_id: Ecto.UUID.load!(organization_id),
          user_id: Ecto.UUID.load!(user_id),
          box: %{
            organization_id: Ecto.UUID.load!(organization_id),
            slug: slug,
            name: name,
            logo_url: logo_url,
            primary_color: color,
            published: published
          }
        }

      _none ->
        nil
    end
  end

  @impl true
  def get_attribution(%{organization_id: organization_id}, id) do
    ReferralAttribution
    |> where([a], a.organization_id == ^organization_id and a.id == ^id)
    |> Repo.one()
  end

  @impl true
  def get_attribution_for(%{organization_id: organization_id}, user_id) do
    Repo.get_by(ReferralAttribution, organization_id: organization_id, referred_user_id: user_id)
  end

  @impl true
  def insert_attribution(_context, attrs),
    do: attrs |> ReferralAttribution.create_changeset() |> Repo.insert()

  @impl true
  def replace_attribution(_context, attribution, attrs) do
    fresh =
      Map.merge(
        %{
          event_at: nil,
          trial_at: nil,
          joined_at: nil,
          paid_at: nil,
          status: "open",
          qualified_at: nil,
          void_reason: nil,
          finance_referral_event_id: nil,
          friend_gift_applied_at: nil,
          friend_gift_applied_by_id: nil,
          previous_referrer_user_id: nil,
          reassigned_at: nil,
          reassigned_by_id: nil,
          community_event_id: nil,
          notes: nil
        },
        attrs
      )

    attribution |> ReferralAttribution.update_changeset(fresh) |> Repo.update()
  end

  @impl true
  def update_attribution(_context, attribution, changes),
    do: attribution |> ReferralAttribution.update_changeset(changes) |> Repo.update()

  @impl true
  def list_attributions(%{organization_id: organization_id}, filters) do
    ReferralAttribution
    |> where([a], a.organization_id == ^organization_id)
    |> referrer(Map.get(filters, :referrer_user_id))
    |> statuses(Map.get(filters, :statuses))
    |> awaiting_review(Map.get(filters, :awaiting_review))
    |> order_by([a], desc: a.attributed_at, desc: a.id)
    |> limit(^Map.get(filters, :limit, 200))
    |> Repo.all()
  end

  defp referrer(query, nil), do: query
  defp referrer(query, id), do: where(query, [a], a.referrer_user_id == ^id)

  defp statuses(query, nil), do: query
  defp statuses(query, list), do: where(query, [a], a.status in ^list)

  # Qualified invites whose Finance referral still waits for the admin.
  defp awaiting_review(query, true) do
    from(a in query,
      join: e in "referral_events",
      on: e.id == a.finance_referral_event_id,
      where: a.status == "qualified" and e.status == "pending"
    )
  end

  defp awaiting_review(query, _), do: query

  @impl true
  def stats(%{organization_id: organization_id}, since) do
    ReferralAttribution
    |> where([a], a.organization_id == ^organization_id and a.attributed_at >= ^since)
    |> group_by([a], a.status)
    |> select([a], {a.status, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def with_friend_lock(%{organization_id: organization_id}, user_id, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
        "referral:#{organization_id}:#{user_id}"
      ])

      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        result -> result
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _reason} = error -> error
    end
  end
end
