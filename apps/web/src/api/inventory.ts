import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

// Gym inventory (ADR-104): machines with their log, consumables with stock
// movements and "running low" reports, and the managers' spend report.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;
type Body<T> = T extends { requestBody: { content: { "application/json": infer B } } } ? B : never;
type Op = operations;
type InventoryOp<Name extends string> = Op[`MilosTrainingWeb.InventoryController.${Name}` & keyof Op];

type MachinesResponse = Json<InventoryOp<"machines">["responses"][200]>;
type MachineResponse = Json<InventoryOp<"update_machine">["responses"][200]>;
type MachineEventsResponse = Json<InventoryOp<"machine_events">["responses"][200]>;
type MachineEventResponse = Json<InventoryOp<"log_machine_event">["responses"][201]>;
type SuppliesResponse = Json<InventoryOp<"supplies">["responses"][200]>;
type SupplyResponse = Json<InventoryOp<"update_supply">["responses"][200]>;
type MovementsResponse = Json<InventoryOp<"movements">["responses"][200]>;
type MovementResponse = Json<InventoryOp<"record_movement">["responses"][201]>;
type LowReportsResponse = Json<InventoryOp<"supply_reports">["responses"][200]>;
type LowReportResponse = Json<InventoryOp<"report_low">["responses"][201]>;
type ReportResponse = Json<InventoryOp<"report">["responses"][200]>;

export type Machine = MachinesResponse["machines"][number];
export type MachineInput = Body<InventoryOp<"create_machine">>;
export type MachineEvent = MachineEventsResponse["events"][number];
export type MachineEventInput = Body<InventoryOp<"log_machine_event">>;
export type MachineEventKind = MachineEvent["kind"];
export type MachineStatus = Machine["status"];
export type Supply = SuppliesResponse["supplies"][number];
export type SupplyInput = Body<InventoryOp<"create_supply">>;
export type SupplyMovement = MovementsResponse["movements"][number];
export type SupplyMovementInput = Body<InventoryOp<"record_movement">>;
export type LowReport = LowReportsResponse["reports"][number];
export type LowReportInput = Body<InventoryOp<"report_low">>;
export type InventoryReport = ReportResponse;
export type StockStatus = Supply["stock_status"];

export const MACHINE_EVENT_KINDS: MachineEventKind[] = ["note", "issue", "out_of_order", "repair_requested", "maintenance", "repaired", "retired"];
export const SEVERITIES = ["low", "medium", "high", "safety"] as const;
export const SYMPTOMS = ["noise", "not_starting", "broken_part", "leak", "electrical", "display", "cleanliness", "other"] as const;
export const CONSUMPTION_SPEEDS = ["fast", "regular", "slow"] as const;
export const LOW_LEVELS = ["running_low", "empty"] as const;

export async function fetchMachines(token: string) {
  const response = await apiRequest<MachinesResponse>("/staff/inventory/machines", { token });
  return response.machines;
}

export async function createMachine(token: string, body: MachineInput) {
  const response = await apiRequest<MachineResponse>("/staff/inventory/machines", { method: "POST", token, body });
  return response.machine;
}

export async function updateMachine(token: string, id: string, body: MachineInput) {
  const response = await apiRequest<MachineResponse>(`/staff/inventory/machines/${id}`, { method: "PATCH", token, body });
  return response.machine;
}

export async function archiveMachine(token: string, id: string) {
  const response = await apiRequest<MachineResponse>(`/staff/inventory/machines/${id}/archive`, { method: "POST", token });
  return response.machine;
}

export async function fetchMachineEvents(token: string, id: string) {
  const response = await apiRequest<MachineEventsResponse>(`/staff/inventory/machines/${id}/events`, { token });
  return response.events;
}

export async function logMachineEvent(token: string, id: string, body: MachineEventInput) {
  return apiRequest<MachineEventResponse>(`/staff/inventory/machines/${id}/events`, { method: "POST", token, body });
}

export async function fetchSupplies(token: string) {
  const response = await apiRequest<SuppliesResponse>("/staff/inventory/supplies", { token });
  return response.supplies;
}

export async function createSupply(token: string, body: SupplyInput) {
  const response = await apiRequest<SupplyResponse>("/staff/inventory/supplies", { method: "POST", token, body });
  return response.supply;
}

export async function updateSupply(token: string, id: string, body: SupplyInput) {
  const response = await apiRequest<SupplyResponse>(`/staff/inventory/supplies/${id}`, { method: "PATCH", token, body });
  return response.supply;
}

export async function archiveSupply(token: string, id: string) {
  const response = await apiRequest<SupplyResponse>(`/staff/inventory/supplies/${id}/archive`, { method: "POST", token });
  return response.supply;
}

export async function fetchSupplyMovements(token: string, id: string) {
  const response = await apiRequest<MovementsResponse>(`/staff/inventory/supplies/${id}/movements`, { token });
  return response.movements;
}

export async function recordSupplyMovement(token: string, id: string, body: SupplyMovementInput) {
  return apiRequest<MovementResponse>(`/staff/inventory/supplies/${id}/movements`, { method: "POST", token, body });
}

export async function fetchLowReports(token: string, id: string) {
  const response = await apiRequest<LowReportsResponse>(`/staff/inventory/supplies/${id}/low-reports`, { token });
  return response.reports;
}

export async function reportSupplyLow(token: string, id: string, body: LowReportInput) {
  return apiRequest<LowReportResponse>(`/staff/inventory/supplies/${id}/low-reports`, { method: "POST", token, body });
}

export async function fetchInventoryReport(token: string, months = 12) {
  return apiRequest<ReportResponse>(`/staff/inventory/report?months=${months}`, { token });
}
