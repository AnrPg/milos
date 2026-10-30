defmodule Palee.Payments.Domain.AccountOptions do
  @moduledoc """
  What a business lets its members pay online, and who hears about a failed
  charge (ADR-260). Stored on the provider account; every key has a default,
  so an account saved before these options existed behaves as «everything
  online, everyone told».

    * `purposes` – which payments members may make online:
      `packages` (buy or renew a membership package), `autopay` (renewals
      and bills charged to the card the member chose), `drop_in` (a single
      visit or trial paid when booking), `shop` (e-shop orders),
      `personal_training` (personal-training packages);
    * `notify_member` – a member hears about every declined charge, with a
      link to pay with another card;
    * `notify_staff` – staff with billing rights hear when the last retry
      failed (the Εκκρεμότητες tab lists such charges either way).

  The retry schedule (1, 3, 7 days) lives in `IntentPolicy` and the grace
  days in the finance settings (`subscription_grace_days`): one place each.
  """

  @purposes ~w(packages autopay drop_in shop personal_training)
  @flags ~w(notify_member notify_staff)

  def purposes, do: @purposes

  @doc "The options with every missing key at its default."
  def resolve(options) when is_map(options) do
    given = stringify(options)
    stored_purposes = if is_map(given["purposes"]), do: given["purposes"], else: %{}

    %{
      "purposes" =>
        Map.new(@purposes, fn key -> {key, boolean(stored_purposes[key], true)} end),
      "notify_member" => boolean(given["notify_member"], true),
      "notify_staff" => boolean(given["notify_staff"], true)
    }
  end

  def resolve(_options), do: resolve(%{})

  @doc """
  Applies a change to the stored options. Unknown keys and non-boolean
  values are refused field by field; keys left out keep their value.
  """
  def change(current, params) when is_map(params) do
    params = stringify(params)
    base = resolve(current)

    {purposes, purpose_errors} =
      case params["purposes"] do
        nil -> {base["purposes"], %{}}
        %{} = given -> merge_booleans(base["purposes"], given, @purposes, "purposes.")
        _other -> {base["purposes"], %{"purposes" => "invalid"}}
      end

    {flags, flag_errors} =
      merge_booleans(Map.take(base, @flags), Map.take(params, @flags), @flags, "")

    unknown =
      params
      |> Map.keys()
      |> Kernel.--(["purposes" | @flags])
      |> Map.new(&{&1, "unknown"})

    errors = purpose_errors |> Map.merge(flag_errors) |> Map.merge(unknown)

    if errors == %{},
      do: {:ok, Map.put(flags, "purposes", purposes)},
      else: {:error, {:invalid_fields, errors}}
  end

  def change(_current, _params), do: {:error, {:invalid_fields, %{"options" => "invalid"}}}

  @doc "Whether members may pay `purpose` online under these options."
  def allows?(options, purpose) when purpose in @purposes,
    do: resolve(options)["purposes"][purpose] == true

  def allows?(_options, _purpose), do: false

  def notify_member?(options), do: resolve(options)["notify_member"]
  def notify_staff?(options), do: resolve(options)["notify_staff"]

  defp merge_booleans(base, given, allowed, prefix) do
    Enum.reduce(given, {base, %{}}, fn {key, value}, {acc, errors} ->
      cond do
        key not in allowed -> {acc, Map.put(errors, prefix <> key, "unknown")}
        is_boolean(value) -> {Map.put(acc, key, value), errors}
        true -> {acc, Map.put(errors, prefix <> key, "invalid")}
      end
    end)
  end

  defp boolean(value, _default) when is_boolean(value), do: value
  defp boolean(_value, default), do: default

  defp stringify(map) do
    Map.new(map, fn
      {key, %{} = value} when not is_struct(value) -> {to_string(key), stringify(value)}
      {key, value} -> {to_string(key), value}
    end)
  end
end
