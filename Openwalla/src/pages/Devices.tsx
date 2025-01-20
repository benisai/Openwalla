import { useState } from "react";
import { Button } from "@/components/ui/button";
import DevicesHeader from "@/components/devices/DevicesHeader";
import DevicesSearch from "@/components/devices/DevicesSearch";
import DevicesList from "@/components/devices/DevicesList";
import { TopClientsTable } from "@/components/devices/TopClientsTable";
import { useDevices } from "@/services/DeviceService";
import { useToast } from "@/components/ui/use-toast";
import DevicesSort, { SortOption } from "@/components/devices/DevicesSort";
import { Device } from "@/types/device";

type ViewType = "all" | "top-clients";

const Devices = () => {
  const [currentView, setCurrentView] = useState<ViewType>("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [currentSort, setCurrentSort] = useState<SortOption>("hostname");
  const { data: devices, error, isLoading } = useDevices();
  const { toast } = useToast();

  if (error) {
    toast({
      variant: "destructive",
      title: "Error",
      description: "Failed to fetch devices"
    });
  }

  const sortDevices = (devices: Device[]) => {
    return [...devices].sort((a, b) => {
      switch (currentSort) {
        case "hostname":
          return a.hostname.localeCompare(b.hostname);
        case "ip":
          return a.ip.localeCompare(b.ip);
        case "status":
          // Sort by active status (requires the isActive property from useDeviceActivity)
          // We'll sort alphabetically for now since status is determined per-device
          return a.hostname.localeCompare(b.hostname);
        default:
          return 0;
      }
    });
  };

  const filteredDevices = devices?.filter((device) => {
    const searchLower = searchQuery.toLowerCase();
    return (
      device.hostname.toLowerCase().includes(searchLower) ||
      device.ip.toLowerCase().includes(searchLower) ||
      device.mac.toLowerCase().includes(searchLower)
    );
  }) ?? [];

  const sortedAndFilteredDevices = sortDevices(filteredDevices);

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto pb-20">
        <DevicesHeader />
        <div className="flex flex-col md:flex-row gap-4 mb-6">
          <div className="flex-1">
            <DevicesSearch searchQuery={searchQuery} setSearchQuery={setSearchQuery} />
          </div>
          <DevicesSort currentSort={currentSort} onSortChange={setCurrentSort} />
        </div>

        <div className="flex gap-2 mb-6 bg-dashboard-card rounded-lg p-1">
          <Button
            variant="ghost"
            className={`flex-1 ${
              currentView === "all"
                ? "text-white bg-gray-700"
                : "text-gray-400 hover:text-white hover:bg-gray-700"
            }`}
            onClick={() => setCurrentView("all")}
          >
            All
          </Button>
          <Button
            variant="ghost"
            className={`flex-1 ${
              currentView === "top-clients"
                ? "text-white bg-gray-700"
                : "text-gray-400 hover:text-white hover:bg-gray-700"
            }`}
            onClick={() => setCurrentView("top-clients")}
          >
            Top Clients
          </Button>
        </div>

        <div className="space-y-4">
          {currentView === "top-clients" && <TopClientsTable />}
          {currentView === "all" && (
            isLoading ? (
              <div className="text-center text-gray-400">Loading devices...</div>
            ) : (
              <DevicesList devices={sortedAndFilteredDevices} />
            )
          )}
        </div>
      </div>
    </div>
  );
};

export default Devices;
