defmodule Palee.Documents.Domain.StarterTemplates do
  @moduledoc """
  Ready-made Greek and English drafts a box can start from (ADR-252, CP-B1
  «έτοιμα ελληνικά πρότυπα»): participation waiver, terms, privacy notice
  and health declaration. They are **drafts for legal review**: each text
  opens with that warning and is listed with `legal_review_required: true`,
  so no box publishes one as final without a lawyer's check.

  The texts live in `priv/documents/starters/<language>/<kind>.md` and are
  read at compile time.
  """

  @root Path.expand("../../../../priv/documents/starters", __DIR__)
  @kinds ~w(waiver terms privacy health_certificate)
  @languages ~w(el en)
  @requirements %{
    "waiver" => "mandatory",
    "terms" => "mandatory",
    "privacy" => "mandatory",
    "health_certificate" => "optional"
  }

  @starters (for language <- @languages, kind <- @kinds do
               path = Path.join([@root, language, kind <> ".md"])
               @external_resource path
               body = path |> File.read!() |> String.trim()
               "# " <> title_line = body |> String.split("\n", parts: 2) |> hd()

               %{
                 kind: kind,
                 language: language,
                 title: String.trim(title_line),
                 body: body,
                 requirement: Map.fetch!(@requirements, kind),
                 draft: true,
                 legal_review_required: true
               }
             end)

  @doc "Every starter, optionally only those in `language`."
  def list(language \\ nil)
  def list(nil), do: @starters
  def list(language), do: Enum.filter(@starters, &(&1.language == language))

  @doc "One starter by kind and language, or nil."
  def get(kind, language),
    do: Enum.find(@starters, &(&1.kind == kind and &1.language == language))
end
