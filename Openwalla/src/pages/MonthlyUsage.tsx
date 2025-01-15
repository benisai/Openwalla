import { ArrowLeft } from "lucide-react";
import { Link } from "react-router-dom";
import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Calendar } from "@/components/ui/calendar";
import { format } from "date-fns";
import { UsageStats } from "@/components/monthly-usage/UsageStats";
import { UsageChart } from "@/components/monthly-usage/UsageChart";
import { UsageSettings } from "@/components/monthly-usage/UsageSettings";

const MonthlyUsage = () => {
  const [isDataPlanOpen, setIsDataPlanOpen] = useState(false);
  const [isResetDateOpen, setIsResetDateOpen] = useState(false);
  const [dataPlan, setDataPlan] = useState("2.00");
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(new Date());
  const [selectedTime, setSelectedTime] = useState("00:00");

  const formattedResetDate = selectedDate 
    ? `${format(selectedDate, 'do')} of every month`
    : "1st of every month";

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto pb-20">
        {/* Header */}
        <header className="flex items-center gap-4 mb-6">
          <Link to="/" className="text-dashboard-accent">
            <ArrowLeft className="w-6 h-6" />
          </Link>
          <h1 className="text-2xl font-bold">Data Usage</h1>
        </header>

        <p className="text-gray-400 mb-8">
          Monitor uploads, downloads, and total bandwidth usage in your network.
        </p>

        <UsageStats />
        <UsageChart />
        <UsageSettings 
          onDataPlanClick={() => setIsDataPlanOpen(true)}
          onResetDateClick={() => setIsResetDateOpen(true)}
        />
      </div>

      {/* Data Plan Dialog */}
      <Dialog open={isDataPlanOpen} onOpenChange={setIsDataPlanOpen}>
        <DialogContent className="bg-dashboard-card border-none max-w-md">
          <DialogHeader className="space-y-4">
            <div className="flex justify-between items-center">
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => setIsDataPlanOpen(false)}
              >
                Cancel
              </Button>
              <DialogTitle className="text-white">Data Plan</DialogTitle>
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => setIsDataPlanOpen(false)}
              >
                Save
              </Button>
            </div>
          </DialogHeader>

          <div className="mt-8 space-y-4">
            <div>
              <label htmlFor="dataPlan" className="text-gray-400 text-sm block mb-2">
                DATA PLAN (TB)
              </label>
              <Input
                id="dataPlan"
                type="number"
                value={dataPlan}
                onChange={(e) => setDataPlan(e.target.value)}
                className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
              />
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reset Date Dialog */}
      <Dialog open={isResetDateOpen} onOpenChange={setIsResetDateOpen}>
        <DialogContent className="bg-dashboard-card border-none max-w-md">
          <DialogHeader className="space-y-4">
            <div className="flex justify-between items-center">
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => setIsResetDateOpen(false)}
              >
                Cancel
              </Button>
              <DialogTitle className="text-white">Reset Date</DialogTitle>
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => setIsResetDateOpen(false)}
              >
                Save
              </Button>
            </div>
          </DialogHeader>

          <div className="mt-8 space-y-6">
            <div>
              <label className="text-gray-400 text-sm block mb-4">
                SELECT DAY
              </label>
              <Calendar
                mode="single"
                selected={selectedDate}
                onSelect={setSelectedDate}
                className="bg-[#222632] text-white rounded-lg p-3"
              />
            </div>
            <div>
              <label htmlFor="time" className="text-gray-400 text-sm block mb-2">
                SELECT TIME
              </label>
              <Input
                id="time"
                type="time"
                value={selectedTime}
                onChange={(e) => setSelectedTime(e.target.value)}
                className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
              />
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MonthlyUsage;