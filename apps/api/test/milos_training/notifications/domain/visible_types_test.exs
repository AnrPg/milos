defmodule MilosTraining.Notifications.Domain.VisibleTypesTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Notifications.Domain.VisibleTypes

  test "keeps chat delivery records out of the Updates inbox" do
    refute VisibleTypes.visible_inbox_type?(:chat_message)
    refute VisibleTypes.visible_inbox_type?("chat_message")
    assert "chat_message" in VisibleTypes.hidden_inbox_types()
  end

  test "keeps non-conversational updates visible" do
    assert VisibleTypes.visible_inbox_type?(:booking_approved)
    assert VisibleTypes.visible_inbox_type?("admin_note")
  end
end
