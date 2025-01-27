import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";

interface FlowsSearchProps {
  searchQuery: string;
  setSearchQuery: (query: string) => void;
}

export const FlowsSearch = ({ searchQuery, setSearchQuery }: FlowsSearchProps) => {
  return (
    <div className="relative mb-6">
      <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-4 w-4" />
      <Input
        type="text"
        placeholder="Search flows..."
        value={searchQuery}
        onChange={(e) => setSearchQuery(e.target.value)}
        className="pl-10 bg-dashboard-card border-gray-700 text-white"
      />
    </div>
  );
};