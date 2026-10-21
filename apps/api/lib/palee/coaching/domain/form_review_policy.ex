defmodule Palee.Coaching.Domain.FormReviewPolicy do
  @moduledoc "Pure rules for form reviews (ADR-098)."

  @doc "Ledger request for one form review."
  def entitlement_request(review_id, %Date{} = occurred_on) do
    %{
      capability: :request_form_reviews,
      allowance: :form_reviews,
      quantity: 1,
      occurred_on: occurred_on,
      source_context: "coaching",
      source_id: review_id,
      idempotency_key: "form-review:#{review_id}"
    }
  end

  @doc "Videos are linked from the client's own host, never uploaded."
  def valid_link?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _other -> false
    end
  end

  def valid_link?(_url), do: false

  def can_withdraw?(%{status: "submitted", user_id: user_id}, user_id), do: :ok
  def can_withdraw?(%{status: "submitted"}, _user_id), do: {:error, :forbidden}
  def can_withdraw?(_review, _user_id), do: {:error, :form_review_closed}

  def can_review?(%{status: "submitted"}), do: :ok
  def can_review?(_review), do: {:error, :form_review_closed}
end
