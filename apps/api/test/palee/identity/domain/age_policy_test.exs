defmodule Palee.Identity.Domain.AgePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Identity.Domain.AgePolicy

  test "the minimum age is 16" do
    assert AgePolicy.minimum_age() == 16
  end

  test "an explicit confirmation passes, with atom or string keys" do
    assert AgePolicy.confirm(%{age_confirmed: true}) == :ok
    assert AgePolicy.confirm(%{"age_confirmed" => true}) == :ok
    assert AgePolicy.confirm(%{"age_confirmed" => "true"}) == :ok
  end

  test "anything else is the field error shown under the confirmation" do
    error = {:error, {:invalid_fields, %{"age_confirmed" => "minimum_age"}}}

    for params <- [
          %{},
          %{age_confirmed: false},
          %{"age_confirmed" => "yes"},
          %{age_confirmed: nil}
        ] do
      assert AgePolicy.confirm(params) == error
    end

    assert AgePolicy.confirm(nil) == error
  end
end
