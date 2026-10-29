defmodule Palee.PersonalData.Domain.Archive do
  @moduledoc """
  ADR-267: the file of "Download my data": an in-memory ZIP of
  pretty-printed JSON, one file per section of `Catalog.sections/0`
  (`<section>.json`, `%{table => rows}`), plus `manifest.json` with the
  format, the profile, when it was made and how many records each file
  holds. Pure apart from OTP's in-memory `:zip`; callers pass the time.
  """

  alias Palee.PersonalData.Domain.Catalog

  @format "palee-personal-data/v1"

  def format, do: @format

  @doc "The archive's file name as the person downloads it."
  def file_name(%DateTime{} = generated_at),
    do: "palee-my-data-#{Date.to_iso8601(DateTime.to_date(generated_at))}.zip"

  @doc """
  `{:ok, %{zip: binary, record_count: n}}` for `sections` (`%{section =>
  %{table => [row]}}`). Every section of the catalog gets its file, empty
  when the person has nothing there, so the archive's shape never depends on
  what exists.
  """
  def build(%{profile_id: profile_id, generated_at: %DateTime{} = generated_at, sections: sections}) do
    files =
      Enum.map(Catalog.sections(), fn section ->
        tables = Map.get(sections, section, %{})
        {"#{section}.json", section, tables}
      end)

    manifest = %{
      "format" => @format,
      "profile_id" => profile_id,
      "generated_at" => DateTime.to_iso8601(generated_at),
      "about" =>
        "A copy of the personal data Palee keeps about this profile (GDPR articles 15 and 20). " <>
          "Each file holds the rows of one area, by table. Passwords, keys and other people's data are left out.",
      "files" =>
        Enum.map(files, fn {name, section, tables} ->
          %{"file" => name, "section" => section, "record_count" => count(tables)}
        end)
    }

    documents = [{"manifest.json", manifest} | Enum.map(files, fn {name, _s, tables} -> {name, tables} end)]

    with {:ok, zip} <- zip(documents) do
      {:ok, %{zip: zip, record_count: Enum.sum(Enum.map(files, fn {_n, _s, t} -> count(t) end))}}
    end
  end

  defp count(tables), do: tables |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

  defp zip(documents) do
    files =
      Enum.map(documents, fn {name, document} ->
        {String.to_charlist(name),
         document |> Jason.encode_to_iodata!(pretty: true) |> IO.iodata_to_binary()}
      end)

    case :zip.create(~c"palee-my-data.zip", files, [:memory]) do
      {:ok, {_name, binary}} -> {:ok, binary}
      {:error, reason} -> {:error, {:archive_failed, reason}}
    end
  end
end
