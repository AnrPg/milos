import { AuthGuard } from "@/components/auth-guard";
import { PlatformTagSuggestions } from "@/components/platform/PlatformTagSuggestions";

export const dynamic = "force-dynamic";

export default function PlatformTagSuggestionsRoute() {
  return (
    <AuthGuard>
      <PlatformTagSuggestions />
    </AuthGuard>
  );
}
