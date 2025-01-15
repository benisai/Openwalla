import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";

export interface Device {
  mac: string;
  ip: string;
  hostname: string;
  dl_speed: number;
  ul_speed: number;
  total_download: number;
  total_upload: number;
  last_seen: number;
}

export const useDevices = () => {
  return useQuery({
    queryKey: ['devices'],
    queryFn: async () => {
      const response = await fetch('/api/devices');
      if (!response.ok) {
        throw new Error('Failed to fetch devices');
      }
      return response.json() as Promise<Device[]>;
    },
    refetchInterval: 30000,
  });
};

export const useDevice = (mac: string) => {
  return useQuery({
    queryKey: ['device', mac],
    queryFn: async () => {
      const response = await fetch(`/api/devices/${mac}`);
      if (!response.ok) {
        throw new Error('Failed to fetch device');
      }
      return response.json() as Promise<Device>;
    },
    refetchInterval: 30000,
  });
};

export const useDeviceActivity = (mac: string) => {
  return useQuery({
    queryKey: ['deviceActivity', mac],
    queryFn: async () => {
      const response = await fetch(`/api/devices/active/${mac}`);
      if (!response.ok) {
        throw new Error('Failed to fetch device activity');
      }
      const data = await response.json();
      return data.isActive;
    },
    refetchInterval: 30000,
  });
};

export const useUpdateDeviceHostname = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ mac, hostname }: { mac: string; hostname: string }) => {
      const response = await fetch(`/api/devices/${mac}/hostname`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ hostname }),
      });
      
      if (!response.ok) {
        throw new Error('Failed to update hostname');
      }
      
      return response.json();
    },
    onSuccess: (_, variables) => {
      // Invalidate and refetch device queries
      queryClient.invalidateQueries({ queryKey: ['devices'] });
      queryClient.invalidateQueries({ queryKey: ['device', variables.mac] });
    },
  });
};