defmodule MilosTraining.Workouts.Domain.WorkoutIcon do
  @moduledoc """
  A workout's library icon: exactly one emoji (one grapheme, possibly built from
  several code points such as "🏋️‍♀️"). Anything else is rejected, which also
  keeps free-form model output out of the database.
  """

  @max_bytes 32

  @spec normalize(term()) :: {:ok, String.t()} | :error
  def normalize(value) when is_binary(value) do
    icon = String.trim(value)

    if byte_size(icon) in 1..@max_bytes and String.length(icon) == 1 and emoji?(icon),
      do: {:ok, icon},
      else: :error
  end

  def normalize(_value), do: :error

  # Pictographic code points (symbols, dingbats, emoji planes); letters, digits
  # and punctuation never qualify on their own.
  defp emoji?(icon) do
    icon
    |> String.to_charlist()
    |> Enum.any?(fn codepoint ->
      codepoint in 0x2190..0x2BFF or codepoint in 0x1F000..0x1FAFF or
        codepoint in [0x00A9, 0x00AE]
    end)
  end
end
