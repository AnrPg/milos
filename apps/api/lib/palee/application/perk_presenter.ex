defmodule Palee.Application.PerkPresenter do
  @moduledoc """
  How partner perks and claims read (ADR-191): to staff (everything, with
  counts and the code pool), to members (never the code before a claim) and
  in the claims export (JSON rows or CSV).
  """

  alias Palee.Application.BoxPhotoCovers
  alias Palee.Perks

  @doc "One perk for staff."
  def staff(context, perk, today), do: context |> staff_all([perk], today) |> hd()

  @doc "Perks for staff, logos and pools read in one go."
  def staff_all(_context, [], _today), do: []

  def staff_all(context, perks, today) do
    logos = logos(perks)
    pools = Perks.code_stats(context, for(%{redemption_method: "unique_code", id: id} <- perks, do: id))

    Enum.map(perks, fn perk ->
      perk
      |> common(logos, today)
      |> Map.merge(%{
        shared_code: perk.shared_code,
        max_claims: perk.max_claims,
        max_claims_per_member: perk.max_claims_per_member,
        audience: perk.audience,
        package_ids: perk.package_ids,
        all_locations: perk.all_locations,
        location_ids: perk.location_ids,
        claims_count: perk.claims_count,
        uses_count: perk.uses_count,
        remaining: Perks.remaining(perk),
        codes:
          if(perk.redemption_method == "unique_code",
            do: Map.get(pools, perk.id, %{total: 0, free: 0})
          ),
        published_at: perk.published_at,
        paused_at: perk.paused_at,
        expired_at: perk.expired_at,
        inserted_at: perk.inserted_at,
        updated_at: perk.updated_at
      })
    end)
  end

  @doc "What anyone shown the perk reads: partner, benefit, method, terms, window."
  def common(perk, logos, today) do
    %{
      id: perk.id,
      organization_id: perk.organization_id,
      partner_name: perk.partner_name,
      partner_url: perk.partner_url,
      partner_address: perk.partner_address,
      logo_media_id: perk.logo_media_id,
      logo_url: perk.logo_media_id && Map.get(logos, perk.logo_media_id),
      benefit_type: perk.benefit_type,
      benefit_value: perk.benefit_value,
      benefit_text: perk.benefit_text,
      benefit_label: Perks.benefit_label(perk),
      currency: perk.currency,
      redemption_method: perk.redemption_method,
      terms: perk.terms,
      valid_from: perk.valid_from,
      valid_until: perk.valid_until,
      status: Perks.effective_status(perk, today)
    }
  end

  @doc "Logo URLs by media id."
  def logos(perks) do
    perks
    |> Enum.map(&%{organization_id: &1.organization_id, cover_media_id: &1.logo_media_id})
    |> BoxPhotoCovers.urls()
  end

  @doc "A claim as staff see it after acting on it."
  def staff_claim(claim) do
    %{
      id: claim.id,
      perk_id: claim.perk_id,
      user_id: claim.user_id,
      code: claim.code,
      status: claim.status,
      claimed_at: claim.claimed_at,
      used_at: claim.used_at,
      used_via: claim.used_via,
      revoked_at: claim.revoked_at
    }
  end

  @doc "One row of the claims export."
  def export_row(row),
    do:
      Map.take(row, [
        :id,
        :user_id,
        :display_name,
        :handle,
        :code,
        :status,
        :claimed_at,
        :used_at,
        :used_via,
        :revoked_at
      ])

  @csv_columns ~w(id user_id display_name handle code status claimed_at used_at used_via revoked_at)a

  @doc """
  The export as CSV (RFC 4180, CRLF). Cells that a spreadsheet would read
  as a formula (`= + - @`, tab, CR) are prefixed with `'`.
  """
  def csv(rows) do
    header = Enum.map_join(@csv_columns, ",", &Atom.to_string/1)

    lines =
      Enum.map(rows, fn row ->
        Enum.map_join(@csv_columns, ",", &cell(Map.get(row, &1)))
      end)

    Enum.join([header | lines], "\r\n") <> "\r\n"
  end

  defp cell(nil), do: ""
  defp cell(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp cell(value) when is_binary(value), do: value |> defuse() |> quote_cell()
  defp cell(value), do: value |> to_string() |> quote_cell()

  defp defuse(<<first, _rest::binary>> = value) when first in [?=, ?+, ?-, ?@, ?\t, ?\r],
    do: "'" <> value

  defp defuse(value), do: value

  defp quote_cell(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end
end
