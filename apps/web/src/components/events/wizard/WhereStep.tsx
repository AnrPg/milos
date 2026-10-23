"use client";

import { useTranslations } from "next-intl";

import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";

import type { EventLocation } from "../EventFormParts";
import { FieldGroup, SegmentGrid, fieldClass } from "./fields";
import type { StepProps } from "./types";

const ELSEWHERE = "__elsewhere__";

/** Step 4: one of the box's branches, or another address (a name, an address, or both). */
export function WhereStep({ form, set, locations }: StepProps & { locations: EventLocation[] }) {
  const t = useTranslations("Events");
  const place = form.place;
  const value = place.kind === "location" ? place.locationId : ELSEWHERE;

  return (
    <div className="flex flex-col gap-4">
      <FieldGroup legend={t("fieldPlace")}>
        <SegmentGrid
          label={t("fieldPlace")}
          value={value}
          onChange={(choice) =>
            set({
              place:
                choice === ELSEWHERE
                  ? place.kind === "address"
                    ? place
                    : { kind: "address", name: "", address: "" }
                  : { kind: "location", locationId: choice },
            })
          }
          options={[
            ...locations.map((location) => ({ value: location.id, label: location.name })),
            { value: ELSEWHERE, label: t("placeElsewhere") },
          ]}
        />
      </FieldGroup>
      {place.kind === "address" ? (
        <div className="flex flex-col gap-3">
          <Field label={t("fieldPlaceName")}>
            <input
              value={place.name}
              maxLength={120}
              onChange={(event) => set({ place: { kind: "address", name: event.target.value, address: place.address } })}
              placeholder={t("fieldPlaceNamePlaceholder")}
              className={fieldClass}
              style={inputStyle}
            />
          </Field>
          <Field label={t("fieldAddress")}>
            <input
              value={place.address}
              maxLength={200}
              onChange={(event) => set({ place: { kind: "address", name: place.name, address: event.target.value } })}
              placeholder={t("fieldAddressPlaceholder")}
              className={fieldClass}
              style={inputStyle}
            />
          </Field>
        </div>
      ) : null}
    </div>
  );
}
