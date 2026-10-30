defmodule Palee.Application.Payments.Webhooks do
  @moduledoc """
  ADR-246: provider webhooks. Each business's account has its own URL
  (`/api/webhooks/payments/<organization>/<account>`), so a notification
  never needs a lookup across businesses; whatever it says is confirmed by
  asking the provider.
  """

  alias Palee.Application.PublicURL
  alias Palee.Payments

  def url(organization_id, account_id) do
    (PublicURL.base_url() |> String.trim_trailing("/")) <>
      "/api/webhooks/payments/#{organization_id}/#{account_id}"
  end

  def handle(organization_id, account_id, request, now \\ DateTime.utc_now()) do
    with {:ok, organization_id} <- cast(organization_id),
         {:ok, account_id} <- cast(account_id) do
      Payments.handle_webhook(%{organization_id: organization_id}, account_id, request, now)
    end
  end

  defp cast(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
