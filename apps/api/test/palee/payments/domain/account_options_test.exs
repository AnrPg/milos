defmodule Palee.Payments.Domain.AccountOptionsTest do
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.AccountOptions

  test "missing keys resolve to their defaults" do
    resolved = AccountOptions.resolve(%{"purposes" => %{"shop" => false}})
    assert resolved["purposes"]["shop"] == false
    assert resolved["purposes"]["packages"] == true
    assert resolved["notify_member"] and resolved["notify_staff"]
    assert AccountOptions.resolve(nil) == AccountOptions.resolve(%{})
  end

  test "a change keeps what it leaves out" do
    {:ok, first} = AccountOptions.change(%{}, %{purposes: %{autopay: false}})
    {:ok, second} = AccountOptions.change(first, %{"notify_staff" => false})
    refute second["purposes"]["autopay"]
    refute second["notify_staff"]
    assert second["notify_member"]
  end

  test "unknown keys and non-booleans are refused field by field" do
    assert {:error, {:invalid_fields, errors}} =
             AccountOptions.change(%{}, %{
               "purposes" => %{"shop" => "yes", "bingo" => true},
               "notify_member" => 1,
               "colour" => true
             })

    assert errors == %{
             "purposes.shop" => "invalid",
             "purposes.bingo" => "unknown",
             "notify_member" => "invalid",
             "colour" => "unknown"
           }

    assert {:error, {:invalid_fields, %{"purposes" => "invalid"}}} =
             AccountOptions.change(%{}, %{"purposes" => true})
  end

  test "allows? answers per purpose and refuses unknown purposes" do
    assert AccountOptions.allows?(%{}, "packages")
    refute AccountOptions.allows?(%{"purposes" => %{"packages" => false}}, "packages")
    refute AccountOptions.allows?(%{}, "booking")
  end
end
