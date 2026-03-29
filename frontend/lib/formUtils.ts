export interface PillConfig {
  description: string;
  tags: string[];
  frequency: string | null;
  frequencyLabel: string;
  rankLabel: string;
  isCreateMode: boolean;
}

export interface VisiblePill {
  key: "description" | "tags" | "frequency" | "rank";
  label: string;
  isSet: boolean;
}

export function getVisiblePills(config: PillConfig): VisiblePill[] {
  const pills: VisiblePill[] = [];

  if (!config.description) {
    pills.push({ key: "description", label: "Description", isSet: false });
  }

  if (config.tags.length === 0) {
    pills.push({ key: "tags", label: "Tags", isSet: false });
  }

  const frequencyIsSet = config.frequency !== null;
  pills.push({
    key: "frequency",
    label: frequencyIsSet ? config.frequency! : config.frequencyLabel,
    isSet: frequencyIsSet,
  });

  pills.push({ key: "rank", label: config.rankLabel, isSet: false });

  return pills;
}
