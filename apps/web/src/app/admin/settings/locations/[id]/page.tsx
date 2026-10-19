import { AuthGuard } from "@/components/auth-guard";
import { LocationEditor } from "@/components/admin/location/LocationEditor";

export const dynamic = "force-dynamic";

export default async function AdminLocationPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  return (
    <AuthGuard roles={["admin"]}>
      <LocationEditor locationId={id} />
    </AuthGuard>
  );
}
