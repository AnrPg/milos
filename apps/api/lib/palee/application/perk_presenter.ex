defmodule Palee.Application.PerkPresenter do
  @moduledoc """
  How partner perks and claims read (ADR-191): to staff (everything, with
  counts, the code pool and the version), to members (never a code before a
  claim) and in the claims export (JSON rows or CSV).
  """

  alias Palee.Application.BoxPhotoCovers
  alias Palee.Perks

  @doc "One perk for staff."
  def staff(context, perk, today), do: context |> staff_all([perk], today) |> hd()

  @doc "Perks for staff, logos and pools read in one go."
  def staff_all(_context, [], _today), do: []

  def staff_all(context, perks, today) do
    logos = logos(perks)
    pools = Perks.code_stats(context, for(%{redemption_method: "code_pool", id: id} <- perks, do: id))

    Enum.map(perks, fn perk ->
      redemption = documents(perk.version).redemption

      perk
      |> common(perk.version, logos, today)
      |> Map.merge(%{
        redemption: redemption,
        all_locations: perk.all_locations,
        location_ids: perk.location_ids,
        claims_count: perk.claims_count,
        uses_count: perk.uses_count,
        remaining: Perks.remaining(perk),
        codes: pool(perk, pools, redemption),
        published_at: perk.published_at,
        paused_at: perk.paused_at,
        expired_at: perk.expired_at,
        inserted_at: perk.inserted_at,
        updated_at: perk.updated_at
      })
    end)
  end

  defp pool(%{redemption_method: "code_pool", id: id}, pools, redemption) do
    stats = Map.get(pools, id, %{total: 0, free: 0})
    Map.put(stats, :low, Perks.pool_low?(redemption, stats.free))
  end

  defp pool(_perk, _pools, _redemption), do: nil

  @doc """
  What anyone shown the perk reads: partner, method, the version's
  benefit, rules and terms, the window and status. `version` is the
  version to show (a claim shows the one it agreed to).
  """
  def common(perk, version, logos, today) do
    docs = documents(version)

    %{
      id: perk.id,
      organization_id: perk.organization_id,
      partner_name: perk.partner_name,
      partner_url: perk.partner_url,
      partner_address: perk.partner_address,
      logo_media_id: perk.logo_media_id,
      logo_url: perk.logo_media_id && Map.get(logos, perk.logo_media_id),
      redemption_method: perk.redemption_method,
      version: version.version,
      benefit: docs.benefit,
      benefit_label: Perks.benefit_label(version.benefit),
      rules: docs.rules,
      terms: version.terms,
      instructions: version.redemption.instructions,
      valid_from: perk.valid_from,
      valid_until: perk.valid_until,
      status: Perks.effective_status(perk, today)
    }
  end

  @doc "A version for the staff history."
  def version(version) do
    docs = documents(version)

    %{
      version: version.version,
      benefit: docs.benefit,
      benefit_label: Perks.benefit_label(version.benefit),
      rules: docs.rules,
      redemption: docs.redemption,
      terms: version.terms,
      created_by_id: version.created_by_id,
      inserted_at: version.inserted_at
    }
  end

  # The documents as plain maps (embedded structs carry no JSON encoder).
  defp documents(version) do
    %{
      benefit: plain(version.benefit),
      rules: plain(version.rules),
      redemption: plain(version.redemption)
    }
  end

  defp plain(%module{} = value) when module in [Date, Time, DateTime, NaiveDateTime], do: value
  defp plain(%{__struct__: _} = struct), do: struct |> Map.from_struct() |> Map.delete(:__meta__) |> plain()
  defp plain(map) when is_map(map) and not is_struct(map), do: Map.new(map, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value

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
      perk_version: claim.perk_version,
      user_id: claim.user_id,
      code: claim.code,
      status: claim.status,
      claimed_at: claim.claimed_at,
      used_at: claim.used_at,
      used_via: claim.used_via,
      revoked_at: claim.revoked_at
    }
  end

  @csv_columns ~w(id user_id display_name handle perk_version code status claimed_at used_at used_via
                  revoked_at)a

  @doc "One row of the claims export."
  def export_row(row), do: Map.take(row, @csv_columns)

  @doc """
  The export as CSV (RFC 4180, CRLF). Cells that a spreadsheet would read
  as a formula (`= + - @`, tab, CR) are prefixed with `'`.
  """
  def csv(rows) do
    header = Enum.map_join(@csv_columns, ",", &Atom.to_string/1)
    lines = Enum.map(rows, fn row -> Enum.map_join(@csv_columns, ",", &cell(Map.get(row, &1))) end)
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
