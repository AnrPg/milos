defmodule Palee.Facility.Domain.MapLinkTest do
  use ExUnit.Case, async: true

  alias Palee.Facility.Domain.MapLink

  test "recognises Google Maps links only" do
    assert MapLink.link?("https://maps.app.goo.gl/AbC")
    assert MapLink.link?("https://www.google.gr/maps/@38,23,15z")
    assert MapLink.link?(" https://google.com/maps?q=38,23 ")
    refute MapLink.link?("https://google.evil.com/maps")
    refute MapLink.link?("https://example.com/@38,23")
    refute MapLink.link?("Φωκίωνος Νέγρη 12")
  end

  test "the exact place wins over the camera" do
    assert {:ok, {38.000563, 23.7345526}} =
             MapLink.coordinates(
               "https://www.google.com/maps/place/X/@37.9,23.6,15z/data=!4m6!3m5!3d38.000563!4d23.7345526"
             )

    assert {:ok, {37.9, 23.6}} = MapLink.coordinates("https://www.google.com/maps/@37.9,23.6,15z")
    assert {:ok, {38.1, -3.5}} = MapLink.coordinates("https://maps.google.com/?q=38.1,-3.5")

    assert {:ok, {38.1, 23.5}} =
             MapLink.coordinates("https://www.google.com/maps/search/?api=1&query=38.1%2C23.5")
  end

  test "rejects links without a usable point" do
    assert {:error, :no_coordinates} =
             MapLink.coordinates("https://www.google.com/maps/place/Kypseli")

    assert {:error, :no_coordinates} =
             MapLink.coordinates("https://www.google.com/maps/@138,23,15z")
  end
end
