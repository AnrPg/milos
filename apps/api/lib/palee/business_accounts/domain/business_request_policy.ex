defmodule Palee.BusinessAccounts.Domain.BusinessRequestPolicy do
  @moduledoc """
  ADR-184: requests to the platform team.

  - `conversion`: a plain account asks to become a business (a gym or an
    independent coach). Approving it creates the business, in demo mode,
    owned by the requester.
  - `activation`: the owner of a demo business asks for it to be activated.
    Filed automatically by business sign-up; the vendor answers by issuing
    an activation link, and redeeming it completes the request.

  A person has at most one pending request of each kind. Only a pending
  request can be cancelled (by the requester) or decided (by a vendor).

  Self-serve business creation is a sign-up step: an account may open a
  business itself only within `signup_window_seconds/0` of registering.
  Older accounts file a conversion request instead.
  """

  @kinds ~w(conversion activation)
  @business_kinds ~w(gym coach)
  @statuses ~w(pending approved declined cancelled completed)
  @signup_window_seconds 30 * 60

  def kinds, do: @kinds
  def business_kinds, do: @business_kinds
  def statuses, do: @statuses
  def signup_window_seconds, do: @signup_window_seconds

  @doc "Whether an account registered at `registered_at` is still signing up at `now`."
  def signing_up?(%NaiveDateTime{} = registered_at, %DateTime{} = now),
    do: signing_up?(DateTime.from_naive!(registered_at, "Etc/UTC"), now)

  def signing_up?(%DateTime{} = registered_at, %DateTime{} = now),
    do: DateTime.diff(now, registered_at, :second) <= @signup_window_seconds

  def signing_up?(_registered_at, _now), do: false

  @doc """
  The fields of a conversion request (or of the business a sign-up opens),
  trimmed and checked: `business_kind`, `business_name` (2 to 120), and
  optional `city` (80), `phone` (40) and `message` (1000).
  """
  def normalize_details(params) do
    kind = text(params, :business_kind)
    name = text(params, :business_name)

    attrs = %{
      business_kind: kind,
      business_name: name,
      city: text(params, :city),
      phone: text(params, :phone),
      message: text(params, :message)
    }

    cond do
      kind not in @business_kinds ->
        {:error, :invalid_business_kind}

      is_nil(name) or String.length(name) not in 2..120 ->
        {:error, :invalid_name}

      too_long?(attrs.city, 80) or too_long?(attrs.phone, 40) ->
        {:error, :invalid_business_request}

      too_long?(attrs.message, 1000) ->
        {:error, :invalid_business_request}

      true ->
        {:ok, attrs}
    end
  end

  @doc "Whether the request can still be cancelled or decided."
  def open?(%{status: "pending"}), do: true
  def open?(_request), do: false

  @doc "A vendor's decision: `approve` or `decline`, with an optional note (500)."
  def normalize_decision(params) do
    decision = text(params, :decision)
    note = text(params, :note)

    cond do
      decision not in ["approve", "decline"] -> {:error, :invalid_decision}
      too_long?(note, 500) -> {:error, :invalid_business_request}
      true -> {:ok, %{decision: decision, note: note}}
    end
  end

  defp too_long?(nil, _max), do: false
  defp too_long?(value, max), do: String.length(value) > max

  defp text(params, key) do
    case Map.get(params, key, Map.get(params, Atom.to_string(key))) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_atom(value) and not is_nil(value) and not is_boolean(value) ->
        Atom.to_string(value)

      _other ->
        nil
    end
  end
end
