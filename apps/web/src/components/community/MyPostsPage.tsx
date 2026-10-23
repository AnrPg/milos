"use client";

import { useTranslations } from "next-intl";

import { FeedList } from "@/components/community/FeedList";
import { HubPage } from "@/components/member-app/HubParts";
import { BackToMe } from "@/components/member-app/me/BackToMe";

/** Εγώ › Αναρτήσεις: what I posted, in every club. */
export function MyPostsPage() {
  const t = useTranslations("Community");
  return (
    <HubPage back={<BackToMe />} title={t("myPostsTitle")}>
      <FeedList filter={{ mine: true }} empty={t("myPostsEmpty")} />
    </HubPage>
  );
}
