defmodule Palee.Email.Domain.DeliveryPolicy do
  @moduledoc """
  Retry rules of `Palee.Workers.DeliverEmailJob` (ADR-203): eight attempts
  with exponential backoff (1, 2, 4 ... 64 minutes, about two hours in all),
  except for an answer the provider means permanently (an SMTP 5xx), which
  is not retried.
  """

  @max_attempts 8
  @base_seconds 60
  @max_backoff_seconds 3_600

  @doc "How many times an email is tried before it is `failed`."
  def max_attempts, do: @max_attempts

  @doc "Seconds before attempt `attempt + 1`."
  def backoff(attempt) when is_integer(attempt) and attempt >= 1,
    do: min(@base_seconds * Integer.pow(2, attempt - 1), @max_backoff_seconds)

  @doc "Whether the error means retrying cannot help."
  def permanent?({:permanent_failure, _host, _message}), do: true
  def permanent?({_stage, {:permanent_failure, _host, _message}}), do: true
  def permanent?({:permanent_failure, _message}), do: true
  def permanent?(:undecryptable), do: true
  def permanent?(_reason), do: false

  @doc "A short, log-safe description of a delivery error for `last_error`."
  def describe(reason) do
    reason |> inspect(limit: 20, printable_limit: 200) |> String.slice(0, 500)
  end
end
