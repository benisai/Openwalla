import { Card } from "@/components/ui/card";
import BottomNav from "@/components/dashboard/BottomNav";
import { useNavigate } from "react-router-dom";
import { ChevronLeft } from "lucide-react";

const Rules = () => {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto pb-20">
        {/* Header */}
        <div className="flex items-center mb-6">
          <button onClick={() => navigate(-1)} className="mr-4">
            <ChevronLeft className="h-6 w-6" />
          </button>
          <h1 className="text-xl font-bold">Rules</h1>
        </div>

        {/* Rules List */}
        <Card className="bg-dashboard-card p-4">
          <div className="space-y-4">
            <div className="text-center text-gray-400">
              No rules configured
            </div>
          </div>
        </Card>
      </div>

      {/* Navigation */}
      <BottomNav />
    </div>
  );
};

export default Rules;