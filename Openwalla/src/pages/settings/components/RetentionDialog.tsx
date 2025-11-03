import { useState, useEffect } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { updateConfig, getConfig } from "@/services/ConfigService";
import { useQueryClient } from "@tanstack/react-query";

interface RetentionDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function RetentionDialog({ open, onOpenChange }: RetentionDialogProps) {
  const [retentionDays, setRetentionDays] = useState("7");
  const [isLoading, setIsLoading] = useState(false);
  const { toast } = useToast();
  const queryClient = useQueryClient();

  useEffect(() => {
    if (open) {
      loadCurrentValue();
    }
  }, [open]);

  const loadCurrentValue = async () => {
    try {
      const config = await getConfig();
      setRetentionDays(config.retention_days || "7");
    } catch (error) {
      console.error("Failed to load retention days:", error);
    }
  };

  const handleSave = async () => {
    const days = parseInt(retentionDays);
    
    if (isNaN(days) || days < 1) {
      toast({
        variant: "destructive",
        title: "Invalid Input",
        description: "Please enter a valid number of days (minimum 1)",
      });
      return;
    }

    setIsLoading(true);
    try {
      await updateConfig({ retention_days: retentionDays });
      queryClient.invalidateQueries({ queryKey: ['config'] });
      toast({
        title: "Success",
        description: `Data retention updated to ${days} days`,
      });
      onOpenChange(false);
    } catch (error) {
      toast({
        variant: "destructive",
        title: "Error",
        description: "Failed to update retention days",
      });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="bg-dashboard-card border-none max-w-md">
        <DialogHeader className="space-y-4">
          <div className="flex justify-between items-center">
            <Button 
              variant="ghost" 
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={() => onOpenChange(false)}
              disabled={isLoading}
            >
              Cancel
            </Button>
            <DialogTitle className="text-white">Data Retention</DialogTitle>
            <Button 
              variant="ghost" 
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={handleSave}
              disabled={isLoading}
            >
              {isLoading ? "Saving..." : "Save"}
            </Button>
          </div>
        </DialogHeader>

        <div className="mt-8 space-y-4">
          <div>
            <label className="text-gray-400 text-sm block mb-2">
              RETENTION PERIOD (DAYS)
            </label>
            <Input
              id="retention-days"
              type="number"
              min="1"
              value={retentionDays}
              onChange={(e) => setRetentionDays(e.target.value)}
              placeholder="7"
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
            />
            <p className="text-sm text-gray-400 mt-3">
              Data older than {retentionDays} day{retentionDays !== "1" ? "s" : ""} will be removed from:
            </p>
            <ul className="text-sm text-gray-400 list-disc list-inside ml-2 mt-2">
              <li>Network flows</li>
              <li>Notifications</li>
              <li>Ping statistics</li>
              <li>Vnstat hourly data</li>
            </ul>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
