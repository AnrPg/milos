defmodule Palee.Identity.Domain.FilterPolicy do
  @moduledoc """
  Rules for remembered filters (ADR-151). A surface is a list screen that
  uses the chip row + «Φίλτρα (n)» pattern (vision §7.2). Params are an
  opaque JSON object here; the surface's own query validates what it uses.
  """

  @surfaces ~w(around_me box_schedule feed club journal vault progress partners)
  @max_named 20
  @max_param_bytes 4_096

  def surfaces, do: @surfaces
  def max_named, do: @max_named

  def validate_surface(surface) when surface in @surfaces, do: :ok
  def validate_surface(_surface), do: {:error, :unknown_filter_surface}

  def validate_params(params) when is_map(params) do
    if byte_size(Jason.encode!(params)) <= @max_param_bytes,
      do: :ok,
      else: {:error, :filter_too_large}
  end

  def validate_params(_params), do: {:error, :invalid_filter}

  def normalize_name(name) when is_binary(name) do
    case name |> String.split() |> Enum.join(" ") do
      "" -> {:error, :invalid_filter_name}
      name when byte_size(name) > 160 -> {:error, :invalid_filter_name}
      name -> if String.length(name) <= 40, do: {:ok, name}, else: {:error, :invalid_filter_name}
    end
  end

  def normalize_name(_name), do: {:error, :invalid_filter_name}
end
