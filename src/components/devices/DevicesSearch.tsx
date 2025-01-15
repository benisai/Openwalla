import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";

interface DevicesSearchProps {
  searchQuery: string;
  setSearchQuery: (query: string) => void;
}

const DevicesSearch = ({ searchQuery, setSearchQuery }: DevicesSearchProps) => {
  return (
    <div className="mb-6">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
        <Input
          type="text"
          placeholder="Search devices..."
          className="w-full pl-10 bg-dashboard-card border-gray-700 text-white placeholder:text-gray-400"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
        />
      </div>
    </div>
  );
};

export default DevicesSearch;