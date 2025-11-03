import { useState } from "react";
import { Recycle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

interface ServiceStatus {
  name: string;
  status: 'running' | 'stopped' | 'error';
  lastError?: string;
}

export function ServicesSection() {
  const [services, setServices] = useState<ServiceStatus[]>([
    { name: 'Internet Monitor', status: 'stopped' },
    { name: 'Netify', status: 'stopped' },
    { name: 'Vnstat', status: 'stopped' },
    { name: 'Netdata', status: 'stopped' }
  ]);
  const { toast } = useToast();

  const handleRestartService = async (serviceName: string) => {
    try {
      // Convert service name to API format
      const apiName = serviceName.toLowerCase().replace(' ', '-');
      const endpoint = `/api/service/restart/${apiName}`;
      const response = await fetch(endpoint, { method: 'POST' });
      
      if (!response.ok) {
        throw new Error(`Failed to restart ${serviceName} service`);
      }

      toast({
        title: `${serviceName} Service`,
        description: `${serviceName} service restarted successfully.`,
      });

      setServices(prev => prev.map(service => 
        service.name === serviceName 
          ? { ...service, status: 'running' }
          : service
      ));
    } catch (error) {
      console.error(`Error restarting ${serviceName} service:`, error);
      toast({
        variant: "destructive",
        title: "Error",
        description: `Failed to restart ${serviceName} service.`,
      });
    }
  };

  const handleRestartAll = async () => {
    toast({
      title: "Restarting Services",
      description: "Restarting all services...",
    });

    for (const service of services) {
      try {
        const apiName = service.name.toLowerCase().replace(' ', '-');
        const endpoint = `/api/service/restart/${apiName}`;
        await fetch(endpoint, { method: 'POST' });
      } catch (error) {
        console.error(`Error restarting ${service.name}:`, error);
      }
    }

    toast({
      title: "Services Restarted",
      description: "All services have been restarted successfully.",
    });

    setServices(prev => prev.map(service => ({ ...service, status: 'running' })));
  };

  return (
    <div 
      className="flex items-center justify-between p-4 cursor-pointer hover:bg-[#2A303C] transition-colors"
      role="button"
    >
      <Dialog>
        <DialogTrigger className="flex items-center justify-between w-full">
          <span className="text-lg">Services</span>
        </DialogTrigger>
        <DialogContent className="sm:max-w-[425px] bg-dashboard-card border-none">
          <DialogHeader>
            <div className="flex items-center justify-between">
              <DialogTitle className="text-white">Services</DialogTitle>
              <Button
                variant="ghost"
                size="icon"
                onClick={handleRestartAll}
                className="text-dashboard-accent hover:text-dashboard-accent/80"
                title="Restart All Services"
              >
                <Recycle className="w-5 h-5" />
              </Button>
            </div>
          </DialogHeader>
          <div className="space-y-2">
            {services.map((service) => (
              <div 
                key={service.name}
                className="flex items-center justify-between p-3 bg-[#222632] rounded-lg border border-gray-800"
              >
                <div className="flex items-center space-x-3">
                  <span>{service.name}</span>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => handleRestartService(service.name)}
                  className="text-dashboard-accent hover:text-dashboard-accent/80"
                >
                  <Recycle className="w-4 h-4" />
                </Button>
              </div>
            ))}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}