import type { MessageTopic } from "@/api/messaging";

/** Ui keys for what a message to or from the box is about (ADR-140 §6, ADR-282). */
export const TOPIC_KEYS: Record<MessageTopic, string> = {
  booking: "msgTopicBooking",
  payment: "msgTopicPayment",
  membership: "msgTopicMembership",
  training: "msgTopicTraining",
  facility: "msgTopicFacility",
};
