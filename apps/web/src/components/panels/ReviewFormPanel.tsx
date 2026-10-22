"use client";


import {useUiTranslations} from "@/i18n/ui";
import { ReviewForm } from "@/components/my-reviews";
import { Dialog } from "@/components/ui/Dialog";

export function ReviewFormPanel({ onClose }: { onClose: () => void }) {
  const i18n = useUiTranslations();
  return (
    <Dialog
      onClose={onClose}
      variant="drawer"
      layer="drawer"
      size="full"
      panelClassName="md:max-w-[440px]"
      eyebrow={i18n("leaveAReview5e65b65")}
      description={i18n("shareYourFeedbackWithYourCoacha24d2a8")}
      ariaLabel={i18n("leaveAReview5e65b65")}
    >
        <ReviewForm />
    </Dialog>
  );
}
