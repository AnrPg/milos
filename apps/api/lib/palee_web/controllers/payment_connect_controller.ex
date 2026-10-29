defmodule PaleeWeb.PaymentConnectController do
  @moduledoc """
  Where the payment provider sends the business owner back after a
  one-button connection (ADR-261). No session: the signed `state` names
  the business and the person, who must still be allowed to manage
  billing. Always redirects to the settings page with the outcome.
  """

  use PaleeWeb, :controller

  alias Palee.Application.Payments.OnlinePayments

  def callback(conn, params) do
    {:ok, path} = OnlinePayments.connect_callback(params)
    redirect(conn, to: path)
  end
end
