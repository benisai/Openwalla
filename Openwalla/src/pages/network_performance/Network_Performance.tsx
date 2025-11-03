
import { useNavigate } from "react-router-dom";
import { SummaryCard } from "@/pages/network_performance/components/SummaryCard";
import { RecentEventsCard } from "@/pages/network_performance/components/RecentEventsCard";
import { InternetSpeedCard } from "@/pages/network_performance/components/InternetSpeedCard";
import { InternetQualityCard } from "@/pages/network_performance/components/InternetQualityCard";
import { ChevronLeft, Home } from "lucide-react";

export default function NetworkPerformance() {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto">
        <header className="flex items-center justify-between mb-8">
          <button
            onClick={() => navigate(-1)}
            className="text-dashboard-accent hover:opacity-80"
          >
            <ChevronLeft className="w-6 h-6" />
          </button>
          <h1 className="text-xl font-bold">Network Performance</h1>
          <button
            onClick={() => navigate("/")}
            className="text-dashboard-accent hover:opacity-80"
          >
            <Home className="w-6 h-6" />
          </button>
        </header>

        <div className="space-y-4">
          <SummaryCard />
          <RecentEventsCard />
          <InternetQualityCard /> 
          <InternetSpeedCard />
        </div>
      </div>
    </div>
  );
}
