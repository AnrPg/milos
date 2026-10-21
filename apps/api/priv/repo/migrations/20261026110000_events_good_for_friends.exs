defmodule Palee.Repo.Migrations.EventsGoodForFriends do
  use Ecto.Migration

  # ADR-156 (board 11 Q3 extra): staff tag an event «Καλό για φίλους» so it
  # comes first when members pick an event to bring a friend to. Only an
  # event friends can come to (open to everyone, or with guest passes) takes
  # the tag; a member group's event never does.

  def change do
    alter table(:community_events) do
      add :good_for_friends, :boolean, null: false, default: false
    end

    create constraint(:community_events, :community_events_good_for_friends_check,
             check: "NOT good_for_friends OR open_to_non_members OR guest_pass_allowed"
           )
  end
end
