defmodule Palee.Documents.Domain.TemplatePolicy do
  @moduledoc """
  Documents and their versions (ADR-252).

  A document has a kind, a title and a requirement set by staff:
  `mandatory` documents block booking (when the box's gate is on) and count
  as outstanding items; `optional` ones are only offered. Its text lives in
  immutable, numbered versions. A version is `major` (everyone signs again)
  or `minor` (earlier signatures still count); the first version is always
  major.

  The content hash of a version is the SHA-256 of the canonical JSON of
  `template_id`, `number`, `title`, `language` and `body` (line endings
  normalised to `\\n`), so a signature names exactly the text it accepted.
  """

  alias Palee.Fiscal.Domain.CanonicalJson

  @kinds ~w(waiver terms privacy health_certificate other)
  @requirements ~w(mandatory optional)
  @change_kinds ~w(major minor)
  @languages ~w(el en de fr es it ru pt-PT nl bg ar he)
  @max_title 200
  @max_body 100_000

  def kinds, do: @kinds
  def requirements, do: @requirements
  def change_kinds, do: @change_kinds
  def languages, do: @languages

  @doc """
  `{:ok, %{kind, title, requirement}}` or `{:error, {:invalid_fields, errors}}`.
  The requirement defaults to `optional`.
  """
  def validate_template(attrs) do
    kind = text(attrs[:kind])
    title = text(attrs[:title])
    requirement = text(attrs[:requirement]) || "optional"

    %{}
    |> check(:kind, kind in @kinds, "invalid")
    |> check_title(title)
    |> check(:requirement, requirement in @requirements, "invalid")
    |> result(%{kind: kind, title: title, requirement: requirement})
  end

  @doc "`{:ok, requirement}` or `{:error, {:invalid_fields, %{requirement: \"invalid\"}}}`."
  def validate_requirement(value) do
    value = text(value)

    if value in @requirements,
      do: {:ok, value},
      else: {:error, {:invalid_fields, %{requirement: "invalid"}}}
  end

  @doc """
  Validates the text of version `number`: `{:ok, %{title, body, language,
  change_kind}}`. Version 1 is always `major`; later ones default to `major`
  (asking everyone to sign again is the safe default).
  """
  def validate_version(attrs, number) when is_integer(number) and number >= 1 do
    title = text(attrs[:title])
    body = body(attrs[:body])
    language = text(attrs[:language]) || "el"
    change_kind = if number == 1, do: "major", else: text(attrs[:change_kind]) || "major"

    %{}
    |> check_title(title)
    |> check(:body, is_binary(body) and body != "", "required")
    |> check(:body, not is_binary(body) or String.length(body) <= @max_body, "too_long")
    |> check(:language, language in @languages, "invalid")
    |> check(:change_kind, change_kind in @change_kinds, "invalid")
    |> result(%{title: title, body: body, language: language, change_kind: change_kind})
  end

  @doc "The version numbers after publishing `change_kind` on a template."
  def next_numbers(%{current_version_number: current, required_version_number: required}, kind) do
    number = current + 1

    %{
      current_version_number: number,
      required_version_number: if(kind == "major", do: number, else: required)
    }
  end

  @doc "SHA-256 (hex) of a version's canonical content."
  def content_hash(%{template_id: template_id, number: number} = version) do
    %{
      template_id: template_id,
      number: number,
      title: version.title,
      language: version.language,
      body: version.body
    }
    |> CanonicalJson.encode!()
    |> sha256()
  end

  def sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp check_title(errors, nil), do: Map.put(errors, :title, "required")

  defp check_title(errors, title),
    do: check(errors, :title, String.length(title) <= @max_title, "too_long")

  defp check(errors, _field, true, _reason), do: errors
  defp check(errors, field, false, reason), do: Map.put_new(errors, field, reason)

  defp result(errors, attrs) when errors == %{}, do: {:ok, attrs}
  defp result(errors, _attrs), do: {:error, {:invalid_fields, errors}}

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(value) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp text(_value), do: nil

  defp body(value) when is_binary(value) do
    value
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.trim()
  end

  defp body(_value), do: nil
end
