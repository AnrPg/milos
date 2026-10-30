"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchClassRoom } from "@/api/schedule";
import { useSession } from "@/components/session-provider";
import { FloorPlanCanvas } from "@/components/spaces/FloorPlanCanvas";
import { validArea } from "@/components/spaces/floor-plan";
import { RoomPhotoStrip } from "@/components/spaces/RoomPhotoStrip";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * The room of a class (ADR-290), opened from «Δες στην κάτοψη» in the class
 * details: the floor plan of its floor with the room coloured, how to get
 * there and the room's photos. What shows is what the API lets this viewer
 * see (the gym's setting, a hidden floor).
 */
export function ClassRoomDialog({ slotId, spaceName, onClose }: { slotId: string; spaceName: string; onClose: () => void }) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const room = useQuery({
    queryKey: ["schedule", "slot-space", slotId],
    enabled: Boolean(token),
    queryFn: () => fetchClassRoom(token, slotId),
    staleTime: 60_000,
  });

  const data = room.data;
  const area = data?.area && validArea(data.area) ? data.area : null;

  return (
    <Dialog eyebrow={t("roomEyebrow")} title={data?.space.name ?? spaceName} size="lg" variant="sheet" onClose={onClose}>
      <div className="flex flex-col gap-4" data-testid="class-room">
        {room.isError ? <ErrorNotice>{localizeError(room.error, ui)}</ErrorNotice> : null}
        {data?.floor_plan && area ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm font-semibold" style={{ color: "var(--muted)" }}>{data.floor_plan.name}</p>
            <FloorPlanCanvas
              testId="class-room-plan"
              imageUrl={data.floor_plan.image_url}
              alt={t("planAlt", { name: data.floor_plan.name })}
              areas={[{ id: data.space.id, label: data.space.name, points: area.points, tone: "selected" }]}
            />
          </div>
        ) : null}
        {data?.space.directions ? (
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide" style={{ color: "var(--dim)" }}>{t("roomDirections")}</p>
            <p className="mt-1 text-sm" style={{ color: "var(--text)" }} data-testid="class-room-directions">{data.space.directions}</p>
          </div>
        ) : null}
        {data?.space.description ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{data.space.description}</p>
        ) : null}
        {data && data.photos.length > 0 ? (
          <div>
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide" style={{ color: "var(--dim)" }}>{t("roomPhotos")}</p>
            <RoomPhotoStrip photos={data.photos} testId="class-room-photos" />
          </div>
        ) : null}
      </div>
    </Dialog>
  );
}
