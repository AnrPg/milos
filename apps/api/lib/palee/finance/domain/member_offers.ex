defmodule Palee.Finance.Domain.MemberOffers do
  @moduledoc """
  The promotion codes a box shows its members (Εγώ › Πληρωμές ›
  Προσφορές), as a pure policy over campaigns and codes.

  A campaign is shown when the box marked it `params.member_visible`, it is
  active and `today` falls inside its optional start and end dates. Each of
  its active codes becomes one offer the member can use at the desk or when
  renewing. Nothing here redeems a code.
  """

  @doc "Whether the box shows this campaign to members on `today`."
  def visible?(campaign, %Date{} = today) do
    campaign.active != false and member_visible?(campaign) and
      (is_nil(campaign.starts_on) or Date.compare(campaign.starts_on, today) != :gt) and
      (is_nil(campaign.ends_on) or Date.compare(campaign.ends_on, today) != :lt)
  end

  @doc "Whether the box flagged the campaign for members."
  def member_visible?(campaign), do: (Map.get(campaign, :params) || %{})["member_visible"] == true

  @doc """
  One offer per active code of each campaign shown on `today`, in campaign
  order. `codes` may hold the codes of any campaigns; the rest are ignored.
  """
  def available(campaigns, codes, %Date{} = today) do
    by_campaign = Enum.group_by(codes, & &1.promotion_campaign_id)

    campaigns
    |> Enum.filter(&visible?(&1, today))
    |> Enum.flat_map(fn campaign ->
      by_campaign
      |> Map.get(campaign.id, [])
      |> Enum.filter(&(&1.active != false))
      |> Enum.map(&offer(campaign, &1))
    end)
  end

  defp offer(campaign, code) do
    %{
      id: code.id,
      code: code.code,
      campaign_name: campaign.name,
      description: campaign.description,
      discount_type: code.discount_type,
      discount_value: code.discount_value,
      ends_on: campaign.ends_on
    }
  end
end
