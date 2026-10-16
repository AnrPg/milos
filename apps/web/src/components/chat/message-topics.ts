import type { MessageTopic } from "@/api/messaging";

/** Ui keys for what a message from the box is about (ADR-140 §6). */
export const TOPIC_KEYS: Record<MessageTopic, string> = {
  booking: "msgTopicBooking",
  payment: "msgTopicPayment",
  membership: "msgTopicMembership",
  facility: "msgTopicFacility",
};
