defmodule MilosTraining.Media.Domain.ImageInspectorTest do
  use ExUnit.Case, async: true

  import MilosTraining.TestSupport.ImageFixtures

  alias MilosTraining.Media.Domain.ImageInspector

  test "reads a clean JPEG's dimensions" do
    assert {:ok, %{content_type: "image/jpeg", width: 1600, height: 1200}} =
             ImageInspector.inspect_image(jpeg(1600, 1200))
  end

  test "refuses a JPEG that still carries EXIF" do
    assert {:error, :media_has_metadata} =
             ImageInspector.inspect_image(jpeg(800, 600, [exif_segment()]))
  end

  test "refuses a JPEG whose segments run past the probe" do
    head = jpeg(800, 600)
    assert {:error, :media_unreadable} = ImageInspector.inspect_image(binary_part(head, 0, 12))
  end

  test "reads simple WebP (lossy and lossless) and refuses extended WebP" do
    assert {:ok, %{content_type: "image/webp", width: 1024, height: 768}} =
             ImageInspector.inspect_image(webp_lossy(1024, 768))

    assert {:ok, %{content_type: "image/webp", width: 640, height: 480}} =
             ImageInspector.inspect_image(webp_lossless(640, 480))

    assert {:error, :media_has_metadata} = ImageInspector.inspect_image(webp_extended())
  end

  test "refuses anything else" do
    assert {:error, :invalid_media_type} = ImageInspector.inspect_image(<<0x89, "PNG">>)
    assert {:error, :invalid_media_type} = ImageInspector.inspect_image("<svg/>")
  end
end
