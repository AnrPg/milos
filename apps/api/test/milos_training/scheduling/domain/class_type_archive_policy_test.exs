defmodule MilosTraining.Scheduling.Domain.ClassTypeArchivePolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Scheduling.Domain.ClassTypeArchivePolicy

  test "allows archival without a replacement when no future classes use the type" do
    assert :ok = ClassTypeArchivePolicy.validate(0, "source", nil, ["source", "other"])
  end

  test "keeps at least one active type available for new classes" do
    assert {:error, :last_active_class_type} =
             ClassTypeArchivePolicy.validate(0, "source", nil, ["source"])
  end

  test "requires a replacement when future classes use the type" do
    assert {:error, :class_type_replacement_required} =
             ClassTypeArchivePolicy.validate(2, "source", nil, ["source", "other"])
  end

  test "rejects the source type as its own replacement" do
    assert {:error, :invalid_class_type_replacement} =
             ClassTypeArchivePolicy.validate(1, "source", "source", ["source", "other"])
  end

  test "requires the replacement to be active" do
    assert {:error, :invalid_class_type_replacement} =
             ClassTypeArchivePolicy.validate(1, "source", "archived", ["source", "active"])
  end

  test "accepts a distinct active replacement" do
    assert :ok =
             ClassTypeArchivePolicy.validate(1, "source", "replacement", [
               "source",
               "replacement"
             ])
  end
end
