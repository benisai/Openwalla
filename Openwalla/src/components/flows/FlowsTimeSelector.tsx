import { ChevronDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useNavigate } from "react-router-dom";

interface FlowsTimeSelectorProps {
  selectedTime: string;
  setSelectedTime: (time: string) => void;
  timeOptions: string[];
}

export const FlowsTimeSelector = ({ selectedTime, setSelectedTime, timeOptions }: FlowsTimeSelectorProps) => {
  const navigate = useNavigate();
  
  return (
    <div className="flex justify-between items-center mb-8">
      <DropdownMenu>
        <DropdownMenuTrigger className="flex items-center gap-2 hover:opacity-80">
          <span className="text-lg font-semibold">Last {selectedTime}</span>
          <ChevronDown className="w-4 h-4 text-gray-400" />
        </DropdownMenuTrigger>
        <DropdownMenuContent className="bg-dashboard-card border-gray-700">
          {timeOptions.map((time) => (
            <DropdownMenuItem
              key={time}
              className="text-white hover:bg-gray-700/50 cursor-pointer"
              onClick={() => setSelectedTime(time)}
            >
              {time}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
      <Button
        variant="link"
        className="text-blue-500 hover:text-blue-400"
        onClick={() => navigate("/blocked-flows")}
      >
        View Blocked
      </Button>
    </div>
  );
};