
import { useQuery } from "@tanstack/react-query";

export interface RxTxData {
  mac: string;
  rx_diff: number;
  tx_diff: number;
  timestamp: number;
}

export const useDevicesRxTx = (timeframe: string) => {
  return useQuery({
    queryKey: ['devices-rx-tx', timeframe],
    queryFn: async () => {
      const response = await fetch(`/api/devices/rx-tx/data?timeframe=${timeframe}`);
      if (!response.ok) {
        throw new Error('Failed to fetch RX/TX data');
      }
      return response.json() as Promise<RxTxData[]>;
    },
    refetchInterval: timeframe === 'real-time' ? 1000 : 5000,
  });
};
