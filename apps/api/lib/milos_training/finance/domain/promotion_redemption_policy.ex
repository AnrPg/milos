defmodule MilosTraining.Finance.Domain.PromotionRedemptionPolicy do
  @valid_discount_types ["percent", "fixed_amount", "free_period", "manual"]

  def validate_manual_discount(discount_type, discount_value)
      when discount_type in [nil, ""] and discount_value in [nil, ""] do
    {:error, :promotion_discount_required}
  end

  def validate_manual_discount(discount_type, discount_value) do
    type = normalize_discount_type(discount_type)
    value = parse_integer(discount_value)

    cond do
      is_nil(type) ->
        {:error, :promotion_discount_required}

      type not in @valid_discount_types ->
        {:error, :invalid_promotion_discount}

      value <= 0 ->
        {:error, :promotion_discount_required}

      true ->
        {:ok, {type, value}}
    end
  end

  defp normalize_discount_type("fixed"), do: "fixed_amount"
  defp normalize_discount_type(type) when is_binary(type), do: type
  defp normalize_discount_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_discount_type(_type), do: nil

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> 0
    end
  end

  defp parse_integer(_value), do: 0
end
