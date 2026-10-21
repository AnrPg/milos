defmodule MilosTraining.Organizations.Domain.Provider do
  @moduledoc """
  Everyone who provides a member's training (ADR-162, vision §7.10): a gym
  or an independent coach (a one-person organization). Built from the
  member's memberships; a provider is **former** once the membership is
  suspended or revoked, or the organization closed (board 17, Q6). Box ▾
  lists the active ones, «Παλιοί πάροχοι» the former, and every
  cross-provider view labels entries from this directory.
  """

  @kinds ~w(gym coach)

  def kinds, do: @kinds

  @doc "One provider from a `milos_my_providers()` row."
  def from_row(row) do
    %{
      organization_id: row.organization_id,
      name: row.name,
      slug: row.slug,
      kind: if(row.provider_kind in @kinds, do: row.provider_kind, else: "gym"),
      logo_url: row.logo_url,
      primary_color: row.primary_color,
      roles: row.roles || [],
      joined_at: row.joined_at,
      ended_at: row.ended_at,
      former: row.membership_status != "active" or row.organization_status != "active"
    }
  end

  @doc "Active providers by name, then former ones, most recently ended first."
  def split(providers) do
    {former, active} = Enum.split_with(providers, & &1.former)

    {Enum.sort_by(active, &String.downcase(&1.name || "")),
     Enum.sort_by(former, &sort_key(&1.ended_at), :desc)}
  end

  @doc "`%{organization_id => %{name, former}}` for labelling entries."
  def directory(providers),
    do: Map.new(providers, &{&1.organization_id, %{name: &1.name, former: &1.former}})

  @doc """
  The provider Box opens on: the remembered one while still active, else the
  first active provider, else nil.
  """
  def selected(active, remembered_id) do
    ids = Enum.map(active, & &1.organization_id)

    cond do
      remembered_id in ids -> remembered_id
      ids != [] -> hd(ids)
      true -> nil
    end
  end

  @doc "Ids of the active providers."
  def active_ids(providers), do: for(%{former: false} = p <- providers, do: p.organization_id)

  defp sort_key(nil), do: ""
  defp sort_key(%NaiveDateTime{} = at), do: NaiveDateTime.to_iso8601(at)
  defp sort_key(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
