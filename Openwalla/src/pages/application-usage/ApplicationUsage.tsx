
import { useState } from "react";
import { ApplicationUsageHeader } from "./components/ApplicationUsageHeader";
import { UsageTimelineChart } from "./components/UsageTimelineChart";
import { TopApplicationsChart } from "./components/TopApplicationsChart";
import { useDeviceApplicationUsage, useTopDevicesByUsage } from "@/services/ApplicationUsageService";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ApplicationUsageStats } from "./components/ApplicationUsageStats";
import { Button } from "@/components/ui/button";
import { RefreshCw } from "lucide-react";
import { useToast } from "@/components/ui/use-toast";
import { Card } from "@/components/ui/card";

export default function ApplicationUsage() {
  const [selectedDevice, setSelectedDevice] = useState<string | null>(null);
  const { toast } = useToast();

  const { 
    data: devices = [], 
    isLoading: isLoadingDevices,
    isError: isDevicesError,
    error: devicesError,
    refetch: refetchDevices
  } = useTopDevicesByUsage();

  const { 
    data: deviceUsage, 
    isLoading: isLoadingUsage,
    isError: isUsageError,
    error: usageError,
    refetch: refetchUsage
  } = useDeviceApplicationUsage(selectedDevice);

  const handleDeviceChange = (value: string) => {
    setSelectedDevice(value);
  };

  const handleRefresh = async () => {
    try {
      await refetchDevices();
      if (selectedDevice) {
        await refetchUsage();
      }
      toast({
        title: "Data refreshed",
        description: "Application usage data has been updated.",
        variant: "default",
      });
    } catch (error) {
      console.error("Error refreshing data:", error);
      toast({
        title: "Refresh failed",
        description: "Could not refresh application usage data.",
        variant: "destructive",
      });
    }
  };

  // Handle errors
  if (isDevicesError && devicesError) {
    console.error("Error loading devices:", devicesError);
  }

  if (isUsageError && usageError) {
    console.error("Error loading usage data:", usageError);
  }

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto pb-20">
        <ApplicationUsageHeader />

        <div className="flex items-center justify-between mb-6">
          <Select 
            onValueChange={handleDeviceChange} 
            disabled={isLoadingDevices || devices.length === 0}
            value={selectedDevice || undefined}
          >
            <SelectTrigger className="w-[200px] bg-dashboard-card border-gray-700 text-white">
              <SelectValue placeholder="Select Device" />
            </SelectTrigger>
            <SelectContent className="bg-dashboard-card border-gray-700">
              {devices.map((device) => (
                <SelectItem 
                  key={device.mac} 
                  value={device.mac}
                  className="text-white hover:bg-gray-700 focus:bg-gray-700"
                >
                  {device.hostname || device.mac}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          
          <Button 
            variant="outline" 
            size="sm"
            onClick={handleRefresh}
            className="border-gray-700 bg-dashboard-card text-white hover:bg-gray-700"
            disabled={isLoadingDevices || isLoadingUsage}
          >
            <RefreshCw className={`h-4 w-4 mr-2 ${isLoadingDevices || isLoadingUsage ? 'animate-spin' : ''}`} /> 
            Refresh
          </Button>
        </div>

        {isDevicesError && (
          <div className="text-center py-4 px-4 bg-red-900/30 border border-red-900 rounded-md mb-6">
            <p className="text-red-400">Error loading devices. Please try refreshing the page.</p>
          </div>
        )}

        {!selectedDevice && !isLoadingDevices && !isDevicesError && (
          <div className="text-center py-8 text-gray-400">
            <p>Please select a device to view application usage data</p>
          </div>
        )}

        {isLoadingDevices && (
          <div className="text-center py-8">
            <p className="text-gray-400">Loading devices...</p>
          </div>
        )}

        {selectedDevice && (
          <>
            {isUsageError && (
              <div className="text-center py-4 px-4 bg-red-900/30 border border-red-900 rounded-md mb-6">
                <p className="text-red-400">Error loading usage data. Please try refreshing.</p>
              </div>
            )}
          
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
              <UsageTimelineChart 
                data={deviceUsage?.timelineData || []} 
                isLoading={isLoadingUsage} 
              />
              <TopApplicationsChart 
                data={deviceUsage?.applications || []} 
                isLoading={isLoadingUsage} 
              />
            </div>

            <ApplicationUsageStats 
              deviceUsage={deviceUsage} 
              isLoading={isLoadingUsage} 
            />
          </>
        )}
      </div>
    </div>
  );
}
