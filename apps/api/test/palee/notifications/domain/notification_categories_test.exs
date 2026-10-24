defmodule Palee.Notifications.Domain.NotificationCategoriesTest do
  use ExUnit.Case, async: true

  alias Palee.Notifications.Domain.NotificationCategories, as: Categories
  alias Palee.Notifications.Notification

  @all_types Enum.map(Notification.types(), &Atom.to_string/1)

  describe "the type → category map (ADR-199)" do
    test "gives every notification type a category" do
      assert @all_types -- Categories.mapped_types() == []
    end

    test "names no type that does not exist and none twice" do
      assert Categories.mapped_types() -- @all_types == []
      assert Categories.duplicated_types() == []
    end

    test "answers by atom or string" do
      assert Categories.category_for(:water_reminder) == "journal"
      assert Categories.category_for("person_message") == "messages"
      assert Categories.category_for("no_such_type") == nil
    end
  end

  describe "resolve/1" do
    test "with nothing stored every channel is on, in display order" do
      resolved = Categories.resolve([])

      assert Enum.map(resolved, & &1.category) == Categories.category_ids()

      assert Enum.all?(resolved, fn %{channels: channels} ->
               channels == %{"in_app" => true, "push" => true}
             end)

      assert %{locked: true} = Enum.find(resolved, &(&1.category == "account"))
      assert %{audience: "staff"} = Enum.find(resolved, &(&1.category == "staff"))
    end

    test "applies stored choices; push needs the bell" do
      choices = [
        %{category: "community", channel: "push", enabled: false},
        %{category: "journal", channel: "in_app", enabled: false}
      ]

      resolved = Map.new(Categories.resolve(choices), &{&1.category, &1.channels})

      assert resolved["community"] == %{"in_app" => true, "push" => false}
      assert resolved["journal"] == %{"in_app" => false, "push" => false}
      assert resolved["messages"] == %{"in_app" => true, "push" => true}
    end

    test "a locked category stays on whatever is stored" do
      choices = [%{category: "account", channel: "push", enabled: false}]
      assert Categories.delivers?(choices, :invoice_issued, "push")
    end
  end

  describe "delivers?/3" do
    test "follows the type's category and channel" do
      choices = [%{category: "community", channel: "push", enabled: false}]

      refute Categories.delivers?(choices, :new_follower, "push")
      assert Categories.delivers?(choices, :new_follower, "in_app")
      assert Categories.delivers?(choices, :person_message, "push")
    end

    test "a channel the category does not offer is untouched" do
      assert Categories.delivers?([], :booking_approved, "email")
    end
  end

  describe "parse_change/2" do
    test "keeps the category's channels with boolean values" do
      assert {:ok, [{"push", false}]} =
               Categories.parse_change("coach", %{"push" => false, "x" => 1})

      assert {:ok, pairs} = Categories.parse_change("coach", %{in_app: true, push: false})
      assert Enum.sort(pairs) == [{"in_app", true}, {"push", false}]
    end

    test "refuses an unknown, locked or empty change" do
      assert {:error, :unknown_category} = Categories.parse_change("nope", %{"push" => true})
      assert {:error, :locked_category} = Categories.parse_change("account", %{"push" => false})
      assert {:error, :invalid_change} = Categories.parse_change("coach", %{})
      assert {:error, :invalid_change} = Categories.parse_change("coach", %{"push" => "no"})
      assert {:error, :invalid_change} = Categories.parse_change("coach", %{"email" => false})
    end
  end
end
