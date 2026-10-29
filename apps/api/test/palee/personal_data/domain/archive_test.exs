defmodule Palee.PersonalData.Domain.ArchiveTest do
  use ExUnit.Case, async: true

  alias Palee.PersonalData.Domain.{Archive, Catalog}

  @at ~U[2027-03-10 12:00:00.000000Z]

  test "one JSON file per section and a manifest with the counts" do
    {:ok, %{zip: zip, record_count: 3}} =
      Archive.build(%{
        profile_id: "p1",
        generated_at: @at,
        sections: %{
          "bookings" => %{"bookings" => [%{"id" => "b1"}, %{"id" => "b2"}]},
          "profile" => %{"users" => [%{"id" => "p1", "nickname" => "Ελένη"}]}
        }
      })

    {:ok, files} = :zip.unzip(zip, [:memory])
    files = Map.new(files, fn {name, body} -> {to_string(name), Jason.decode!(body)} end)

    assert Map.keys(files) |> Enum.sort() ==
             Enum.sort(["manifest.json" | Enum.map(Catalog.sections(), &"#{&1}.json")])

    assert files["profile.json"] == %{"users" => [%{"id" => "p1", "nickname" => "Ελένη"}]}
    assert files["signatures.json"] == %{}

    manifest = files["manifest.json"]
    assert manifest["format"] == "palee-personal-data/v1"
    assert manifest["profile_id"] == "p1"
    assert manifest["generated_at"] == "2027-03-10T12:00:00.000000Z"

    assert %{"file" => "bookings.json", "record_count" => 2} =
             Enum.find(manifest["files"], &(&1["section"] == "bookings"))
  end

  test "the file is named after its day" do
    assert Archive.file_name(@at) == "palee-my-data-2027-03-10.zip"
  end
end
