import { AuthGuard } from "@/components/auth-guard";
import { BodyScreen } from "@/components/body/BodyScreen";
import { MeasureForm } from "@/components/body/MeasureForm";

export const dynamic = "force-dynamic";

// The measure reminder notification links here (ADR-158 §8).
export default function NewMeasurePage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <BodyScreen titleKey="newMeasure">
        <MeasureForm />
      </BodyScreen>
    </AuthGuard>
  );
}
