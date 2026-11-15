// Types for midas-settings.js, for the Worker and the tests. The script itself is plain JS so every
// Sidekick page and tools.js can paste the same file.

export type SettingType = "colour" | "size" | "show" | "dateFormat" | "choice";
export type SettingValue = string | boolean;

export type SettingEntry = {
  key: string;
  label: string;
  type: SettingType;
  part: string;
  default: SettingValue;
  values?: SettingValue[];
  selector?: string;
  css?: string | string[];
  tools?: string[];
};

export type SettingsCatalogue = {
  entries: SettingEntry[];
  alsoSet?: Record<string, unknown>;
};

export type CheckedValue = { value: SettingValue; problem?: undefined } | { problem: string; value?: undefined };

export type ToolOutcome = {
  ops?: { op: "set"; key: string; value: Record<string, unknown> }[];
  refused?: string;
  result: { text: string; key?: string; value?: SettingValue };
};

export type MidasSettingsModule = {
  RECORD_KEY: string;
  TYPES: SettingType[];
  SIZES: string[];
  SIZE_ZOOM: Record<string, number>;
  DATE_FORMATS: string[];
  catalogueProblems(catalogue: unknown): string[];
  entryFor(catalogue: unknown, key: string): SettingEntry | null;
  /** The values an entry may take; null for a colour (any #RRGGBB). */
  allowedValues(entry: SettingEntry): SettingValue[] | null;
  checkValue(entry: SettingEntry | null, said: unknown): CheckedValue;
  valuesFrom(catalogue: unknown, record: unknown): Record<string, SettingValue>;
  /** settings:self with these changes over it; a change to null removes the key. */
  recordWith(catalogue: unknown, record: unknown, changes: Record<string, SettingValue | null>): Record<string, unknown>;
  propertySchemaFor(entry: SettingEntry): Record<string, unknown>;
  cssFor(catalogue: unknown, record: unknown): string;
  formatDate(catalogue: unknown, record: unknown, key: string, date: Date): string | null;
  formatDateAs(format: string, date: Date): string | null;
  setSettingFrom(catalogue: unknown, input: unknown, records: unknown): ToolOutcome;
  offSettingFor(catalogue: unknown, record: unknown, toolName: string): SettingEntry | null;
  attachTools<T>(tools: T, options: { sidekickId: string; catalogue: unknown; ownKeys?: string[] }): T;
  watch(options: unknown): unknown;
};

declare const MidasSettings: MidasSettingsModule;
export default MidasSettings;
