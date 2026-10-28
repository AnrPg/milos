defmodule Palee.Application.EnrollCorporateSeat do
  @moduledoc """
  An employee joins their company's corporate plan (ADR-098), either with the
  client's enrollment code or, for email-domain plans, by their account email.
  The company pays for the seat.

  ADR-205: the email-domain path trusts the address only once the login has
  verified it. An unverified account whose email matches is told to confirm
  its email first (`needs_verification` on the offer,
  `:corporate_email_unverified` on enrollment); the code path is unchanged,
  since the code is the employer's own proof.
  """

  alias Palee.{Finance, Identity}

  def call(context, %{id: user_id} = actor, params) do
    with {:ok, client, via} <- find_client(context, actor, params) do
      Finance.enroll_corporate_seat(context, client.id, user_id, %{corporate_enrolled_via: via})
    end
  end

  @doc """
  Whether the client should be offered a company plan without a link: an
  active email-domain plan matches their account email and they hold no seat
  on it yet. Members never see the offer otherwise. While the email is
  unverified the offer says so (`needs_verification: true`), and joining
  waits for the confirmation.
  """
  def offer(context, %{id: user_id} = actor) do
    with %{} = client <- Finance.find_corporate_client(context, %{email: Map.get(actor, :email)}),
         false <-
           context
           |> Finance.list_corporate_seats(client.id)
           |> Enum.any?(&(&1.user_id == user_id and &1.status == "active")) do
      %{
        company_name: client.company_name,
        needs_verification: not Identity.email_verified?(actor)
      }
    else
      _no_offer -> nil
    end
  end

  defp find_client(context, actor, params) do
    case Map.get(params, :code) || Map.get(params, "code") do
      code when is_binary(code) and code != "" ->
        case Finance.find_corporate_client(context, %{enrollment_code: code}) do
          %{} = client -> {:ok, client, "code"}
          nil -> {:error, :corporate_enrollment_not_found}
        end

      _no_code ->
        case Finance.find_corporate_client(context, %{email: Map.get(actor, :email)}) do
          nil ->
            {:error, :corporate_enrollment_not_found}

          client ->
            if Identity.email_verified?(actor),
              do: {:ok, client, "email_domain"},
              else: {:error, :corporate_email_unverified}
        end
    end
  end
end
