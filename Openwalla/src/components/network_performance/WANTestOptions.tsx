import { Switch } from "@/components/ui/switch";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Globe, ChevronRight } from "lucide-react";
import { useState } from "react";
import { Calendar } from "@/components/ui/calendar";
import { Input } from "@/components/ui/input";
import { format } from "date-fns";

interface WANTestOptionsProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function WANTestOptions({ open, onOpenChange }: WANTestOptionsProps) {
  const [isScheduleOpen, setIsScheduleOpen] = useState(false);
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(new Date());
  const [selectedTime, setSelectedTime] = useState("08:00");

  const formattedSchedule = selectedDate 
    ? `Every ${format(selectedDate, 'EEEE')} at ${selectedTime}`
    : "Not scheduled";

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="bg-dashboard-card border-none max-w-md">
          <DialogHeader className="space-y-4">
            <div className="flex justify-between items-center">
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => onOpenChange(false)}
              >
                Cancel
              </Button>
              <DialogTitle className="text-white">Test Options</DialogTitle>
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              >
                Save
              </Button>
            </div>
          </DialogHeader>

          <div className="mt-8">
            <h3 className="text-gray-400 mb-4">AUTOMATIC TESTING</h3>
            
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Globe className="h-5 w-5 text-gray-400" />
                  <span className="text-white">WAN</span>
                </div>
                <Switch />
              </div>
              
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Globe className="h-5 w-5 text-gray-400" />
                  <span className="text-white">Wireless</span>
                </div>
                <Switch />
              </div>
            </div>

            <div className="mt-8">
              <Button 
                variant="ghost" 
                className="w-full bg-[#222632] text-white justify-between hover:bg-[#222632]/90 py-6"
                onClick={() => setIsScheduleOpen(true)}
              >
                <span>Schedule</span>
                <div className="flex items-center gap-2 text-gray-400">
                  <span>{formattedSchedule}</span>
                  <ChevronRight className="h-5 w-5" />
                </div>
              </Button>
              <p className="text-gray-400 text-sm mt-2">
                The test will happen within the hour after the scheduled time.
              </p>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={isScheduleOpen} onOpenChange={setIsScheduleOpen}>
        <DialogContent className="bg-dashboard-card border-none max-w-md">
          <DialogHeader className="space-y-4">
            <div className="flex justify-between items-center">
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => setIsScheduleOpen(false)}
              >
                Cancel
              </Button>
              <DialogTitle className="text-white">Schedule</DialogTitle>
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => {
                  setIsScheduleOpen(false);
                }}
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
                className="bg-[#222632] border-none text-white"
              />
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}