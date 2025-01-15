import { Card } from "@/components/ui/card";
import { useNavigate } from "react-router-dom";

export function Blocked24() {
  const navigate = useNavigate();

  return (
    <Card 
      className="bg-dashboard-card p-4 cursor-pointer hover:opacity-90 transition-opacity" 
      data-testid="network-card"
      onClick={() => navigate("/blocked-flows")}
    >
      <div className="network-card-content">
        <h3 className="text-gray-400 text-sm mb-2">Blocked</h3>
        <div className="flex items-baseline gap-2">
          <span className="text-xl md:text-2xl font-bold text-white">0</span>
        </div>
      </div>
    </Card>
  );
}