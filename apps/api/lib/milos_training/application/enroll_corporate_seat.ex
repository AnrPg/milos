defmodule MilosTraining.Application.EnrollCorporateSeat do
  @moduledoc """
  An employee joins their company's corporate plan (ADR-098), either with the
  client's enrollment code or, for email-domain plans, by their account email.
  The company pays for the seat.
  """

  alias MilosTraining.Finance

  def call(context, %{id: user_id} = actor, params) do
    with %{} = client <-
           find_client(context, actor, params) || {:error, :corporate_enrollment_not_found} do
      Finance.enroll_corporate_seat(context, client.id, user_id, %{})
    end
  end

  @doc """
  Whether the client should be offered a company plan without a link: an
  active email-domain plan matches their account email and they hold no seat
  on it yet. Members never see the offer otherwise.
  """
  def offer(context, %{id: user_id} = actor) do
    with %{} = client <- Finance.find_corporate_client(context, %{email: Map.get(actor, :email)}),
         false <-
           context
           |> Finance.list_corporate_seats(client.id)
           |> Enum.any?(&(&1.user_id == user_id and &1.status == "active")) do
      %{company_name: client.company_name}
    else
      _no_offer -> nil
    end
  end

  defp find_client(context, actor, params) do
    case Map.get(params, :code) || Map.get(params, "code") do
      code when is_binary(code) and code != "" ->
        Finance.find_corporate_client(context, %{enrollment_code: code})

      _no_code ->
        Finance.find_corporate_client(context, %{email: Map.get(actor, :email)})
    end
  end
end
