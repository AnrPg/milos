import { Suspense } from "react";

import { ChatsPageContent } from "./ChatsPageContent";

export default function ChatsPage() {
  return (
    <Suspense>
      <ChatsPageContent />
    </Suspense>
  );
}
