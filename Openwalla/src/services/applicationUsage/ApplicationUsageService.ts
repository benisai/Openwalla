
import { useQuery } from "@tanstack/react-query";
import { ApplicationUsage } from "@/misc/types/applicationUsage";
import { useDevices } from "../DeviceService";
import { fetchDeviceApplicationUsage, fetchDevicesForUsage } from "./ApplicationUsageApi";

/**
 * Hook to get all devices for the application usage page
 */
export function useTopDevicesByUsage() {
  // Use the standard device service to get all devices
  return useDevices();
}

/**
 * Hook to get application usage data for a specific device
 */
export function useDeviceApplicationUsage(mac: string | null) {
  return useQuery({
    queryKey: ['device-application-usage', mac],
    queryFn: async () => {
      if (!mac) throw new Error('No device selected');
      return fetchDeviceApplicationUsage(mac);
    },
    enabled: !!mac,
  });
}

// Re-export the ApplicationUsage type for convenience
export type { ApplicationUsage };
