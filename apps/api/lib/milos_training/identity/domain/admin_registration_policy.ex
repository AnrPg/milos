defmodule MilosTraining.Identity.Domain.AdminRegistrationPolicy do
  @moduledoc false

  import Bitwise

  def authorize(submitted, expected) when is_binary(submitted) and is_binary(expected) do
    if secure_compare(submitted, expected),
      do: :ok,
      else: {:error, :invalid_admin_registration_code}
  end

  def authorize(_submitted, _expected), do: {:error, :invalid_admin_registration_code}

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {left_byte, right_byte}, difference ->
      difference ||| bxor(left_byte, right_byte)
    end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false
end
