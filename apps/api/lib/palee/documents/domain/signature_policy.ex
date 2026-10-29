defmodule Palee.Documents.Domain.SignaturePolicy do
  @moduledoc """
  Simple electronic signatures with a strong audit trail (ADR-252, eIDAS
  art. 3(10) and 25(1)).

  The signer confirms they read the text (`agreed: true`), names the exact
  version they saw, and signs with a typed name, a drawn signature, or both.
  The evidence names the version's content hash, the time, the IP address,
  the user agent and the account; its own SHA-256 is stored with the row
  and printed on the PDF certificate.

  A drawn signature is vector strokes in a `width` × `height` box with
  integer coordinates (no image upload, no floats in the hash).
  """

  alias Palee.Documents.Domain.TemplatePolicy
  alias Palee.Fiscal.Domain.CanonicalJson

  @min_name 2
  @max_name 120
  @max_side 2_000
  @max_strokes 100
  @max_points 5_000
  @max_user_agent 512

  @doc """
  Validates what the member sent against the template's current version:
  `{:ok, %{typed_name, drawn_signature}}`, `{:error,
  :document_version_outdated}` (the text changed while they read it) or
  `{:error, {:invalid_fields, errors}}`.
  """
  def validate(params, %{id: current_version_id}) do
    typed_name = typed_name(params[:typed_name])
    drawn = drawn(params[:drawn_signature])

    errors =
      %{}
      |> agreed(params[:agreed])
      |> name_errors(params[:typed_name], typed_name)
      |> drawn_errors(drawn)
      |> something_signed(typed_name, drawn)

    cond do
      errors != %{} -> {:error, {:invalid_fields, errors}}
      params[:version_id] != current_version_id -> {:error, :document_version_outdated}
      true -> {:ok, %{typed_name: typed_name, drawn_signature: ok_drawn(drawn)}}
    end
  end

  def validate(_params, nil), do: {:error, :document_not_published}

  @doc """
  The evidence record and its hash. `signer` is the account at signing
  time (`user_id`, `display_name`, `nickname`, `email`); `meta` holds
  `ip_address` and `user_agent`.
  """
  def evidence(%{} = attrs) do
    evidence = %{
      format: "palee-signature-evidence",
      version: 1,
      signature_id: attrs.signature_id,
      organization_id: attrs.organization_id,
      template_id: attrs.template_id,
      version_id: attrs.version_id,
      version_number: attrs.version_number,
      content_hash: attrs.content_hash,
      request_id: attrs[:request_id],
      signed_at: microseconds(attrs.signed_at),
      level: attrs.level,
      provider: attrs.provider,
      signer: Map.take(attrs.signer, [:user_id, :display_name, :nickname, :email]),
      typed_name: attrs.typed_name,
      drawn_signature: attrs.drawn_signature,
      ip_address: attrs[:ip_address],
      user_agent: user_agent(attrs[:user_agent])
    }

    {evidence, evidence |> CanonicalJson.encode!() |> TemplatePolicy.sha256()}
  end

  @doc "Formats an IP tuple (or keeps a string)."
  def ip_address(nil), do: nil
  def ip_address(ip) when is_binary(ip), do: String.slice(ip, 0, 64)

  def ip_address(ip) when is_tuple(ip) do
    case :inet.ntoa(ip) do
      {:error, _} -> nil
      chars -> List.to_string(chars)
    end
  end

  def user_agent(nil), do: nil
  def user_agent(agent) when is_binary(agent), do: String.slice(agent, 0, @max_user_agent)

  @doc """
  Where a person stands with one document: `:signed` (their latest
  signature is of the required version or later), `:resign_required` (a
  major version came after it) or `:unsigned`.
  """
  def status(%{required_version_number: required}, nil) when is_integer(required),
    do: :unsigned

  def status(%{required_version_number: required}, %{version_number: signed})
      when signed >= required,
      do: :signed

  def status(_template, _signature), do: :resign_required

  defp microseconds(%DateTime{} = at) do
    {microsecond, _precision} = at.microsecond
    %{at | microsecond: {microsecond, 6}}
  end

  defp agreed(errors, true), do: errors
  defp agreed(errors, "true"), do: errors
  defp agreed(errors, _other), do: Map.put(errors, :agreed, "required")

  defp typed_name(value) when is_binary(value) do
    case value |> String.trim() |> String.replace(~r/\s+/u, " ") do
      "" -> nil
      name -> name
    end
  end

  defp typed_name(_value), do: nil

  defp name_errors(errors, _raw, nil), do: errors

  defp name_errors(errors, _raw, name) do
    length = String.length(name)

    cond do
      length < @min_name -> Map.put(errors, :typed_name, "too_short")
      length > @max_name -> Map.put(errors, :typed_name, "too_long")
      true -> errors
    end
  end

  defp something_signed(errors, nil, nil),
    do: Map.put_new(errors, :typed_name, "signature_required")

  defp something_signed(errors, _name, _drawn), do: errors

  defp drawn(nil), do: nil

  defp drawn(%{} = value) do
    width = get(value, :width)
    height = get(value, :height)
    strokes = get(value, :strokes)

    with true <- side?(width) and side?(height),
         true <- is_list(strokes) and strokes != [] and length(strokes) <= @max_strokes,
         {:ok, strokes} <- strokes(strokes, width, height),
         true <- Enum.sum(Enum.map(strokes, &length/1)) <= @max_points do
      {:ok, %{width: width, height: height, strokes: strokes}}
    else
      _ -> :invalid
    end
  end

  defp drawn(_value), do: :invalid

  defp drawn_errors(errors, :invalid), do: Map.put(errors, :drawn_signature, "invalid")
  defp drawn_errors(errors, _drawn), do: errors

  defp ok_drawn({:ok, drawn}), do: drawn
  defp ok_drawn(nil), do: nil

  defp side?(value), do: is_integer(value) and value >= 10 and value <= @max_side

  defp strokes(strokes, width, height) do
    Enum.reduce_while(strokes, {:ok, []}, fn stroke, {:ok, acc} ->
      case points(stroke, width, height) do
        {:ok, points} -> {:cont, {:ok, [points | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, strokes} -> {:ok, Enum.reverse(strokes)}
      :error -> :error
    end
  end

  defp points(stroke, width, height) when is_list(stroke) and stroke != [] do
    Enum.reduce_while(stroke, {:ok, []}, fn
      [x, y], {:ok, acc} when is_number(x) and is_number(y) ->
        {x, y} = {round(x), round(y)}

        if x >= 0 and x <= width and y >= 0 and y <= height,
          do: {:cont, {:ok, [[x, y] | acc]}},
          else: {:halt, :error}

      _point, _acc ->
        {:halt, :error}
    end)
    |> case do
      {:ok, points} -> {:ok, Enum.reverse(points)}
      :error -> :error
    end
  end

  defp points(_stroke, _width, _height), do: :error

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
