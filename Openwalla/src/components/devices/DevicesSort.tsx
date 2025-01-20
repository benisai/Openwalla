import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export type SortOption = "hostname" | "status" | "ip";

interface DevicesSortProps {
  onSortChange: (value: SortOption) => void;
  currentSort: SortOption;
}

const DevicesSort = ({ onSortChange, currentSort }: DevicesSortProps) => {
  return (
    <div className="w-[200px]">
      <Select value={currentSort} onValueChange={(value: SortOption) => onSortChange(value)}>
        <SelectTrigger>
          <SelectValue placeholder="Sort by..." />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="hostname">Sort by Hostname</SelectItem>
          <SelectItem value="status">Sort by Status</SelectItem>
          <SelectItem value="ip">Sort by IP</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
};

export default DevicesSort;
