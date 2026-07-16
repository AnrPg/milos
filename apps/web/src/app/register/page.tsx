
import {useUiTranslations} from "@/i18n/ui";
import { AuthConsole } from "@/components/auth-console";

export const dynamic = "force-dynamic";

export default function RegisterPage() {
  const i18n = useUiTranslations();
  return <AuthConsole initialMode="register" />;
}
