
import { Button } from "@/components/ui/button";
import { ChevronLeft, Home } from "lucide-react";
import { useNavigate } from "react-router-dom";

export function ApplicationUsageHeader() {
  const navigate = useNavigate();

  return (
    <header className="flex items-center justify-between mb-8">
      <button
        onClick={() => navigate(-1)}
        className="text-dashboard-accent hover:opacity-80"
      >
        <ChevronLeft className="w-6 h-6" />
      </button>
      <h1 className="text-xl font-bold">Application Usage</h1>
      <button
        onClick={() => navigate("/")}
        className="text-dashboard-accent hover:opacity-80"
      >
        <Home className="w-6 h-6" />
      </button>
    </header>
  );
}
