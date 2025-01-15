import { Card } from "@/components/ui/card";
import { Route } from "lucide-react";

export function RulesCard() {
  return (
    <Card className="bg-dashboard-card p-4 flex flex-col items-center justify-center">
      <Route className="w-6 h-6 text-dashboard-accent mb-2" />
      <span className="text-base md:text-2xl font-bold text-white">0</span>
      <span className="text-sm text-gray-400">Rules</span>
    </Card>
  );
}