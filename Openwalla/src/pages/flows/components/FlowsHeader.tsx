import { ChevronDown, ChevronLeft, Home } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

interface FlowsHeaderProps {
  selectedTime: string;
  setSelectedTime: (time: string) => void;
  timeOptions: string[];
  title?: string;
}

export const FlowsHeader = ({ selectedTime, setSelectedTime, timeOptions, title = "Network Flows" }: FlowsHeaderProps) => {
  const navigate = useNavigate();

  return (
    <header className="flex items-center justify-between mb-8">
      <button
        onClick={() => navigate(-1)}
        className="text-dashboard-accent hover:opacity-80"
      >
        <ChevronLeft className="w-6 h-6" />
      </button>
      <h1 className="text-xl font-bold">{title}</h1>
      <button
        onClick={() => navigate("/")}
        className="text-dashboard-accent hover:opacity-80"
      >
        <Home className="w-6 h-6" />
      </button>
    </header>
  );
};