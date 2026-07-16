defmodule MilosTraining.Identity.Domain.Locale do
  @moduledoc """
  Pure locale policy for persisted user preferences and transport metadata.

  Locale identifiers follow BCP 47 casing at the public boundary. Regional
  variants fall back to a supported base language only when that base language
  is part of the product catalog; Portuguese remains explicitly `pt-PT`.
  """

  @supported [
    "en",
    "el",
    "ar",
    "ru",
    "de",
    "es",
    "pt-PT",
    "he",
    "it",
    "bg",
    "nl",
    "fr"
  ]

  @canonical_by_downcase Map.new(@supported, &{String.downcase(&1), &1})
  @rtl_locales MapSet.new(["ar", "he"])

  @spec supported() :: [String.t()]
  def supported, do: @supported

  @spec default() :: String.t()
  def default, do: "en"

  @spec normalize(term()) :: {:ok, String.t()} | {:error, :unsupported_locale}
  def normalize(locale) when is_binary(locale) do
    normalized = locale |> String.trim() |> String.replace("_", "-") |> String.downcase()

    case Map.fetch(@canonical_by_downcase, normalized) do
      {:ok, canonical} ->
        {:ok, canonical}

      :error ->
        normalize_base(normalized)
    end
  end

  def normalize(_locale), do: {:error, :unsupported_locale}

  @spec direction(term()) :: :ltr | :rtl
  def direction(locale) do
    case normalize(locale) do
      {:ok, canonical} -> if MapSet.member?(@rtl_locales, canonical), do: :rtl, else: :ltr
      {:error, :unsupported_locale} -> :ltr
    end
  end

  defp normalize_base(normalized) do
    base = normalized |> String.split("-", parts: 2) |> List.first()

    case Map.fetch(@canonical_by_downcase, base) do
      {:ok, "pt-PT"} -> {:error, :unsupported_locale}
      {:ok, canonical} -> {:ok, canonical}
      :error -> {:error, :unsupported_locale}
    end
  end
end
