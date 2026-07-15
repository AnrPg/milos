import { apiRequest } from "@/api/client";

export type CalendarExportLinks = {
  token: string;
  path: string;
  https_url: string;
  webcal_url: string;
  download_url: string;
  help: {
    google: string;
    apple: string;
    outlook: string;
    download: string;
  };
};

export async function fetchCalendarExportLinks(token: string) {
  return apiRequest<CalendarExportLinks>("/calendar/export-links", { token });
}

export async function regenerateCalendarExportLinks(token: string) {
  return apiRequest<CalendarExportLinks>("/calendar/export-links/regenerate", {
    method: "POST",
    token,
  });
}
