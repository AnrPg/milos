defmodule Palee.Application.CorporateSeats do
  @moduledoc """
  ADR-205: a corporate seat taken by the email domain (ADR-098) lasts only
  while the login's email stays in that domain.

  The email-change flow calls `email_changed/3` once the new address is in
  place. In every business where one of the login's profiles is a member,
  the seats they took by domain whose company's domain no longer matches
  the new address end today (the company stops paying from the next
  period, the member keeps any other plan). Seats taken with the company's
  code, and seats an admin added, are kept: those never relied on the
  address. A member who still works there joins again with the code, or by
  the new address once it is verified.
  """

  require Logger

  alias Palee.{Finance, Identity, Organizations}

  @doc "Ends the domain seats the new email no longer qualifies for; returns how many."
  def email_changed(login_id, old_email, new_email) when is_binary(login_id) do
    if same_address?(old_email, new_email) do
      {:ok, 0}
    else
      user_ids = login_id |> Identity.list_profiles() |> Enum.map(& &1.id)

      ended =
        user_ids
        |> Organizations.list_membership_organization_ids()
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.map(&end_seats(&1, user_ids, new_email))
        |> Enum.sum()

      {:ok, ended}
    end
  end

  defp end_seats(organization_id, user_ids, new_email) do
    case Finance.end_email_domain_seats(%{organization_id: organization_id}, user_ids, new_email) do
      {:ok, ended} ->
        length(ended)

      {:error, reason} ->
        Logger.warning(
          "corporate domain seats not ended in #{organization_id}: #{inspect(reason)}"
        )

        0
    end
  end

  defp same_address?(old, new) when is_binary(old) and is_binary(new),
    do: String.downcase(String.trim(old)) == String.downcase(String.trim(new))

  defp same_address?(_old, _new), do: false
end
