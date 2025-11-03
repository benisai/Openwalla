
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useState, useEffect } from "react";
import { useToast } from "@/hooks/use-toast";

interface InternetQualityTestOptionsProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function InternetQualityTestOptions({ open, onOpenChange }: InternetQualityTestOptionsProps) {
  const [pingAddress, setPingAddress] = useState('1.1.1.1');
  const [latencyThreshold, setLatencyThreshold] = useState('100');
  const { toast } = useToast();

  useEffect(() => {
    const loadConfig = async () => {
      try {
        const response = await fetch('/api/config');
        if (!response.ok) {
          throw new Error('Failed to load config');
        }
        const config = await response.json();
        console.log('Loaded server config:', config);
        
        setPingAddress(config.ping_address || '1.1.1.1');
        setLatencyThreshold((config.latency_threshold || 100).toString());
      } catch (error) {
        console.error('Error loading config:', error);
        toast({
          variant: "destructive",
          title: "Error loading settings",
          description: "Could not load settings from server.",
        });
      }
    };

    if (open) {
      loadConfig();
    }
  }, [open, toast]);

  const handleSave = async () => {
    try {
      const latencyValue = parseInt(latencyThreshold);
      if (isNaN(latencyValue) || latencyValue <= 0) {
        toast({
          variant: "destructive",
          title: "Invalid input",
          description: "Please enter a valid positive number for latency threshold.",
        });
        return;
      }

      const config = {
        ping_address: pingAddress,
        latency_threshold: latencyValue
      };
      
      const response = await fetch('/api/config', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(config),
      });

      if (!response.ok) {
        throw new Error('Failed to save config');
      }

      // Restart services after config update
      await fetch('/api/ping/restart', { method: 'POST' });

      toast({
        title: "Settings saved",
        description: "Configuration updated successfully.",
      });

      onOpenChange(false);
    } catch (error) {
      console.error('Error saving config:', error);
      toast({
        variant: "destructive",
        title: "Error saving settings",
        description: "Could not save settings to server.",
      });
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
            >
              Cancel
            </Button>
            <DialogTitle className="text-white">Internet Quality Settings</DialogTitle>
            <Button 
              variant="ghost" 
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={handleSave}
            >
              Save
            </Button>
          </div>
        </DialogHeader>

        <div className="mt-8 space-y-4">
          <div>
            <label className="text-gray-400 text-sm block mb-2">
              PING ADDRESS
            </label>
            <Input
              value={pingAddress}
              onChange={(e) => setPingAddress(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
              placeholder="1.1.1.1"
            />
          </div>
          
          <div>
            <label className="text-gray-400 text-sm block mb-2">
              LATENCY THRESHOLD (MS)
            </label>
            <Input
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              value={latencyThreshold}
              onChange={(e) => setLatencyThreshold(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
              placeholder="100"
            />
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
