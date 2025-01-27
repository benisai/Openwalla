import { Card } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ArrowLeft } from "lucide-react";
import { useState, useEffect } from "react";
import axios from "axios";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

interface UsageSettingsProps {
  onDataPlanClick: () => void;
  onResetDateClick: () => void;
}

export function UsageSettings({ onDataPlanClick, onResetDateClick }: UsageSettingsProps) {
  const [dataPlan, setDataPlan] = useState("500");
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const queryClient = useQueryClient();

  useEffect(() => {
    const fetchConfig = async () => {
      try {
        const response = await axios.get('/api/config');
        if (response.data.data_plan_limit) {
          setDataPlan(response.data.data_plan_limit);
        }
      } catch (error) {
        console.error('Failed to fetch config:', error);
      }
    };
    fetchConfig();
  }, []);

  const handleDataPlanClick = async () => {
    try {
      const response = await axios.post('/api/config', {
        data_plan_limit: dataPlan
      });
      
      if (response.status === 200) {
        await queryClient.invalidateQueries({ queryKey: ['config'] });
        await queryClient.invalidateQueries({ queryKey: ['monthly-usage'] });
        toast.success('Data plan updated successfully');
        setIsDialogOpen(false);
      } else {
        throw new Error('Failed to update data plan');
      }
    } catch (error) {
      console.error('Failed to update data plan:', error);
      toast.error('Failed to update data plan');
    }
  };

  return (
    <>
      <Card className="bg-dashboard-card divide-y divide-gray-800">
        <div className="p-4 flex justify-between items-center">
          <h3>Monthly Data Plan</h3>
          <Switch />
        </div>
        <div className="p-4 flex justify-between items-center">
          <h3>Data Plan</h3>
          <Button 
            variant="ghost"
            className="flex items-center gap-2 border border-gray-700 rounded-md px-4 py-2 hover:bg-gray-800"
            onClick={() => setIsDialogOpen(true)}
          >
            {dataPlan} GB
            <ArrowLeft className="w-4 h-4 rotate-180" />
          </Button>
        </div>
      </Card>

      <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
        <DialogContent className="bg-dashboard-card border-none max-w-md">
          <DialogHeader className="space-y-4">
            <div className="flex justify-between items-center">
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={() => setIsDialogOpen(false)}
              >
                Cancel
              </Button>
              <DialogTitle className="text-white">Data Plan</DialogTitle>
              <Button 
                variant="ghost" 
                className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
                onClick={handleDataPlanClick}
              >
                Save
              </Button>
            </div>
          </DialogHeader>

          <div className="mt-8 space-y-4">
            <div>
              <label htmlFor="dataPlan" className="text-gray-400 text-sm block mb-2">
                DATA PLAN (GB)
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
    </>
  );
}