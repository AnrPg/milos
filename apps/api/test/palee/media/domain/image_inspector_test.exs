defmodule Palee.Media.Domain.ImageInspectorTest do
  use ExUnit.Case, async: true

  import Palee.TestSupport.ImageFixtures

  alias Palee.Media.Domain.ImageInspector

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

  describe "sniff/1 (ADR-157)" do
    test "names the real type of what a phone uploads" do
      assert {:ok, "image/jpeg"} = ImageInspector.sniff(jpeg(10, 10, [exif_segment()]))
      assert {:ok, "image/png"} = ImageInspector.sniff(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0>>)
      assert {:ok, "image/webp"} = ImageInspector.sniff(webp_extended())
      assert {:ok, "image/heic"} = ImageInspector.sniff(<<0, 0, 0, 24, "ftypheic", 0, 0>>)
      assert {:ok, "image/heif"} = ImageInspector.sniff(<<0, 0, 0, 24, "ftypmif1", 0, 0>>)
      assert {:ok, "video/quicktime"} = ImageInspector.sniff(<<0, 0, 0, 20, "ftypqt  ", 0>>)
      assert {:ok, "video/mp4"} = ImageInspector.sniff(<<0, 0, 0, 32, "ftypisom", 0>>)
      assert {:ok, "video/mp4"} = ImageInspector.sniff(<<0, 0, 0, 32, "ftypM4V ", 0>>)
      assert {:ok, "video/webm"} = ImageInspector.sniff(<<0x1A, 0x45, 0xDF, 0xA3, 0>>)
    end

    test "refuses anything else" do
      assert {:error, :invalid_media_type} = ImageInspector.sniff("<svg xmlns=...>")
      assert {:error, :invalid_media_type} = ImageInspector.sniff(<<0, 0, 0, 24, "ftypavif">>)
      assert {:error, :invalid_media_type} = ImageInspector.sniff("GIF89a")
    end
  end
end
