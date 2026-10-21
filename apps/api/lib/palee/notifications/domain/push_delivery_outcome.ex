defmodule Palee.Notifications.Domain.PushDeliveryOutcome do
  @moduledoc """
  Classifies a push dispatcher result into an analytics outcome and a coarse,
  PII-free reason class (ADR-123). Raw provider errors (which can echo the
  endpoint or response body) are never stored; only the class is.
  """

  @doc "Returns `{outcome, reason_class}` with outcome in sent/expired/failed."
  def classify(:ok), do: {"sent", nil}
  def classify({:error, :expired}), do: {"expired", "subscription_expired"}
  def classify({:error, :push_not_configured}), do: {"failed", "not_configured"}
  def classify({:error, {:http_error, 429, _body}}), do: {"failed", "rate_limited"}
  def classify({:error, {:http_error, 413, _body}}), do: {"failed", "payload_too_large"}

  def classify({:error, {:http_error, status, _body}}) when status in 400..499,
    do: {"failed", "client_error"}

  def classify({:error, {:http_error, status, _body}}) when status in 500..599,
    do: {"failed", "server_error"}

  def classify({:error, :timeout}), do: {"failed", "timeout"}
  def classify({:error, %{reason: :timeout}}), do: {"failed", "timeout"}
  def classify({:error, _reason}), do: {"failed", "unknown"}
  def classify(_other), do: {"failed", "unknown"}
end
